#!/usr/bin/env bash
# What closing the laptop lid does (systemd-logind's HandleLidSwitch*).
#
# Usage: lid-switch.sh status
#          Prints present=true|false (the machine has a lid) and one KEY=VALUE
#          line per setting with the value logind uses now ("" = not set:
#          HandleLidSwitchExternalPower then follows HandleLidSwitch).
#        lid-switch.sh set KEY [ACTION]
#          KEY: HandleLidSwitch | HandleLidSwitchExternalPower
#          ACTION: suspend, hibernate, hybrid-sleep, suspend-then-hibernate,
#          sleep, lock, poweroff, ignore; none = comment the key out.
#          Edits the [Login] section of /etc/systemd/logind.conf (asks for the
#          password through pkexec) and reloads systemd-logind.
# Exit 1 = bad arguments, 2 = not authorized / cancelled, 3 = write failed.

LOGIND_CONF=/etc/systemd/logind.conf
KEYS="HandleLidSwitch HandleLidSwitchExternalPower"
ACTIONS="suspend hibernate hybrid-sleep suspend-then-hibernate sleep lock poweroff ignore"

has_word() { [[ " $2 " == *" $1 "* ]]; }

lid_present() {
    local reply
    reply=$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower \
        org.freedesktop.UPower LidIsPresent 2>/dev/null)
    if [ -n "$reply" ]; then
        [ "$reply" = "b true" ] && echo true || echo false
    elif compgen -G "/proc/acpi/button/lid/*" > /dev/null; then
        echo true
    else
        echo false
    fi
}

status() {
    echo "present=$(lid_present)"
    local key value
    for key in $KEYS; do
        value=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager "$key" 2>/dev/null)
        value=${value#s \"}
        echo "$key=${value%\"}"
    done
    for key in CanHibernate CanHybridSleep CanSuspendThenHibernate; do
        value=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager "$key" 2>/dev/null)
        value=${value#s \"}
        echo "$key=${value%\"}"
    done
}

# Rewrite logind.conf with KEY set to ACTION (empty = commented out): the
# active line wins over a commented example, other active copies of the key
# are commented out, and a missing key is added under [Login].
write_key() {
    local key=$1 action=$2 tmp
    tmp=$(mktemp) || return 3
    awk -v key="$key" -v action="$action" '
        function is_key(line, commented) {
            return line ~ ("^" (commented ? "#[[:space:]]*" : "") key "[[:space:]]*=")
        }
        FNR == NR { if (is_key($0, 0)) active++; next }
        /^\[/ { if (in_login && !done && action != "") { print key "=" action; done = 1 }
                in_login = ($0 == "[Login]") }
        in_login && !done && (active ? is_key($0, 0) : is_key($0, 1)) {
            print (action != "" ? key "=" action : "#" $0); done = 1; next
        }
        in_login && is_key($0, 0) { print "#" $0; next }
        { print }
        END {
            if (!done && action != "") {
                if (!in_login) print "[Login]"
                print key "=" action
            }
        }
    ' "$LOGIND_CONF" "$LOGIND_CONF" > "$tmp" || { rm -f "$tmp"; return 3; }
    # cat > keeps the file's owner and mode.
    cat "$tmp" > "$LOGIND_CONF" || { rm -f "$tmp"; return 3; }
    rm -f "$tmp"
    systemctl reload systemd-logind
}

case "${1:-}" in
    status)
        status
        ;;
    set)
        key=${2:-}
        action=${3:-}
        has_word "$key" "$KEYS" || { echo "unknown key: $key" >&2; exit 1; }
        [ -z "$action" ] || has_word "$action" "$ACTIONS" || { echo "unknown action: $action" >&2; exit 1; }
        if [ "$(id -u)" -ne 0 ]; then
            pkexec "$(readlink -f "$0")" set "$key" "$action"
            code=$?
            # 126/127: the password dialog was dismissed or auth failed.
            [ "$code" -eq 126 ] || [ "$code" -eq 127 ] && exit 2
            exit "$code"
        fi
        write_key "$key" "$action"
        ;;
    *)
        sed -n '2,18s/^# \{0,1\}//p' "$0"
        exit 1
        ;;
esac
