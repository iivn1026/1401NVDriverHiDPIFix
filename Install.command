#!/bin/bash
set -eo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd -P)
source "$HERE/scripts/ui.sh"

BK=''
INSTALLED=0
RUNLOG=$(mktemp /tmp/nvrmfb-install.XXXXXX)
finish() {
    rc=$?
    if [ "$rc" != 0 ]; then
        if [ "$INSTALLED" = 1 ]; then
            warn 'Installed, but external backup refresh failed. Do not reboot yet.' '安装已完成，但外部备份同步失败。先不要重启。'
        else
            warn 'Operation incomplete. Resolve the error before rebooting.' '操作未完成，请排查错误后再重启。'
        fi
        [ -z "$BK" ] || msg "Backup: $BK" "备份：$BK"
        tail -n 12 "$RUNLOG" >&2
    fi
    msg "Log: $RUNLOG" "日志：$RUNLOG"
    if [ -t 0 ]; then ask 'Press Return to close: ' '按回车关闭：' ignored || true; fi
}
trap finish EXIT
msg 'NVRMFB HiDPI | 1.15.0 / 2.0.1 / 2.0.2 / 2.0.4 / 2.3.6 / 2.4.3' 'NVRMFB HiDPI | 1.15.0 / 2.0.1 / 2.0.2 / 2.0.4 / 2.3.6 / 2.4.3'
warn 'EXPERIMENTAL: read README.md carefully. Black screen/boot failure possible. Verify Recovery first.' '实验版：必须认真阅读 README.md，可能黑屏或无法启动。先确认 Recovery 可用。'
msg '[1/4] Verifying package' '[1/4] 校验安装包'
cd "$HERE"
shasum -a 256 -c SHA256SUMS >> "$RUNLOG" 2>&1
for bundle in "$HERE"/payloads/*/NVRMFB.kext; do
    codesign --verify --deep --strict "$bundle" >> "$RUNLOG" 2>&1
done
[ "$(uname -m)" = x86_64 ] || { warn 'x86_64 required.' '仅支持 x86_64。'; exit 1; }
sudo -p "$(msg 'Administrator password: ' '管理员密码：')" -v
msg '[2/4] Creating paired backup' '[2/4] 创建配对备份'
sudo /bin/bash "$HERE/scripts/prepare-backup.sh" "$HERE" "$NVRMFB_UI_LANG" >> "$RUNLOG" 2>&1
BK=$(sed -n 's/^BACKUP_DIRECTORY=//p' "$RUNLOG" | tail -1)
case "$BK" in /Library/NullMoth/HiDPI-backup-*) ;; *) warn 'Backup path unavailable.' '未取得有效备份路径。'; exit 1;; esac
STATE="$HOME/Library/Application Support/NVRMFB-EDID-HiDPI"
mkdir -p "$STATE"; chmod 700 "$STATE"
printf '%s\n' "$BK" > "$STATE/last-backup.txt"; chmod 600 "$STATE/last-backup.txt"
msg "Backup: $BK" "备份：$BK"
msg 'External data volume: /Volumes/NAME; no quotes. Empty = backup only.' '外部数据卷：/Volumes/卷名，不加引号。留空仅备份、不安装。'
ask 'Volume: ' '外部卷：' EXTERNAL
[ -n "$EXTERNAL" ] || { msg 'Stopped after backup only.' '已结束，未替换驱动。'; exit 0; }
case "$EXTERNAL" in /Volumes/*) ;; *) warn 'Use a mounted volume below /Volumes.' '请选择 /Volumes 下已挂载的卷。'; exit 1;; esac
[ -d "$EXTERNAL" ] && [ -w "$EXTERNAL" ] || { warn 'Destination is not writable.' '目标不可写入。'; exit 1; }
case "$(basename "$EXTERNAL" | tr '[:lower:]' '[:upper:]')" in *EFI*) warn 'Choose a data volume, not EFI.' '请选择数据卷，不要选择 EFI。'; exit 1;; esac
DEST="$EXTERNAL/$(basename "$BK")"
[ ! -e "$DEST" ] || { warn 'Backup destination already exists.' '备份目标已存在。'; exit 1; }
sudo /bin/bash "$HERE/scripts/copy-backup.sh" "$BK" "$DEST" "$NVRMFB_UI_LANG" >> "$RUNLOG" 2>&1
ask 'Backup copied. Type INSTALL to proceed: ' '外部备份已核对。输入 INSTALL 安装：' answer
[ "$answer" = INSTALL ] || { msg 'Cancelled; drivers unchanged.' '已取消，驱动未替换。'; exit 0; }
msg '[3/4] Preflight and installation (please wait)' '[3/4] 预检并安装，请稍候'
sudo /bin/bash "$HERE/scripts/install-framebuffer.sh" "$HERE" "$BK" "$NVRMFB_UI_LANG" >> "$RUNLOG" 2>&1
INSTALLED=1
msg '[4/4] Refreshing external backup' '[4/4] 同步外部备份'
sudo /bin/bash "$HERE/scripts/copy-backup.sh" "$BK" "$DEST" "$NVRMFB_UI_LANG" >> "$RUNLOG" 2>&1
msg 'INSTALLED. Save work and reboot manually.' 'INSTALLED：安装完成。保存工作后自行重启。'
msg "Recovery backup: $DEST" "救援备份：$DEST"
msg 'First boot: omit nvfbhidpi=1 and nvfbhidpiscaled=1. Enable experiments in stages; see README.md. EFI unchanged.' '首次启动移除 nvfbhidpi=1 和 nvfbhidpiscaled=1；再按 README.md 分步启用。EFI 未自动修改。'
