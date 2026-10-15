#!/bin/bash
set -eo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd -P)
source "$HERE/scripts/ui.sh"

finish() {
    rc=$?
    [ "$rc" = 0 ] || warn 'Restore incomplete. Keep the error; do not bypass checks.' '回退未完成。保留报错，不要绕过检查。'
    if [ -t 0 ]; then ask 'Press Return to close: ' '按回车关闭：' ignored || true; fi
}
trap finish EXIT
DEFAULT=''
POINTER="$HOME/Library/Application Support/NVRMFB-EDID-HiDPI/last-backup.txt"
if [ -f "$POINTER" ]; then DEFAULT=$(cat "$POINTER"); fi
msg 'NVRMFB paired rollback' 'NVRMFB 配对回退'
warn 'Do not restore an old cache after unrelated system/driver updates.' '系统或其他驱动更新后，不要恢复旧内核集合。'
[ -z "$DEFAULT" ] || msg "Default: $DEFAULT" "默认备份：$DEFAULT"
ask 'Backup path (Return = default): ' '备份路径（回车使用默认值）：' BK
BK=${BK:-$DEFAULT}
[ -n "$BK" ] || { warn 'Backup path required.' '必须指定备份路径。'; exit 1; }
sudo -p "$(msg 'Administrator password: ' '管理员密码：')" -v
sudo /bin/bash "$HERE/scripts/restore-framebuffer.sh" /System/Volumes/Data "$BK" check "$NVRMFB_UI_LANG"
ask 'Type RESTORE to restore: ' '输入 RESTORE 恢复：' answer
[ "$answer" = RESTORE ] || { msg 'Cancelled.' '已取消。'; exit 0; }
sudo /bin/bash "$HERE/scripts/restore-framebuffer.sh" /System/Volumes/Data "$BK" restore "$NVRMFB_UI_LANG"
msg 'Remove nvfbhidpi=1 and nvfbhidpiscaled=1 if added, then reboot manually.' '若添加过 nvfbhidpi=1 和 nvfbhidpiscaled=1，请移除后自行重启。'
