// Opt-in display metadata experiment for digital EDID 1.3/1.4 displays.
// EDID metadata plus separately gated, bounded supersampled desktop modes.
#pragma once

struct NvrmEdidPanelMetadata {
    unsigned widthMm, heightMm;
    unsigned preferredW, preferredH;
};

static inline bool nvrmEdidPhysicalSizeValid(unsigned w, unsigned h)
{
    // Exclude zero/aspect-only EDID encodings and implausible desktop-panel dimensions.
    return w >= 10 && h >= 10 && w <= 4095 && h <= 4095 &&
           static_cast<unsigned long long>(w) <= static_cast<unsigned long long>(h) * 8 &&
           static_cast<unsigned long long>(h) <= static_cast<unsigned long long>(w) * 8;
}

static inline bool nvrmReadEdidPanelMetadata(const unsigned char *edid, unsigned length,
                                              NvrmEdidPanelMetadata *result)
{
    if (!edid || !result || length < 128) return false;
    const unsigned char header[8] = {0, 255, 255, 255, 255, 255, 255, 0};
    for (unsigned i = 0; i < 8; ++i) if (edid[i] != header[i]) return false;
    if (edid[18] != 1 || (edid[19] != 3 && edid[19] != 4) || !(edid[20] & 0x80)) return false;
    unsigned checksum = 0;
    for (unsigned i = 0; i < 128; ++i) checksum += edid[i];
    if (checksum & 255u) return false;

    NvrmEdidPanelMetadata panel = {};
    const unsigned char *d = edid + 54;
    // First DTD is used as a preferred-mode reference only when explicitly declared.
    // Descriptor strings and interlaced timings are never treated as native rasters.
    if ((edid[24] & 2) && (d[0] || d[1]) && !(d[17] & 0x80)) {
        const unsigned w = d[2] | ((d[4] & 0xf0u) << 4);
        const unsigned h = d[5] | ((d[7] & 0xf0u) << 4);
        if (w >= 320 && h >= 200) {
            panel.preferredW = w;
            panel.preferredH = h;
            const unsigned mmW = d[12] | ((d[14] & 0xf0u) << 4);
            const unsigned mmH = d[13] | ((d[14] & 0x0fu) << 8);
            if (nvrmEdidPhysicalSizeValid(mmW, mmH)) {
                panel.widthMm = mmW;
                panel.heightMm = mmH;
            }
        }
    }
    // Base-block size is in centimetres. In EDID 1.4 a zero axis may encode
    // aspect ratio instead, so both axes must be present before conversion.
    if (!panel.widthMm && edid[21] && edid[22]) {
        const unsigned mmW = static_cast<unsigned>(edid[21]) * 10;
        const unsigned mmH = static_cast<unsigned>(edid[22]) * 10;
        if (nvrmEdidPhysicalSizeValid(mmW, mmH)) {
            panel.widthMm = mmW;
            panel.heightMm = mmH;
        }
    }
    if (!panel.widthMm || !panel.heightMm) return false;
    *result = panel;
    return true;
}

template<class ModeInfo>
static inline bool nvrmApplyEdidHiDpiMetadata(ModeInfo *info, const unsigned char *edid,
                                            unsigned length, unsigned maxW, unsigned maxH,
                                            bool enabled, unsigned hiResFlag)
{
    if (!enabled || !info) return false;
    NvrmEdidPanelMetadata panel = {};
    if (!nvrmReadEdidPanelMetadata(edid, length, &panel)) return false;
    if (!info->imageWidth || !info->imageHeight) {
        // Parsed physical sizes are bounded to 4095 mm, within UInt16 mode fields.
        info->imageWidth = static_cast<decltype(info->imageWidth)>(panel.widthMm);
        info->imageHeight = static_cast<decltype(info->imageHeight)>(panel.heightMm);
    }
    // Mark only already-enumerated, even-sized modes with the preferred aspect,
    // at least preferred size, within this framebuffer's existing scaler limits.
    // No mode is injected, selected, validated or made safe by this flag.
    const unsigned w = info->nominalWidth, h = info->nominalHeight;
    if (panel.preferredW && panel.preferredH && maxW && maxH &&
        w >= panel.preferredW && h >= panel.preferredH &&
        w <= maxW && h <= maxH && w <= 16384 && h <= 16384 &&
        !(w & 1u) && !(h & 1u) &&
        static_cast<unsigned long long>(w) * panel.preferredH ==
        static_cast<unsigned long long>(h) * panel.preferredW)
        info->flags |= hiResFlag;
    return true;
}


