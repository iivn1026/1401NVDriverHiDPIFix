#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
NVRMFB_UI_LANG="${3:-${NVRMFB_UI_LANG:-}}"
source "$(cd "$(dirname "$0")" && pwd -P)/ui.sh"
[ "$(id -u)" = 0 ] || { msg 'STOP: administrator privileges required.' '停止：需要管理员权限。' >&2; exit 1; }
set -euo pipefail
trap 'msg "STOP: installation failed at line $LINENO. Keep the backup; resolve before rebooting." "停止：安装失败（第 $LINENO 行）。保留备份，排查后再重启。" >&2' ERR
PKG=$1
BK=$2
EXT=/Library/Extensions
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
VERSION=$(cat /Library/NullMoth/driver-version)
case "$VERSION" in
    1.15.0|2.0.1|2.0.2) ;;
    *) msg "STOP: unsupported driver version: $VERSION. Only 1.15.0, 2.0.1 and 2.0.2 are allowed." "停止：驱动版本 $VERSION 未验证，仅允许 1.15.0、2.0.1 和 2.0.2。" >&2; exit 1 ;;
esac
[ "$(sw_vers -buildVersion)" = "$(cat "$BK/macos-build.txt")" ]
[ -d "$EXT/NVRMFB.kext" ] && [ ! -L "$EXT/NVRMFB.kext" ]
[ "$(cat "$BK/driver-release.txt")" = "$VERSION" ]
BUNDLE="$PKG/payloads/$VERSION/NVRMFB.kext"
[ -d "$BUNDLE" ]
(cd "$PKG" && shasum -a 256 -c SHA256SUMS)
(cd "$BK" && shasum -a 256 -c original.sha256)
LOCK=/Library/NullMoth/install.lock
mkdir -m 700 "$LOCK"
WORK=
CHANGED=0
PUBLISHED=0
NEWKC="$KC.hidpi-new-$$"
finish() {
    rc=$?
    trap - EXIT
    set +e
    if [ "$CHANGED" = 1 ] && [ "$PUBLISHED" = 0 ]; then
        if [ -e "$EXT/NVRMFB.kext" ]; then mv "$EXT/NVRMFB.kext" "$WORK/failed-test.kext"; fi
        if mv "$WORK/previous.kext" "$EXT/NVRMFB.kext"; then
            msg 'Original framebuffer restored; active AuxKC unchanged.' '已恢复原驱动，系统内核集合未替换。'
        else
            msg "RECOVERY REQUIRED. Backup: $BK" "需要离线回退。备份：$BK" >&2
        fi
    fi
    rm -f "$NEWKC"
    rm -rf "$LOCK"
    msg "Logs: $WORK" "日志：$WORK"
    exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf 'pid=%s\nboot=%s\n' "$$" "$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')" > "$LOCK/owner"
WORK=$(mktemp -d /var/tmp/nvrmfb-hidpi.XXXXXX)
msg '1/4: Checking files and target' '1/4：检查文件和目标卷'
diskutil info -plist /System/Volumes/Data > "$WORK/data-volume.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :VolumeUUID' "$BK/data-volume.plist")" = "$(/usr/libexec/PlistBuddy -c 'Print :VolumeUUID' "$WORK/data-volume.plist")" ]
mkdir "$WORK/repo"
for k in "$EXT"/*.kext; do
    [ -d "$k" ] || continue
    if [ "$(basename "$k")" != NVRMFB.kext ]; then ditto "$k" "$WORK/repo/$(basename "$k")"; fi
done
ditto "$BUNDLE" "$WORK/repo/NVRMFB.kext"
chown -R root:wheel "$WORK/repo"
chmod -R go-w "$WORK/repo"
KARG=()
if [ -f /System/Library/Kernels/kernel ]; then KARG=(--kernel /System/Library/Kernels/kernel); fi
build() {
    kmutil create -n aux --volume-root / --allow-missing-kdk \
      -B /System/Library/KernelCollections/BootKernelExtensions.kc \
      -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
      --repository "$1" -A "$2" -z ${KARG[@]+"${KARG[@]}"} > "$3" 2>&1
    [ -s "$2" ]
    kmutil inspect -a x86_64 -A "$2" > "$3.inspect"
    for id in com.nullmoth.NVRM com.nullmoth.NVRMFB com.nullmoth.NVAccel com.nullmoth.NVRMAGDC; do
        awk '{print $1}' "$3.inspect" | grep -Fx "$id" > /dev/null
    done
}
msg '2/4: Building preflight collection' '2/4：构建临时内核集合'
build "$WORK/repo" "$WORK/test.kc" "$WORK/preflight.log"
(cd "$EXT" && find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort) > "$WORK/extensions-now.sha256"
cmp "$BK/extensions-before.sha256" "$WORK/extensions-now.sha256"
[ "$(shasum -a 256 "$KC" | awk '{print $1}')" = "$(shasum -a 256 "$BK/AuxiliaryKernelExtensions.kc" | awk '{print $1}')" ]
codesign --verify --deep --strict "$WORK/repo/NVRMFB.kext"
msg '3/4: Replacing NVRMFB' '3/4：替换 NVRMFB'
mv "$EXT/NVRMFB.kext" "$WORK/previous.kext"
CHANGED=1
ditto "$WORK/repo/NVRMFB.kext" "$EXT/NVRMFB.kext"
chown -R root:wheel "$EXT/NVRMFB.kext"
chmod -R go-w "$EXT/NVRMFB.kext"
msg '4/4: Building matching system collection' '4/4：重建配套系统内核集合'
build "$EXT" "$NEWKC" "$WORK/live-build.log"
shasum -a 256 "$NEWKC" | awk '{print $1}' > "$BK/installed-aux.sha256"
mv -f "$NEWKC" "$KC"
PUBLISHED=1
msg "INSTALLED. Backup: $BK. Reboot manually." "INSTALLED：安装完成。备份：$BK。请自行重启。"
