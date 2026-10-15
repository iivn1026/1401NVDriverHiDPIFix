#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <initializer_list>
#include "nvrm-edid-hidpi-policy.h"
struct Timing {
    unsigned horizontalActive, verticalActive, horizontalScaled, verticalScaled;
    unsigned horizontalScaledInset, verticalScaledInset;
    unsigned horizontalBorderLeft, horizontalBorderRight, verticalBorderTop, verticalBorderBottom;
    unsigned scalerFlags, detailedTimingModeID;
    unsigned horizontalBlanking, verticalBlanking, horizontalSyncOffset, verticalSyncOffset;
    unsigned dscCompressedBitsPerPixel, dscSliceWidth, dscSliceHeight;
    unsigned long long pixelClock;
};
static unsigned add(Timing *t,unsigned n=1,unsigned cap=16,unsigned long long bytes=256ull*1024*1024) {
    return nvrmAppendScaledHiDpiTimings(t,n,cap,0,7680,4320,bytes,256,1);
}
static Timing seed(unsigned w,unsigned h) {
    Timing t={};t.horizontalActive=w;t.verticalActive=h;t.pixelClock=241500000;
    t.horizontalBlanking=160;t.verticalBlanking=41;t.detailedTimingModeID=0x10000;
    t.dscCompressedBitsPerPixel=257;t.dscSliceWidth=w/4;t.dscSliceHeight=h;
    return t;
}
int main() {
    Timing t[16]={};t[0]=seed(2560,1440);auto original=t[0];
    unsigned n=add(t);assert(n==6);bool have1600=false,have1920=false,have2048=false,have2560=false;
    for(unsigned i=1;i<n;i++) {
        have1600|=t[i].horizontalScaled==3200&&t[i].verticalScaled==1800;
        have1920|=t[i].horizontalScaled==3840&&t[i].verticalScaled==2160;
        have2048|=t[i].horizontalScaled==4096&&t[i].verticalScaled==2304;
        have2560|=t[i].horizontalScaled==5120&&t[i].verticalScaled==2880;
        auto check=t[i];check.horizontalScaled=check.verticalScaled=check.scalerFlags=0;
        check.detailedTimingModeID=original.detailedTimingModeID;
        assert(!std::memcmp(&check,&original,sizeof check)); // physical timings/DSC unchanged
        assert(t[i].detailedTimingModeID<0x80000000u);
    }
    assert(have1600&&have1920&&have2048&&have2560);
    assert(add(t,n)==n); // repeated enumeration does not duplicate
    t[0]=seed(2560,1600);n=add(t);bool have1000=false,have1200=false;
    for(unsigned i=1;i<n;i++){have1000|=t[i].horizontalScaled==3200&&t[i].verticalScaled==2000;have1200|=t[i].horizontalScaled==3840&&t[i].verticalScaled==2400;}
    assert(have1000&&have1200);
    for(auto wh : {seed(1920,1080),seed(3840,2160),seed(3440,1440),seed(1440,2560),seed(1366,768)}) {
        std::memset(t,0,sizeof t);t[0]=wh;n=add(t);
        for(unsigned i=1;i<n;i++)assert((uint64_t)t[i].horizontalScaled*wh.verticalActive==(uint64_t)t[i].verticalScaled*wh.horizontalActive);
    }
    t[0]=seed(2560,1440);assert(add(t,1,1)==1);assert(add(t,1,16,0)==1);
    assert(nvrmAppendScaledHiDpiTimings(t,1,16,0,2560,1440,256ull<<20,256,1)==1);
    t[0].horizontalScaled=1;assert(add(t)==1);t[0]=seed(2560,1440);t[0].horizontalScaledInset=1;assert(add(t)==1);
    t[0]=seed(2560,1440);t[0].pixelClock=0;assert(add(t)==1);
    assert(nvrmAppendScaledHiDpiTimings<Timing>(nullptr,0,0,0,0,0,0,0,0)==0);
    unsigned w=123,h=456;
    assert(!nvrmHiDpiBackingSize(2560,1440,0,7680,4320,256ull<<20,3,&w,&h)&&w==123&&h==456);
    uint32_t rng=0x19201080;
    for(unsigned trial=0;trial<100000;trial++) {
        rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;unsigned nw=rng;
        rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;unsigned nh=rng;
        if(trial&1){nw=nw%8000;nh=nh%5000;}
        if(nvrmHiDpiBackingSize(nw,nh,trial%8,7680,4320,256ull<<20,256,&w,&h)) {
            assert(w>nw&&h>nh&&!(w&1)&&!(h&1)&&w<=7680&&h<=4320);
            assert(((uint64_t)w*4+255)/256*256*h <= (256ull<<20));
            assert((uint64_t)w*nh==(uint64_t)h*nw);
        }
    }
    puts("PASS: higher HiDPI modes, exact panel timing preservation, duplicates/capacity, memory/aspect caps and 100000 fuzz trials.");
}
