#!/usr/bin/env bash
# Open the Settings window on the Update tab (the safe system update).
# Used by SUPER+U and the statusbar update button. Without a running qs it says so on
# stderr and as a desktop notification (a key binding has no terminal to show stderr).
if ! qs ipc call settings openTab update >/dev/null 2>&1; then
    msg="could not reach Quickshell (is qs running?). Update from a terminal: ~/.config/shroomery/scripts/pkg-update.sh apply"
    echo "install-updates.sh: $msg" >&2
    if source "$HOME/.config/shroomery/notify.sh" 2>/dev/null; then
        notify_user --a "System update" --s "System update" --m "$msg" --u normal >/dev/null 2>&1
    fi
    exit 1
fi
