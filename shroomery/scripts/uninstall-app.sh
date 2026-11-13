#!/usr/bin/env bash
# Uninstall an app picked in the launcher.
# Usage: uninstall-app.sh --plan|--run <desktop-entry-id>
#   --plan  prints what would be removed (first line: "Uninstall NAME (kind)", then one line per step,
#           then an optional note) and "default=y|n" last; exit 1 + a message if it can't remove anything.
#   --run   does it, printing progress; stderr is merged into stdout; exit status is the result.
# Each kind sets `cmd` (run first) and/or `remove` (files deleted after). Kinds, in the order tested:
#   local app (Exec under ~/AppImages, also relative to Path=): deletes the AppImage (or its folder), the
#     .desktop file and the icon if it lives in ~/AppImages/icons.
#   browser web app (a ~/.local .desktop whose Exec has --app-id=): deletes the shortcut and its icons only.
#   Steam game (Exec runs steam://rungameid/N): `steam steam://uninstall/N` (Steam asks to confirm), then
#     deletes the shortcut and its steam_icon_N icons.
#   JetBrains Toolbox app (Exec under ~/.local/share/JetBrains/Toolbox/apps): opens Toolbox, which owns it.
#   Flatpak (.desktop in a flatpak exports dir): flatpak uninstall --system|--user (polkit asks for system).
#   pacman / AUR / local package: pacman -Rns <package> through pkexec, plus the ~/.local shortcut if any.
#     The package owns the .desktop file, or else it owns the Exec binary and either ships a file named like
#     the .desktop (an install script copied it into /usr/share/applications, e.g. RustDesk) or is named
#     exactly like the entry (the app wrote its own ~/.local shortcut, e.g. jetbrains-toolbox). Never by the
#     binary's name: a shortcut that merely *runs* some packaged program (ncdu.desktop: `kitty sudo ncdu`)
#     must not uninstall that program (kitty).
#   anything else in ~/.local/share/applications: deletes the shortcut only and says what stays.
exec 2>&1
appdir="$HOME/AppImages"
mode=${1:?--plan or --run}
id=${2:?desktop entry id required}

desktop=
for dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications \
           /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
    if [[ -f "$dir/$id.desktop" ]]; then desktop="$dir/$id.desktop"; break; fi
done
[[ -n $desktop ]] || { echo "Could not find the .desktop file for '$id'."; exit 1; }

