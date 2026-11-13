#!/usr/bin/env bash
# Check that every program, QML module and Python module the dotfiles use
# comes from a package install.sh installs: one in install/packages/*.txt, a
# dependency of one, or part of `base`.
#
# Usage: bash install/tests/deps.sh [-v]
#   -v   also list every command found and the package that covers it
#
# How it finds what's used (a heuristic, so install/tests/deps-ignore.txt lists
# the words it picks up wrongly, and programs that are optional):
#   - shell scripts: every word outside comments
#   - QML, JS, Lua, Python, TOML, conf: the words inside string literals
#   - QML `import Foo.Bar` lines, Python `import foo` lines
# A word counts when it is a program installed on THIS machine (in /usr/bin),
# and its owning package is looked up with pacman. Programs that aren't
# installed here can't be looked up and are not checked.
#
# Exit 0 when everything is covered, 1 when something isn't.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
PACKAGES_DIR="$REPO_DIR/install/packages"
IGNORE_FILE="$TESTS_DIR/deps-ignore.txt"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

for tool in pacman pactree python3; do
    command -v "$tool" >/dev/null || { echo "deps.sh needs $tool (pactree: pacman-contrib)" >&2; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
problem() { printf '  ✗ %s\n' "$*"; fail=1; }
warn()    { printf '  ! %s\n' "$*"; }

list_words() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$@" | grep -v '^$'; }

# --- what install.sh installs -------------------------------------------------
# Every dependency name (and virtual name) reachable from a listed package or
# from base. pactree prints "name" or "name=version"/"name>=version".
mapfile -t LISTED < <(list_words "$PACKAGES_DIR/pacman.txt" "$PACKAGES_DIR/aur.txt")
not_installed=()
for pkg in base "${LISTED[@]}"; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        pactree -lu "$pkg" 2>/dev/null
    else
        not_installed+=("$pkg")
        echo "$pkg"
    fi
done | sed -E 's/[<>=].*//' | sort -u > "$WORK/covered"
[ ${#not_installed[@]} -gt 0 ] && warn "listed but not installed here, so their dependencies aren't known: ${not_installed[*]}"

# covered PKG — PKG, or something it provides, is in the closure.
covered() {
    grep -qxF "$1" "$WORK/covered" && return 0
    local provided
    provided=$(pacman -Qi "$1" 2>/dev/null | awk -F': ' '/^Provides/ { print $2 }' | tr ' ' '\n' | sed -E 's/[<>=].*//')
    [ -n "$provided" ] && [ "$provided" != None ] && grep -qxFf <(printf '%s\n' "$provided") "$WORK/covered"
}

# --- ignore list: "word  # reason" ------------------------------------------------
list_words "$IGNORE_FILE" | sort -u > "$WORK/ignore"
ignored() { grep -qxF "$1" "$WORK/ignore"; }

# --- source files -----------------------------------------------------------------
find "$REPO_DIR/hypr" "$REPO_DIR/quickshell" "$REPO_DIR/shroomery" "$REPO_DIR/matugen" \
    \( -name .git -o -name __pycache__ -o -name tests -o -name docs -o -name .superpowers \
       -o -path '*/WallpaperApp/wallpapers' \) -prune -o -type f -print \
    | grep -vE '\.(md|png|jpg|svg|qsb|frag|json|tsv|css|theme|qml\.colors)$' | sort > "$WORK/files"

rel() { printf '%s\n' "${1#"$REPO_DIR"/}"; }

# "word<TAB>file" for every candidate program word
while IFS= read -r f; do
    r=$(rel "$f")
    if [[ "$f" == *.sh ]] || head -n1 "$f" | grep -qE '^#!.*\b(ba)?sh\b'; then
        # shell: every word, comments dropped
        sed -E 's/(^|[[:space:]])#.*//' "$f"
    elif [[ "$f" =~ \.(qml|js|lua|py|toml|conf)$ ]]; then
        # everything else: words inside string literals, comment lines dropped
        grep -vE '^[[:space:]]*(//|--|#|\*)' "$f" | grep -oE "\"[^\"]*\"|'[^']*'"
    fi | grep -oE '[A-Za-z][A-Za-z0-9_+-]*' | sort -u | sed "s|\$|\t$r|"
done < "$WORK/files" > "$WORK/words"

# --- programs -----------------------------------------------------------------------
cut -f1 "$WORK/words" | sort -u | while IFS= read -r word; do
    ignored "$word" && continue
    path=$(type -P "$word" 2>/dev/null) || continue
    case "$path" in /usr/bin/*|/bin/*) ;; *) continue ;; esac
    pkg=$(pacman -Qoq "$path" 2>/dev/null) || { printf '%s\t%s\n' "$word" "?"; continue; }
    printf '%s\t%s\n' "$word" "$pkg"
done > "$WORK/programs"

echo "programs:"
checked=0
while IFS=$'\t' read -r word pkg; do
    checked=$((checked + 1))
    users=$(awk -F'\t' -v w="$word" '$1 == w { print $2 }' "$WORK/words" | head -3 | paste -sd, - | sed 's/,/, /g')
    if [ "$pkg" = "?" ]; then
        problem "$word ($(type -P "$word")) isn't from any package — used in $users"
    elif covered "$pkg"; then
        [ "$VERBOSE" = 1 ] && printf '  ✓ %-24s %s\n' "$word" "$pkg"
    else
        problem "$word (package $pkg) isn't installed by install.sh — used in $users"
    fi
done < "$WORK/programs"
echo "  $checked checked"

# --- QML modules ------------------------------------------------------------------
echo "QML modules:"
QML_DIR=/usr/lib/qt6/qml
grep -hoE '^[[:space:]]*import[[:space:]]+[A-Z][A-Za-z0-9.]*' $(grep -E '\.qml$' "$WORK/files") 2>/dev/null \
    | awk '{ print $2 }' | sort -u > "$WORK/qml"
while IFS= read -r mod; do
    ignored "$mod" && continue
    qmldir="$QML_DIR/${mod//.//}/qmldir"
    if [ ! -f "$qmldir" ]; then
        problem "QML module $mod isn't installed here ($qmldir missing)"
        continue
    fi
    pkg=$(pacman -Qoq "$qmldir" 2>/dev/null | head -n1)
    if covered "$pkg"; then
        [ "$VERBOSE" = 1 ] && printf '  ✓ %-24s %s\n' "$mod" "$pkg"
    else
        users=$(grep -lE "^[[:space:]]*import[[:space:]]+${mod//./\\.}([[:space:]]|$)" $(grep -E '\.qml$' "$WORK/files") | head -3 | while read -r f; do rel "$f"; done | paste -sd, - | sed 's/,/, /g')
        problem "QML module $mod (package $pkg) isn't installed by install.sh — used in $users"
    fi
done < "$WORK/qml"
echo "  $(wc -l < "$WORK/qml") checked"

# --- Python modules -----------------------------------------------------------------
# Third-party only: the standard library comes with python, and modules that
# live next to the scripts (screencolors) come with the repo.
echo "Python modules:"
grep -hoE '^[[:space:]]*(import|from)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $(grep -E '\.py$' "$WORK/files") 2>/dev/null \
    | awk '{ print $2 }' | sort -u > "$WORK/py"
local_mods=$(find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o \( -name '*.py' -o -name '__init__.py' \) -print \
    | sed -E 's|.*/([^/]+)/__init__\.py$|\1|; s|.*/([^/]+)\.py$|\1|' | sort -u)
python3 -I -c 'import sys; print("\n".join(sorted(sys.stdlib_module_names)))' > "$WORK/stdlib"
py_checked=0
while IFS= read -r mod; do
    grep -qxF "$mod" "$WORK/stdlib" && continue
    grep -qxF "$mod" <<<"$local_mods" && continue
    ignored "$mod" && continue
    py_checked=$((py_checked + 1))
    file=$(python3 -I -c "import $mod, sys; sys.stdout.write($mod.__file__ or '')" 2>/dev/null)
    if [ -z "$file" ]; then
        problem "Python module $mod isn't installed here"
        continue
    fi
    pkg=$(pacman -Qoq "$file" 2>/dev/null)
    if [ -z "$pkg" ]; then
        problem "Python module $mod ($file) isn't from a package (pip?)"
    elif covered "$pkg"; then
        [ "$VERBOSE" = 1 ] && printf '  ✓ %-24s %s\n' "$mod" "$pkg"
    else
        problem "Python module $mod (package $pkg) isn't installed by install.sh"
    fi
done < "$WORK/py"
echo "  $py_checked third-party checked"

echo
if [ "$fail" = 0 ]; then
    echo "OK: everything found is covered by install/packages/"
else
    echo "FAIL: add the package to install/packages/pacman.txt (or aur.txt), or the"
    echo "word to install/tests/deps-ignore.txt when it isn't really a dependency."
fi
exit "$fail"