// Backing surfaces above the physical raster allow logical HiDPI sizes above
// native/2. They are downsampled to an unchanged NVKMS-validated panel timing.
static const unsigned kNvrmHiDpiScaleCount = 6;
static inline bool nvrmHiDpiBackingSize(unsigned nativeW, unsigned nativeH,
                                       unsigned scale, unsigned maxW, unsigned maxH,
                                       unsigned long long bytes, unsigned pitchAlign,
                                       unsigned *outW, unsigned *outH)
{
    const unsigned num[kNvrmHiDpiScaleCount] = {5, 4, 3, 8, 7, 2};
    const unsigned den[kNvrmHiDpiScaleCount] = {4, 3, 2, 5, 4, 1};
    if (!outW || !outH || scale >= kNvrmHiDpiScaleCount ||
        nativeW < 320 || nativeH < 200 || nativeW > 7680 || nativeH > 4320 ||
        !pitchAlign || pitchAlign > 65536 || (pitchAlign & (pitchAlign - 1))) return false;
    const unsigned long long wNum = static_cast<unsigned long long>(nativeW) * num[scale];
    const unsigned long long hNum = static_cast<unsigned long long>(nativeH) * num[scale];
    if (wNum % den[scale] || hNum % den[scale]) return false;
    const unsigned w = static_cast<unsigned>(wNum / den[scale]);
    const unsigned h = static_cast<unsigned>(hNum / den[scale]);
    if ((w & 1) || (h & 1) || w <= nativeW || h <= nativeH ||
        w > maxW || h > maxH || w > 7680 || h > 4320) return false;
    const unsigned long long pitch = (static_cast<unsigned long long>(w) * 4 + pitchAlign - 1) &
                                    ~(static_cast<unsigned long long>(pitchAlign) - 1);
    if (pitch * h > bytes) return false;
    *outW = w; *outH = h;
    return true;
}

template<class Timing>
static inline unsigned nvrmAppendScaledHiDpiTimings(Timing *timings, unsigned count,
                                                   unsigned capacity, unsigned seed,
                                                   unsigned maxW, unsigned maxH,
                                                   unsigned long long bytes,
                                                   unsigned pitchAlign, unsigned stretchFlag)
{
    if (!timings || count > capacity || seed >= count) return count;
    const Timing base = timings[seed];
    if (!base.pixelClock || base.horizontalScaled || base.verticalScaled ||
        base.horizontalScaledInset || base.verticalScaledInset ||
        base.horizontalBorderLeft || base.horizontalBorderRight ||
        base.verticalBorderTop || base.verticalBorderBottom) return count;
    for (unsigned scale = 0; scale < kNvrmHiDpiScaleCount && count < capacity; ++scale) {
        unsigned w = 0, h = 0;
        if (!nvrmHiDpiBackingSize(base.horizontalActive, base.verticalActive, scale,
                                 maxW, maxH, bytes, pitchAlign, &w, &h)) continue;
        const unsigned id = 0x20000000u | (scale << 8);
        bool duplicate = false;
        for (unsigned j = 0; j < count; ++j) {
            if (timings[j].detailedTimingModeID == id ||
                (timings[j].horizontalActive == base.horizontalActive &&
                 timings[j].verticalActive == base.verticalActive &&
                 timings[j].horizontalScaled == w && timings[j].verticalScaled == h)) {
                duplicate = true; break;
            }
        }
        if (duplicate) continue;
        Timing scaled = base;
        scaled.horizontalScaled = w; scaled.verticalScaled = h;
        scaled.scalerFlags = stretchFlag;
        scaled.detailedTimingModeID = id;
        timings[count++] = scaled;
    }
    return count;
}
