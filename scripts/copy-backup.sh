#!/bin/bash
# Portable external copy: copy bytes, never APFS flags, ACLs or xattrs.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
NVRMFB_UI_LANG="${3:-${NVRMFB_UI_LANG:-}}"
source "$(cd "$(dirname "$0")" && pwd -P)/ui.sh"
set -euo pipefail
[ "$(id -u)" = 0 ] || { warn 'Administrator privileges required.' '需要管理员权限。'; exit 1; }
SRC=${1:?Backup source required}
DEST=${2:?Backup destination required}
[ -d "$SRC" ] && [ ! -L "$SRC" ] && [ -f "$SRC/original.sha256" ]
[ -d "$SRC/NVRMFB.kext" ] && [ -f "$SRC/AuxiliaryKernelExtensions.kc" ]
SRC=$(cd "$SRC" && pwd -P)
PARENT=$(cd "$(dirname "$DEST")" && pwd -P)
DEST="$PARENT/$(basename "$DEST")"
case "$DEST/" in "$SRC/"*) warn 'Destination must be outside the source backup.' '目标不能位于源备份中。'; exit 1;; esac
[ ! -L "$DEST" ]
if [ -e "$DEST" ]; then
    [ -d "$DEST" ] && cmp -s "$SRC/original.sha256" "$DEST/original.sha256" || {
        warn 'Existing destination is not this paired backup. Choose a new folder.' '目标已存在且不是这份配对备份，请选择新目录。'; exit 1;
    }
fi
if [ -d "$DEST" ]; then
    [ -z "$(find "$DEST" ! -type f ! -type d -print -quit)" ] || { warn 'Destination contains a special file or symlink.' '目标含特殊文件或符号链接，请选择新目录。'; exit 1; }
fi
TMP=$(mktemp -d /tmp/nvrmfb-copy.XXXXXX)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'warn "External copy failed; installation must not continue. Internal backup: $SRC" "外部复制失败，禁止继续安装。内部备份：$SRC"' ERR
# FAT/exFAT cannot represent symlinks. Refuse rather than silently alter a signed bundle.
find "$SRC" ! -type f ! -type d -print > "$TMP/special"
[ ! -s "$TMP/special" ] || { warn 'Backup contains special files; use an archive or a native filesystem workflow.' '备份含特殊文件，不能使用通用目录复制，请使用归档或原生文件系统流程。'; exit 1; }
diskutil info -plist "$PARENT" > "$TMP/volume.plist"
FSTYPE=$(/usr/libexec/PlistBuddy -c 'Print :FilesystemType' "$TMP/volume.plist" 2>/dev/null || true)
if [ "$FSTYPE" = msdos ]; then
    find "$SRC" -type f -size +4294967295c -print > "$TMP/large"
    [ ! -s "$TMP/large" ] || { warn 'FAT32 has a 4 GiB file limit. Choose exFAT or APFS; do not skip backup.' 'FAT32 单文件上限为 4 GiB，请选择 exFAT 或 APFS，不要跳过备份。'; exit 1; }
fi
NEEDED=$(du -sk "$SRC" | awk '{print $1}')
AVAILABLE=$(df -Pk "$PARENT" | awk 'END {print $4}')
[ "$AVAILABLE" -gt "$NEEDED" ] || { warn 'Not enough free space for a verified copy.' '空间不足，无法完成可校验的复制。'; exit 1; }
mkdir -p "$DEST"
printf 'Incomplete external copy; do not use for recovery.\n' > "$DEST/.copy-incomplete"
# No cp -p or ditto: AuxiliaryKernelExtensions.kc may carry the APFS
# restricted flag, which FAT32/exFAT cannot store (Invalid argument).
find "$SRC" -type d -print0 > "$TMP/directories"
while IFS= read -r -d '' dir; do
    relative=${dir#"$SRC"}
    mkdir -p "$DEST$relative"
done < "$TMP/directories"
find "$SRC" -type f -print0 > "$TMP/files"
while IFS= read -r -d '' file; do
    relative=${file#"$SRC/"}
    case "$relative" in .DS_Store|*/.DS_Store|._*|*/._*) continue;; esac
    target="$DEST/$relative"
    mkdir -p "$(dirname "$target")"
    [ ! -L "$target" ]
    pending=$(mktemp "$(dirname "$target")/.nvrmfb-copy.XXXXXX")
    if ! cat "$file" > "$pending" || ! cmp -s "$file" "$pending"; then
        rm -f "$pending"
        warn "Data copy failed: $relative" "数据复制失败：$relative"
        exit 1
    fi
    # Native permissions are reconstructed by the restore helper, not carried
    # over from an untrusted/foreign filesystem's metadata.
    chmod 644 "$pending"
    mv -f "$pending" "$target"
done < "$TMP/files"
diff -qr -x '._*' -x '.DS_Store' -x '.copy-incomplete' "$SRC" "$DEST"
(cd "$DEST" && shasum -a 256 -c original.sha256)
rm "$DEST/.copy-incomplete"
msg 'External backup bytes and hashes verified.' '外部备份文件内容和校验值已核对。'
