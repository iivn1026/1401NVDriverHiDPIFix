#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
NVRMFB_UI_LANG="${4:-${NVRMFB_UI_LANG:-}}"
source "$(cd "$(dirname "$0")" && pwd -P)/ui.sh"
[ "$(id -u)" = 0 ] || { msg 'STOP: administrator privileges required.' '停止：需要管理员权限。' >&2; exit 1; }
set -euo pipefail
MODE=${3:-restore}
case "$MODE" in check|restore) ;; *) msg 'STOP: unknown mode.' '停止：未知操作。' >&2; exit 1;; esac
trap 'msg "STOP: restore check failed at line $LINENO. Do not bypass it." "停止：回退检查失败（第 $LINENO 行），不要绕过检查。" >&2' ERR
TARGET=$1
BK=$2
if [ "$TARGET" = /System/Volumes/Data ]; then
    [ "$(sw_vers -buildVersion)" = "$(cat "$BK/macos-build.txt")" ]
    [ ! -e /Library/NullMoth/install.lock ]
    if [ -f "$BK/driver-release.txt" ]; then
        [ "$(cat /Library/NullMoth/driver-version)" = "$(cat "$BK/driver-release.txt")" ] || {
            msg 'STOP: driver release changed since backup.' '停止：驱动版本已变化，不能使用旧备份。' >&2
            exit 1
        }
    fi
fi
[ -d "$TARGET/Library/Extensions" ]
[ -f "$TARGET/Library/KernelCollections/AuxiliaryKernelExtensions.kc" ]
[ -d "$BK/NVRMFB.kext" ]
TMP=$(mktemp -d /tmp/nvrmfb-restore.XXXXXX)
OWN_LOCK=''
cleanup() {
    rm -rf "$TMP"
    [ -z "$OWN_LOCK" ] || rm -rf "$OWN_LOCK"
}
trap cleanup EXIT
diskutil info -plist "$TARGET" > "$TMP/target.plist"
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print :VolumeUUID' "$BK/data-volume.plist")
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print :VolumeUUID' "$TMP/target.plist")
[ "$EXPECTED" = "$ACTUAL" ]
# SHA-256 via OpenSSL avoids depending on Python or Perl in Recovery.
sha() { /usr/bin/openssl dgst -sha256 "$1" | awk '{print $NF}'; }
while read -r expected relative; do
    [ "$(sha "$BK/$relative")" = "$expected" ]
done < "$BK/original.sha256"
(cd "$TARGET/Library/Extensions" && find . -type f ! -path './NVRMFB.kext/*' -print | LC_ALL=C sort) > "$TMP/current-paths"
awk '{print substr($0,67)}' "$BK/other-extensions.sha256" | LC_ALL=C sort > "$TMP/expected-paths"
cmp "$TMP/current-paths" "$TMP/expected-paths"
while read -r expected relative; do
    [ "$(sha "$TARGET/Library/Extensions/$relative")" = "$expected" ]
done < "$BK/other-extensions.sha256"
KC="$TARGET/Library/KernelCollections/AuxiliaryKernelExtensions.kc"
CURRENT=$(sha "$KC")
ORIGINAL=$(sha "$BK/AuxiliaryKernelExtensions.kc")
if [ "$CURRENT" != "$ORIGINAL" ]; then
    [ -f "$BK/installed-aux.sha256" ]
    [ "$CURRENT" = "$(cat "$BK/installed-aux.sha256")" ]
fi
msg 'CHECK PASSED: target and paired backup verified.' 'CHECK PASSED：目标卷和配对备份校验通过。'
if [ "$MODE" = check ]; then msg 'Nothing changed.' '未修改文件。'; exit 0; fi
if [ "$TARGET" = /System/Volumes/Data ]; then
    mkdir -m 700 /Library/NullMoth/install.lock
    OWN_LOCK=/Library/NullMoth/install.lock
    printf 'pid=%s\nboot=%s\n' "$$" "$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')" > "$OWN_LOCK/owner"
fi
SAVE=$(mktemp -d "$TARGET/Library/KernelCollections/HiDPI-restore.XXXXXX")
chmod 700 "$SAVE"
ditto "$BK/NVRMFB.kext" "$SAVE/original.kext"
chown -R 0:0 "$SAVE/original.kext"
chmod -R go-w "$SAVE/original.kext"
cp "$BK/AuxiliaryKernelExtensions.kc" "$SAVE/original.kc"
chown 0:0 "$SAVE/original.kc"
chmod 644 "$SAVE/original.kc"
[ "$(sha "$SAVE/original.kc")" = "$ORIGINAL" ]
cp -p "$KC" "$SAVE/previous.kc"
mv "$TARGET/Library/Extensions/NVRMFB.kext" "$SAVE/previous.kext"
revert() {
    [ ! -d "$TARGET/Library/Extensions/NVRMFB.kext" ] || mv "$TARGET/Library/Extensions/NVRMFB.kext" "$SAVE/failed.kext"
    mv "$SAVE/previous.kext" "$TARGET/Library/Extensions/NVRMFB.kext"
}
trap 'revert; exit 1' ERR
mv "$SAVE/original.kext" "$TARGET/Library/Extensions/NVRMFB.kext"
mv -f "$SAVE/original.kc" "$KC"
trap - ERR
msg "RESTORED. Previous files: $SAVE" "RESTORED：回退完成。原文件保留于：$SAVE"
msg 'Remove nvfbhidpi=1 if added, then reboot manually.' '若添加过 nvfbhidpi=1，请移除后自行重启。'
