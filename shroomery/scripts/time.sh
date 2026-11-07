#!/usr/bin/env bash
# Date, time, timezone and system locale, for the quickshell TimeApp (SUPER+T).
# Changes go through timedatectl / localectl, which ask for the password with
# the polkit agent (add-locale and allow-timezone use pkexec).
#
# Usage: time.sh COMMAND
#   status               JSON: timezone, ntp, synced, the locale variables in
#                        effect system-wide, autoTimezone (time.json) and
#                        timezoneAllowed (the timezone can change without a password)
#   timezones            "ZONE<TAB>+HHMM" per timezone (offset now)
#   locales              "NAME<TAB>INSTALLED<TAB>LANGUAGE<TAB>TERRITORY" per
#                        supported UTF-8 locale (INSTALLED 1/0)
#   set-timezone ZONE
#   set-ntp on|off       automatic time from the network
#   set-time "YYYY-MM-DD HH:MM[:SS]"   (needs ntp off)
#   set-locale VAR=VALUE...            the whole system locale (LANG, LC_*);
#                                      variables not given are removed
#   add-locale NAME      generate a locale from /usr/share/i18n/SUPPORTED
#                        (e.g. de_DE.UTF-8): adds it to /etc/locale.gen, runs locale-gen
#   auto-timezone        look up the timezone from the IP address and set it
#                        when it differs (no password prompt: needs allow-timezone)
#   allow-timezone       install a polkit rule that lets you change the
#                        timezone without a password (asks once)
# Exit 1 = bad arguments or values, 2 = not allowed / prompt dismissed,
# 3 = the change or lookup failed.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$SHROOMERY_DIR/notify.sh"

SUPPORTED_LOCALES="/usr/share/i18n/SUPPORTED"
LOCALE_SOURCES="/usr/share/i18n/locales"
SYSTEM_LOCALE_CONF="/etc/locale.conf"

# timedatectl/localectl exit 1 for both a refused prompt and a failure;
# polkit's refusal mentions access/authentication.
run_privileged() {
    local err
    if err=$("$@" 2>&1 >/dev/null); then
        return 0
    fi
    error "$err"
    if [[ "$err" == *"ccess denied"* || "$err" == *"uthenticat"* || "$err" == *"nteractive authentication required"* ]]; then
        return 2
    fi
    return 3
}

timezone_allowed() {
    pkcheck --action-id org.freedesktop.timedate1.set-timezone --process $$ >/dev/null 2>&1
}

valid_timezone() {
    timedatectl list-timezones 2>/dev/null | grep -qxF -- "$1"
}

status() {
    local tz ntp synced
    tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    ntp=$(timedatectl show -p NTP --value 2>/dev/null)
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    jq -n --arg tz "$tz" --arg ntp "$ntp" --arg synced "$synced" \
        --argjson loc "$(system_locale_json)" \
        --arg auto "$(time_setting autoTimezone)" \
        --argjson allowed "$(timezone_allowed && echo true || echo false)" '{
            timezone: $tz, ntp: ($ntp == "yes"), synced: ($synced == "yes"),
            locale: $loc, autoTimezone: ($auto == "true"),
            timezoneAllowed: $allowed
        }'
}

# /etc/locale.conf (what localectl set-locale writes) as {"LANG": "…", …}.
system_locale_json() {
    jq -Rn '[inputs | select(test("^[A-Z_]+="))
        | capture("^(?<k>[A-Z_]+)=\"?(?<v>[^\"]*)\"?$") | { (.k): .v }] | add // {}' \
        < "$SYSTEM_LOCALE_CONF" 2>/dev/null || echo '{}'
}

timezones() {
    timedatectl list-timezones | python3 -c '
import sys
from datetime import datetime
from zoneinfo import ZoneInfo
now = datetime.now()
for line in sys.stdin:
    zone = line.strip()
    if not zone:
        continue
    try:
        offset = datetime.now(ZoneInfo(zone)).strftime("%z")
    except Exception:
        offset = ""
    print(f"{zone}\t{offset}")
'
}

# Language and territory names come from each locale source's
# LC_IDENTIFICATION section (language "German", territory "Austria").
locales() {
    local installed
    installed=$(locale -a 2>/dev/null)
    awk '$2 == "UTF-8" { print $1 }' "$SUPPORTED_LOCALES" | while IFS= read -r name; do
        local base mod="" src lang="" terr="" inst=0
        [[ "$name" == *@* ]] && mod="@${name#*@}"
        base=${name%%@*}
        base=${base%%.*}
        src="$LOCALE_SOURCES/$base$mod"
        if [ -f "$src" ]; then
            lang=$(awk -F'"' '/^language[ \t]/ { print $2; exit }' "$src")
            terr=$(awk -F'"' '/^territory[ \t]/ { print $2; exit }' "$src")
        fi
        grep -qxF -- "$(normalize_locale_name "$name")" <<<"$installed" && inst=1
        printf '%s\t%s\t%s\t%s\n' "$name" "$inst" "$lang" "$terr"
    done
}

