#!/usr/bin/env bash
# Terminal app launcher: pick a desktop entry (system, user, Flatpak) with fzf
# and start it detached.

dirs=(/usr/share/applications "$HOME/.local/share/applications")

# Name | Exec | file, one line per desktop entry (field codes like %U removed).
list=$(find -L "${dirs[@]}" -name "*.desktop" -type f 2>/dev/null | xargs -r awk -F'=' '
    function print_entry() {
        if (name != "" && exec != "") {
            icon = (is_term == "true") ? " " : "󰀻 "
            printf "%s %s | %s | %s\n", icon, name, exec, f
        }
    }
    f != FILENAME { print_entry(); f = FILENAME; name = ""; exec = ""; is_term = "false" }
    /^Name=/     { if (!name) { sub(/^Name=/, ""); name = $0 } }
    /^Exec=/     { if (!exec) { sub(/^Exec=/, ""); exec = $0; gsub(/%[a-zA-Z]/, "", exec) } }
    /^Terminal=/ { sub(/^Terminal=/, ""); is_term = tolower($0) }
    END { print_entry() }
' 2>/dev/null)

if command -v flatpak >/dev/null 2>&1; then
    while IFS=$'\t' read -r id fp_name; do
        [ -z "$id" ] && continue
        fp_file=$(find /var/lib/flatpak/exports/share/applications/ \
            "$HOME/.local/share/flatpak/exports/share/applications/" \
            -name "$id.desktop" 2>/dev/null | head -n 1)
        [ -z "$fp_file" ] && continue
        fp_exec=$(grep -m 1 "^Exec=" "$fp_file" | cut -d= -f2- | sed "s/%[a-zA-Z]//g" | xargs)
        list+=$'\n'"󰏖  $fp_name | $fp_exec | $fp_file"
    done < <(flatpak list --app --columns=application,name 2>/dev/null)
fi

selected=$(printf '%s\n' "$list" | grep . | sort -u | fzf \
    --style full \
    --delimiter '|' \
    --with-nth '1,2' \
    --height 40% \
    --layout reverse \
    --border \
    --prompt "🚀 Run: " \
    --header "󰀻 System | 󰏖 Flatpak |   Terminal")

[ -z "$selected" ] && exit 0

cmd=$(echo "$selected" | cut -d'|' -f2 | xargs)
# shellcheck disable=SC2086
setsid $cmd >/dev/null 2>&1 &
