#!/usr/bin/env bash
# Pick a command from ~/.quicklinks with fzf and run it.
# File format, one per line: Name | Description | Command

config_file="$HOME/.quicklinks"

if [ ! -f "$config_file" ]; then
    echo "Quicklinks file not found: $config_file"
    echo "Format: Name | Description | Command"
    read -p "Create a template file now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Example | This is a description | echo 'Hello World'" > "$config_file"
        echo "Template created. Edit it and run this again."
    fi
    exit 1
fi

selected=$(fzf \
    --style full \
    --height 40% --layout reverse --border \
    --prompt "🚀 Quick Access: " \
    --delimiter "|" --with-nth 1..3 < "$config_file")

[ -z "$selected" ] && exit 0

command=$(echo "$selected" | cut -d'|' -f3- | sed 's/^[[:space:]]*//')
echo "🚀 Executing: $command"
eval "$command"