set_timezone() {
    valid_timezone "$1" || { error "Unknown timezone: $1"; exit 1; }
    run_privileged timedatectl set-timezone "$1" || exit $?
}

set_ntp() {
    case "$1" in
        on|true|yes) run_privileged timedatectl set-ntp true || exit $? ;;
        off|false|no) run_privileged timedatectl set-ntp false || exit $? ;;
        *) error "set-ntp takes on or off"; exit 1 ;;
    esac
}

set_time() {
    valid_datetime "$1" || { error "Not a date and time (YYYY-MM-DD HH:MM[:SS]): $1"; exit 1; }
    if [ "$(timedatectl show -p NTP --value)" = yes ]; then
        error "Automatic time is on; turn it off first"
        exit 1
    fi
    run_privileged timedatectl set-time "$1" || exit $?
}

set_locale() {
    local a
    [ $# -gt 0 ] || { error "set-locale needs at least LANG=…"; exit 1; }
    for a in "$@"; do
        valid_locale_assignment "$a" || { error "Not a locale setting: $a"; exit 1; }
    done
    run_privileged localectl set-locale "$@" || exit $?
}

add_locale() {
    local name=$1
    [[ "$name" =~ ^[A-Za-z0-9_.@-]+$ ]] || { error "Not a locale name: $name"; exit 1; }
    local line
    line=$(awk -v n="$name" '$1 == n { print; exit }' "$SUPPORTED_LOCALES")
    [ -n "$line" ] || { error "Not in $SUPPORTED_LOCALES: $name"; exit 1; }
    # The line is passed as an argument, never spliced into the shell text.
    pkexec /usr/bin/bash -c '
        grep -qxF -- "$1" /etc/locale.gen || printf "%s\n" "$1" >> /etc/locale.gen
        locale-gen' bash "$line" >/dev/null 2>&1
    case $? in
        0) ;;
        126|127) error "Password prompt dismissed"; exit 2 ;;
        *) error "locale-gen failed"; exit 3 ;;
    esac
}

lookup_timezone() {
    local tz url
    for url in "https://ipapi.co/timezone" "https://ipinfo.io/timezone"; do
        tz=$(curl -sf --max-time 10 "$url" | tr -d '[:space:]')
        if [ -n "$tz" ] && valid_timezone "$tz"; then
            echo "$tz"
            return 0
        fi
    done
    return 1
}

auto_timezone() {
    local tz current
    tz=$(lookup_timezone) || { error "Couldn't look up the timezone"; exit 3; }
    current=$(timedatectl show -p Timezone --value)
    if [ "$tz" = "$current" ]; then
        echo "$tz"
        return 0
    fi
    if ! timedatectl --no-ask-password set-timezone "$tz" 2>/dev/null; then
        error "Not allowed to change the timezone to $tz without a password"
        exit 2
    fi
    notify_user --a "Time" --i "preferences-system-time" --s "Timezone changed" \
        --m "Now on $tz time (was $current)"
    echo "$tz"
}

allow_timezone() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<JS
// Written by ~/.config/shroomery/scripts/time.sh allow-timezone: lets $USER
// change the timezone without a password (automatic timezone in the TimeApp).
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.timedate1.set-timezone" &&
        subject.user == "$USER" && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
JS
    chmod 644 "$tmp"
    pkexec /usr/bin/install -m 644 -o root -g root "$tmp" "$TIMEZONE_POLKIT_RULE" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    case $rc in
        0) ;;
        126|127) error "Password prompt dismissed"; exit 2 ;;
        *) error "Couldn't install $TIMEZONE_POLKIT_RULE"; exit 3 ;;
    esac
}

case "${1:-}" in
    status)         status ;;
    timezones)      timezones ;;
    locales)        locales ;;
    set-timezone)   set_timezone "${2:-}" ;;
    set-ntp)        set_ntp "${2:-}" ;;
    set-time)       set_time "${2:-}" ;;
    set-locale)     shift; set_locale "$@" ;;
    add-locale)     add_locale "${2:-}" ;;
    auto-timezone)  auto_timezone ;;
    allow-timezone) allow_timezone ;;
    *)
        echo "Usage: $(basename "$0") status | timezones | locales | set-timezone ZONE | set-ntp on|off |" \
            "set-time 'YYYY-MM-DD HH:MM[:SS]' | set-locale VAR=VALUE... | add-locale NAME |" \
            "auto-timezone | allow-timezone" >&2
        exit 1 ;;
esac
