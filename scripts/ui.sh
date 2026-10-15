#!/bin/bash
# Shared UI language selection. Keep filesystem/hash sorting independent of UI text.
case "${NVRMFB_UI_LANG:-}" in
    zh|zh-*|zh_*) NVRMFB_UI_LANG=zh ;;
    en|en-*|en_*) NVRMFB_UI_LANG=en ;;
    *)
        nvrmfb_preferred=$(defaults read -g AppleLanguages 2>/dev/null |
            awk 'NR>1 {gsub(/^[ \t"]+|[",; \t)]+$/, ""); if(length) {print; exit}}' || true)
        if [ -z "$nvrmfb_preferred" ]; then
            nvrmfb_preferred=${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}
        fi
        case "$nvrmfb_preferred" in zh|zh-*|zh_*) NVRMFB_UI_LANG=zh ;; *) NVRMFB_UI_LANG=en ;; esac
        unset nvrmfb_preferred
        ;;
esac
msg() {
    if [ "$NVRMFB_UI_LANG" = zh ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}
warn() {
    if [ -t 1 ]; then printf '\033[1;31m'; fi
    msg "$1" "$2"
    if [ -t 1 ]; then printf '\033[0m'; fi
}
ask() { read -r -p "$(msg "$1" "$2")" "$3"; }
