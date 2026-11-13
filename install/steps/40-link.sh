#!/usr/bin/env bash
# Symlink hypr, quickshell, shroomery and matugen into ~/.config (old ones are backed up).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

run mkdir -p "$CONFIG_DIR"

for part in "${LINKED_PARTS[@]}"; do
    src="$REPO_DIR/$part"
    dest="$CONFIG_DIR/$part"
    [ -d "$src" ] || die "missing $src"

    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
        ok "~/.config/$part already links here"
        continue
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        moved=$(backup "$dest")
        warn "moved the old ~/.config/$part to ${moved/#$HOME/\~}"
    fi
    run ln -s "$src" "$dest" || die "linking $dest failed"
    ok "~/.config/$part -> ${src/#$HOME/\~}"
done

# A zip download instead of a git clone loses the executable bits.
if [ "$DRY_RUN" != 1 ]; then
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type f \( -name '*.sh' -o -name '*.py' \) \
        -exec grep -lq '^#!' {} \; -exec chmod +x {} +
fi
ok "scripts are executable"
