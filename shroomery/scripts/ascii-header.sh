#!/usr/bin/env bash
# Ask for a text, render it with figlet (smslant) as a `cat <<"EOF"` block,
# show it and copy it to the clipboard.
# Usage: ascii-header.sh [TEXT]

text="$*"
if [ -z "$text" ]; then
    figlet -f smslant "Figlet"
    echo
    read -r -p "Enter the text for ascii encoding: " text
fi
[ -z "$text" ] && exit 0

header=$(printf 'cat <<"EOF"\n%s\n\nEOF\n' "$(figlet -f smslant "$text")")
echo "$header"
printf '%s\n' "$header" | wl-copy
echo "Copied to clipboard."
