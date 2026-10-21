#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
NVRMFB_UI_LANG="${2:-${NVRMFB_UI_LANG:-}}"
source "$(cd "$(dirname "$0")" && pwd -P)/ui.sh"
[ "$(id -u)" = 0 ] || { msg 'STOP: administrator privileges required.' '停止：需要管理员权限。' >&2; exit 1; }
set -euo pipefail
PKG=${1:?Package path required}
trap 'msg "STOP: backup failed at line $LINENO; driver unchanged." "停止：备份失败（第 $LINENO 行），尚未安装。" >&2' ERR
[ "$(uname -m)" = x86_64 ]
VERSION=$(cat /Library/NullMoth/driver-version)
case "$VERSION" in
    1.15.0|2.0.1|2.0.2|2.0.4|2.3.6|2.4.3) ;;
    *) msg "STOP: unsupported driver version: $VERSION. Only 1.15.0, 2.0.1, 2.0.2, 2.0.4, 2.3.6 and 2.4.3 are allowed." "停止：驱动版本 $VERSION 未验证，仅允许 1.15.0、2.0.1、2.0.2、2.0.4、2.3.6 和 2.4.3。" >&2; exit 1 ;;
esac
[ ! -e /Library/NullMoth/install.lock ]
LOCK=/Library/NullMoth/install.lock
mkdir -m 700 "$LOCK"
trap 'rm -rf "$LOCK"' EXIT
printf 'pid=%s\nboot=%s\n' "$$" "$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')" > "$LOCK/owner"
BK=$(mktemp -d "/Library/NullMoth/HiDPI-backup-$(date +%Y%m%d-%H%M%S).XXXXXX")
chmod 700 "$BK"
ditto /Library/Extensions/NVRMFB.kext "$BK/NVRMFB.kext"
cp -p /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BK/"
sw_vers -buildVersion > "$BK/macos-build.txt"
printf '%s\n' "$VERSION" > "$BK/driver-release.txt"
diskutil info -plist /System/Volumes/Data > "$BK/data-volume.plist"
(cd "$BK" && find NVRMFB.kext -type f -exec shasum -a 256 {} \; && shasum -a 256 AuxiliaryKernelExtensions.kc) > "$BK/original.sha256"
(cd /Library/Extensions && find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort) > "$BK/extensions-before.sha256"
(cd /Library/Extensions && find . -type f ! -path './NVRMFB.kext/*' -exec shasum -a 256 {} \; | LC_ALL=C sort) > "$BK/other-extensions.sha256"
cmp /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BK/AuxiliaryKernelExtensions.kc"
diff -qr /Library/Extensions/NVRMFB.kext "$BK/NVRMFB.kext"
mkdir "$BK/scripts"
cp "$PKG/Recovery.command" "$BK/Recovery.command"
cp "$PKG/scripts/restore-framebuffer.sh" "$BK/scripts/restore-framebuffer.sh"
cp "$PKG/scripts/ui.sh" "$BK/scripts/ui.sh"
chmod 700 "$BK/Recovery.command" "$BK/scripts/restore-framebuffer.sh" "$BK/scripts/ui.sh"
printf '\nBACKUP_DIRECTORY=%s\n' "$BK"
