#!/usr/bin/env bash
# fzf file finder over the current directory (4 levels deep).
# Prints TYPE_DIR:<path> or TYPE_FILE:<path> for the `finder` shell function
# (bashrc/zshrc 30-autostart), which cds into a directory or opens a file.
# Prints nothing when cancelled.

list=$(find -L . -mindepth 1 -maxdepth 4 -printf "%y %p\n" 2>/dev/null | awk '
    $1 == "d" { print " " $2 }
    $1 == "f" { print "󰈚 " $2 }
    $1 == "l" { print " " $2 }
')

selected=$(printf '%s\n' "$list" | fzf \
    --style full \
    --height 50% \
    --layout reverse \
    --border \
    --prompt "🔍 Finder: " \
    --with-nth 2..)

[ -z "$selected" ] && exit 0

icon=${selected%% *}
path=${selected#* }

if [ "$icon" = "" ]; then
    echo "TYPE_DIR:$path"
else
    echo "TYPE_FILE:$path"
fi
