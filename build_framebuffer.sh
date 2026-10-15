#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/source/kexts/NVRMFB"
OGKM="${NVRMFB_OGKM:-$HERE/ogkm}"
OUT="${1:-$HERE/out-generic}"
SDK="$(xcrun --show-sdk-path)"
KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
mkdir -p "$OUT/NVRMFB.kext/Contents/MacOS"
INCLUDES=( -I"$KHDR" -I"$SRC"
  -I"$OGKM/src/nvidia/arch/nvalloc/unix/include"
  -I"$OGKM/src/common/sdk/nvidia/inc" -I"$OGKM/src/common/inc"
  -I"$OGKM/src/nvidia-modeset/os-interface/include"
  -I"$OGKM/src/nvidia-modeset/kapi/interface"
  -I"$OGKM/src/nvidia-modeset/kapi/include"
  -I"$OGKM/src/nvidia-modeset/interface"
  -I"$OGKM/src/nvidia-modeset/include"
  -I"$OGKM/src/common/unix/nvidia-push/interface"
  -I"$OGKM/src/common/unix/common/inc"
  -I"$OGKM/src/common/modeset" )
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc "${INCLUDES[@]}" \
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
  -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common \
  -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-unused-function -O2 \
  -ffile-prefix-map="$HERE"=/local/nvrmfb-build \
  -c "$SRC/fb/nvrm-fb.cpp" -o "$OUT/nvrm-fb.o" >"$OUT/compile.log" 2>&1
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext \
  -lkmodc++ -lkmod -lcc_kext "$OUT/nvrm-fb.o" \
  -o "$OUT/NVRMFB.kext/Contents/MacOS/NVRMFB" >"$OUT/link.log" 2>&1
cp "$SRC/fb/Info.plist" "$OUT/NVRMFB.kext/Contents/Info.plist"
codesign --force --sign - "$OUT/NVRMFB.kext"
codesign --verify --deep --strict "$OUT/NVRMFB.kext"
dwarfdump --uuid "$OUT/NVRMFB.kext/Contents/MacOS/NVRMFB"
