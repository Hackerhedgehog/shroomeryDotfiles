#!/usr/bin/env bash
# Uninstall an app picked in the launcher.
# Usage: uninstall-app.sh --plan|--run <desktop-entry-id>
#   --plan  prints what would be removed (first line: "Uninstall NAME (kind)", then one line per step) and
#           "default=y|n" last; exit 1 + a message if it doesn't know how the app was installed.
#   --run   does it, printing progress; stderr is merged into stdout; exit status is the result.
# Kinds:
#   local app (Exec under ~/AppImages): deletes the AppImage (or its folder), the .desktop file and the icon
#     if it lives in ~/AppImages/icons.
#   pacman / AUR (the .desktop file is owned by a package): pacman -Rns <package> through pkexec.
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
# First word of Exec (quotes honored), without field codes.
bin=$(python3 -I -c 'import shlex,sys; w=shlex.split(sys.argv[1]); print(w[0] if w else "")' "$(value Exec)" 2>/dev/null)
[[ $bin == /* ]] || bin=$(command -v -- "$bin" 2>/dev/null)
icon=$(value Icon)

remove=()
if [[ $bin == "$appdir"/* ]]; then
    kind="local app in ~/AppImages"
    rel=${bin#"$appdir"/}
    top=$appdir/${rel%%/*}
    case ${rel%%/*} in icons|LocalDesktopFiles|"") echo "Refusing to remove $top."; exit 1 ;; esac
    remove=("$top" "$desktop")
    [[ $icon == "$appdir"/icons/* && -e $icon ]] && remove+=("$icon")
elif pkg=$(pacman -Qqo "$desktop" 2>/dev/null); then
    if pacman -Qmq "$pkg" >/dev/null 2>&1; then kind="AUR package"; else kind="pacman package"; fi
else
    echo "Don't know how '$name' was installed ($desktop); nothing to remove."
    exit 1
fi

if [[ $mode == --plan ]]; then
    echo "Uninstall $name ($kind)"
    if [[ ${#remove[@]} -gt 0 ]]; then
        printf 'delete %s\n' "${remove[@]}"
    else
        echo "pacman -Rns $pkg (asks for your password)"
    fi
    echo "default=n"
    exit 0
fi

if [[ ${#remove[@]} -gt 0 ]]; then
    for path in "${remove[@]}"; do
        echo "Deleting $path"
        rm -rf -- "$path" || exit 1
    done
else
    echo "Running pacman -Rns $pkg"
    pkexec pacman -Rns --noconfirm "$pkg" || exit 1
fi
echo "Done."
