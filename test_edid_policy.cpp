#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <initializer_list>
#include "source/kexts/NVRMFB/fb/nvrm-edid-hidpi-policy.h"

struct Mode { unsigned nominalWidth, nominalHeight, flags; unsigned short imageWidth, imageHeight; };
static constexpr unsigned hiRes = 0x00800000;
static void checksum(unsigned char *e) {
    unsigned sum=0; for(unsigned i=0;i<127;++i)sum+=e[i];e[127]=static_cast<unsigned char>(0u-sum);
}
static void makeEdid(unsigned char *e, unsigned w, unsigned h, unsigned mmW, unsigned mmH) {
    std::memset(e,0,128);
    const unsigned char hdr[8]={0,255,255,255,255,255,255,0};std::memcpy(e,hdr,8);
    e[18]=1;e[19]=4;e[20]=0x80;e[21]=mmW/10;e[22]=mmH/10;e[24]=2;
    auto *d=e+54;d[0]=1;d[2]=w&255;d[4]=(w>>8)<<4;d[5]=h&255;d[7]=(h>>8)<<4;
    d[12]=mmW&255;d[13]=mmH&255;d[14]=((mmW>>8)<<4)|(mmH>>8);
    checksum(e);
}
static bool apply(Mode& m,unsigned char *e,unsigned len=128,unsigned maxW=8192,unsigned maxH=8192,bool enabled=true) {
    return nvrmApplyEdidHiDpiMetadata(&m,e,len,maxW,maxH,enabled,hiRes);
}
static void unchanged(Mode m,unsigned char *e,unsigned len=128,bool enabled=true) {
    const Mode old=m; assert(!apply(m,e,len,8192,8192,enabled));assert(!std::memcmp(&m,&old,sizeof m));
}
int main() {
    unsigned char e[128];
    for(auto p : {Mode{2560,1600,3,344,215},Mode{1920,1080,3,309,174},Mode{3840,2160,3,600,340},
                  Mode{3440,1440,3,800,335},Mode{1440,2560,3,215,344},Mode{1366,768,3,310,174}}) {
        makeEdid(e,p.nominalWidth,p.nominalHeight,p.imageWidth,p.imageHeight);
        Mode m={p.nominalWidth,p.nominalHeight,3,0,0}; assert(apply(m,e));
        assert(m.imageWidth==p.imageWidth && m.imageHeight==p.imageHeight && m.flags==(3|hiRes));
        assert(m.nominalWidth==p.nominalWidth && m.nominalHeight==p.nominalHeight);
        unchanged(p,e,128,false);
        for(unsigned len=0;len<128;++len)unchanged(p,e,len);
        for(unsigned i=0;i<128;++i) for(unsigned bit=0;bit<8;++bit) {
            e[i]^=1u<<bit;unchanged(p,e);e[i]^=1u<<bit;
        }
    }
    makeEdid(e,2560,1600,344,215);
    for(auto d:{Mode{1280,800,3,0,0},Mode{3200,1800,3,0,0},Mode{3201,2000,3,0,0},Mode{4000,2500,3,0,0}}) {
        auto m=d; assert(apply(m,e,128,3840,2160));assert(m.flags==3 && m.imageWidth==344);
    }
    Mode m={3200,2000,0x02000003,0,0}; assert(apply(m,e,128,3840,2160));assert(m.flags==0x02800003);
    m={2560,1600,3,0,0};assert(apply(m,e,128,0,0));assert(m.flags==3 && m.imageWidth==344);
    m={2560,1600,3,400,250};assert(apply(m,e));assert(m.imageWidth==400 && m.imageHeight==250);
    m={2560,1600,3,400,0};assert(apply(m,e));assert(m.imageWidth==344 && m.imageHeight==215);
    // Millimetre DTD values take priority over rounded base-block centimetres.
    makeEdid(e,2560,1600,344,215);e[21]=34;e[22]=22;checksum(e);
    m={2560,1600,3,0,0};assert(apply(m,e));assert(m.imageWidth==344 && m.imageHeight==215);
    // Missing DTD dimensions fall back to valid base-block centimetres.
    e[66]=e[67]=e[68]=0;checksum(e);m={2560,1600,3,0,0};assert(apply(m,e));assert(m.imageWidth==340 && m.imageHeight==220 && m.flags==(3|hiRes));
    // No preferred timing, descriptor strings or interlacing: dimensions only.
    for(unsigned kind=0;kind<3;++kind) {
        makeEdid(e,2560,1600,344,215);
        if(kind==0)e[24]=0;
        if(kind==1)e[54]=e[55]=0;
        if(kind==2)e[71]=0x80;
        checksum(e);m={2560,1600,3,0,0};assert(apply(m,e));assert(m.imageWidth==340 && m.imageHeight==210 && m.flags==3);
    }
    // EDID 1.4 aspect-only size encoding is not a physical size.
    makeEdid(e,2560,1600,0,0);e[21]=0;e[22]=160;checksum(e);unchanged(m,e);
    for(unsigned kind=0;kind<4;++kind) {
        makeEdid(e,2560,1600,344,215);
        if(kind==0)e[18]=2;
        if(kind==1)e[19]=2;
        if(kind==2)e[20]=0;
        if(kind==3)e[0]=1;
        checksum(e);unchanged(m,e);
    }
    makeEdid(e,2560,1600,344,215);e[19]=3;checksum(e);m={2560,1600,3,0,0};assert(apply(m,e));
    unchanged(m,nullptr);
    assert(!nvrmApplyEdidHiDpiMetadata<Mode>(nullptr,e,128,3840,2160,true,hiRes));
    assert(!nvrmReadEdidPanelMetadata(e,128,nullptr));
    // Bounded arbitrary-input exercise with valid headers/checksums under sanitizers.
    uint32_t rng=0x62d31579;
    for(unsigned trial=0;trial<100000;++trial) {
        for(unsigned i=0;i<128;++i){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;e[i]=rng&255;}
        if(trial&1){const unsigned char h[8]={0,255,255,255,255,255,255,0};std::memcpy(e,h,8);e[18]=1;e[19]=4;e[20]|=0x80;checksum(e);}
        m={2560,1600,3,0,0};apply(m,e);
        assert(m.nominalWidth==2560 && m.nominalHeight==1600 && (m.flags & ~hiRes)==3);
        assert(m.imageWidth<=4095 && m.imageHeight<=4095);
    }
    puts("PASS: multiple panel geometries, EDID validation/fallbacks, caps/aspect, disabled/malformed inputs and 100000 bounded-input trials.");
}
