#!/bin/bash
set -eo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd -P)
source "$HERE/scripts/ui.sh"

MODE=restore
if [ "${1:-}" = --check ]; then MODE=check; shift; fi
TARGET=${1:-}
BK=${2:-}
if [ -z "$BK" ] && [ -f "$HERE/AuxiliaryKernelExtensions.kc" ]; then BK=$HERE; fi
[ "$(id -u)" = 0 ] || { warn 'Use Rollback.command in macOS. This entry needs Recovery Terminal.' '正常系统请用 Rollback.command；此入口用于 Recovery 终端。'; exit 1; }
msg 'Offline rollback — mount/unlock the original DATA volume first.' '离线回退：请先挂载并解锁原 macOS 数据卷。'
if [ -z "$TARGET" ]; then ls /Volumes; ask 'DATA volume path: ' '数据卷完整路径：' TARGET; fi
if [ -z "$BK" ]; then ask 'Backup directory: ' '备份目录完整路径：' BK; fi
[ -n "$TARGET" ] && [ -n "$BK" ] || { warn 'Target and backup are required.' '必须指定目标卷和备份目录。'; exit 1; }
if [ -f "$BK/scripts/restore-framebuffer.sh" ]; then HELPER="$BK/scripts/restore-framebuffer.sh"; else HELPER="$HERE/scripts/restore-framebuffer.sh"; fi
[ -f "$HELPER" ] || { warn 'Helper missing. Keep the entire backup folder.' '缺少辅助脚本，请保留完整备份文件夹。'; exit 1; }
/bin/bash "$HELPER" "$TARGET" "$BK" check "$NVRMFB_UI_LANG"
[ "$MODE" != check ] || exit 0
ask 'Type RESTORE to restore: ' '输入 RESTORE 恢复：' answer
[ "$answer" = RESTORE ] || { msg 'Cancelled.' '已取消。'; exit 0; }
/bin/bash "$HELPER" "$TARGET" "$BK" restore "$NVRMFB_UI_LANG"
msg 'Reboot manually only after RESTORED.' '看到 RESTORED 后再自行重启。'
