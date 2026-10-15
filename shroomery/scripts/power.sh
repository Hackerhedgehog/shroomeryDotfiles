#!/usr/bin/env bash
# Lock / suspend / logout / reboot / power off. Uses hyprshutdown when installed.

lock_action()     { pidof hyprlock || hyprlock; }
suspend_action()  { systemctl suspend; }
logout_action()   { hyprctl dispatch 'hl.dsp.exit()'; }
reboot_action()   { systemctl reboot; }
poweroff_action() { systemctl poweroff; }

if command -v hyprshutdown &> /dev/null; then
    logout_action()   { hyprshutdown; }
    reboot_action()   { hyprshutdown -t 'Restarting...' --post-cmd 'reboot'; }
    poweroff_action() { hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown -P 0'; }
fi

show_help() {
    cat << HELP
Usage: $(basename "$0") [OPTION]
  -l, --lock        Lock the screen (hyprlock)
  -s, --suspend     Suspend
  -e, --logout      Exit Hyprland
  -r, --reboot      Reboot
  -p, --poweroff    Power off
  -h, --help        Show this help
HELP
}

case "${1:-}" in
    -l|--lock)     lock_action ;;
    -s|--suspend)  suspend_action ;;
    -e|--logout)   logout_action ;;
    -r|--reboot)   reboot_action ;;
    -p|--poweroff) poweroff_action ;;
    -h|--help|"")  show_help ;;
    *) echo "Error: Unknown option '$1'" >&2; show_help; exit 1 ;;
esac