value() { grep -m1 "^$1=" "$desktop" | cut -d= -f2-; }
name=$(value Name)
exec_line=$(value Exec)
icon=$(value Icon)
workdir=$(value Path)
# First word of Exec (quotes honored), without field codes; relative paths resolve against Path=.
bin=$(python3 -I -c 'import shlex,sys; w=shlex.split(sys.argv[1]); print(w[0] if w else "")' "$exec_line" 2>/dev/null)
if [[ $bin == */* && $bin != /* ]]; then
    [[ -n $workdir ]] && bin=$(realpath -m -- "$workdir/$bin")
elif [[ $bin != /* ]]; then
    bin=$(command -v -- "$bin" 2>/dev/null)
fi
user_desktop=false
[[ $desktop == "$HOME"/.local/share/applications/* ]] && user_desktop=true

# Icons in ~/.local/share/icons/hicolor named after this entry's Icon= (only for app-specific names).
add_icons() {
    [[ -n $icon && $icon != */* ]] || return 0
    local f
    for f in "$HOME"/.local/share/icons/hicolor/*/apps/"$icon".{png,svg}; do
        [[ -e $f ]] && remove+=("$f")
    done
    return 0
}
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

remove=()
cmd=()
label=   # what the plan/progress calls cmd; empty = the command itself
note=
steam_id=$(grep -oP 'steam://rungameid/\K[0-9]+' <<<"$exec_line" | head -1)
toolbox_apps="$HOME/.local/share/JetBrains/Toolbox/apps"

if [[ $bin == "$appdir"/* ]]; then
    kind="local app in ~/AppImages"
    rel=${bin#"$appdir"/}
    top=$appdir/${rel%%/*}
    case ${rel%%/*} in icons|LocalDesktopFiles|"") echo "Refusing to remove $top."; exit 1 ;; esac
    remove=("$top" "$desktop")
    [[ $icon == "$appdir"/icons/* && -e $icon ]] && remove+=("$icon")
elif $user_desktop && grep -q -- '--app-id=' <<<"$exec_line"; then
    # A Chrome/Chromium/Brave/Edge web app shortcut: Exec is the *browser* binary, so never look at its
    # package. Only the shortcut and its icons go; the app itself lives in the browser profile.
    kind="browser web app shortcut"
    remove=("$desktop")
    add_icons
    note="The app stays installed in the browser; remove it there too (e.g. chrome://apps) or the browser may recreate the shortcut."
elif [[ -n $steam_id ]]; then
    kind="Steam game"
    # setsid: if Steam isn't running, `steam` starts it and would not return.
    cmd=(setsid -f steam "steam://uninstall/$steam_id")
    $user_desktop && { remove=("$desktop"); add_icons; }
    note="Steam opens its own uninstall dialog; the shortcut goes even if you cancel there."
elif [[ $bin == "$toolbox_apps"/* ]]; then
    kind="managed by JetBrains Toolbox"
    toolbox=$(command -v jetbrains-toolbox || echo /opt/jetbrains-toolbox/jetbrains-toolbox)
    [[ -x $toolbox ]] || { echo "'$name' is managed by JetBrains Toolbox, which isn't installed; delete $toolbox_apps/${bin#"$toolbox_apps"/} by hand."; exit 1; }
    cmd=(setsid -f "$toolbox")
    label="open JetBrains Toolbox"
    note="Opens JetBrains Toolbox: uninstall $name there (the ⋮ menu next to it), so Toolbox removes its files and shortcut."
elif [[ $desktop == /var/lib/flatpak/exports/* || $desktop == "$HOME"/.local/share/flatpak/exports/* ]]; then
    # Flatpak exports are named after the app id (com.discordapp.Discord.desktop).
    if [[ $desktop == /var/lib/* ]]; then scope=--system; else scope=--user; fi
    flatpak info "$scope" "$id" >/dev/null 2>&1 || { echo "Flatpak '$id' is not installed ($scope)."; exit 1; }
    kind="Flatpak, ${scope#--}"
    # Keeps the app's data in ~/.var/app; leftover runtimes go with `flatpak uninstall --unused`.
    cmd=(flatpak uninstall "$scope" --noninteractive "$id")
    note="Your data in ~/.var/app/$id is kept."
elif pkg=$(pacman -Qqo "$desktop" 2>/dev/null) ||
     { [[ $bin == /* ]] && pkg=$(pacman -Qqo "$bin" 2>/dev/null) &&
       { { [[ $desktop == /usr/* ]] && pacman -Qlq "$pkg" | grep -q "/$id\.desktop$"; } ||
         { $user_desktop && [[ $(lower "$pkg") == "$(lower "$id")" ]]; }; }; }; then
    if pacman -Qmq "$pkg" >/dev/null 2>&1; then kind="AUR or local package"; else kind="pacman package"; fi
    cmd=(pkexec pacman -Rns --noconfirm "$pkg")
    # pacman doesn't own a shortcut the app wrote into ~/.local itself.
    $user_desktop && remove=("$desktop")
elif $user_desktop; then
    kind="shortcut only"
    remove=("$desktop")
    if [[ -z $bin || ! -e $bin ]]; then
        note="The program it starts isn't installed any more; this removes the leftover shortcut."
    elif [[ $bin == "$HOME"/* ]]; then
        note="Only the shortcut goes; the program in ${bin%/*} stays, delete that folder yourself."
    elif owner=$(pacman -Qqo "$bin" 2>/dev/null); then
        note="Only the shortcut goes; it runs $bin, which belongs to the $owner package and stays installed."
    else
        real=$(readlink -f -- "$bin")
        note="Only the shortcut goes; ${real%/*} (installed by hand, not from a package) stays, delete it yourself."
    fi
else
    if [[ $bin == /* && -e $bin ]]; then
        echo "'$name' was installed outside pacman ($bin belongs to no package, e.g. make/meson install); remove it with the tool that built it."
    else
        echo "Don't know how '$name' was installed ($desktop); nothing to remove."
    fi
    exit 1
fi

# The command as shown to the user: without pkexec/setsid and the non-interactive flags.
shown=()
for w in "${cmd[@]}"; do
    case $w in pkexec|setsid|-f|--noconfirm|--noninteractive) ;; *) shown+=("$w") ;; esac
done
[[ -n $label ]] && shown=("$label")

if [[ $mode == --plan ]]; then
    echo "Uninstall $name ($kind)"
    if [[ ${#cmd[@]} -gt 0 ]]; then
        if [[ ${cmd[0]} == pkexec || ${cmd[0]} == flatpak ]]; then
            echo "${shown[*]} (may ask for your password)"
        else
            echo "${shown[*]}"
        fi
    fi
    [[ ${#remove[@]} -gt 0 ]] && printf 'delete %s\n' "${remove[@]}"
    [[ -n $note ]] && echo "$note"
    echo "default=n"
    exit 0
fi

if [[ ${#cmd[@]} -gt 0 ]]; then
    echo "Running ${shown[*]}"
    "${cmd[@]}" || exit 1
fi
for path in "${remove[@]}"; do
    echo "Deleting $path"
    rm -rf -- "$path" || exit 1
done
echo "Done."
