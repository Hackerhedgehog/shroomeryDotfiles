#!/usr/bin/env bash
# Library for pkg-update.sh (safe system updates): protected package set,
# manifests, atomic writes, state. Sourced after lib.sh; defines functions only.
#
# Environment overrides (tests use them; each is read when a function runs):
#   PKG_RECOVERY_DIR    recovery storage          (default: lib.sh RECOVERY_DIR)
#   PKG_CACHE_DIR       pacman package cache      (default: /var/cache/pacman/pkg; lib.sh keeps it)
#   PKG_PACMAN          pacman command, may hold arguments (default: pacman)
#   PKG_PACMAN_CONF     pacman config             (default: /etc/pacman.conf)
#   PKG_DBPATH          the real pacman DBPath    (default: DBPath of the config, else /var/lib/pacman)
#   XDG_RUNTIME_DIR     holds the update check's temp DB (default: /tmp)
#   PKG_PROTECTED_FILE  protected pattern list    (default: lib.sh PROTECTED_FILE)
#   PKG_ARCHIVE_URL     Arch Linux Archive base   (default: https://archive.archlinux.org/packages;
#                       https or file:// only)
#   PKG_VERIFY          signature check command, run as `$PKG_VERIFY SIGFILE PKGFILE`
#                       (default: pkg_verify_signature, gpg against the pacman keyring)
#   PKG_GPG_DIR         gpg home of that keyring  (default: pacman-conf GPGDir, /etc/pacman.d/gnupg)
#   PKG_FREE_BYTES      free space of the cache filesystem, bytes (default: measured with stat -f)
#   PKG_PACMAN_DBLOCK   pacman's database lock    (default: /var/lib/pacman/db.lck)
#   PKG_CACHE_KEEP_FILE cache-keep setting file   (default: lib.sh CACHE_KEEP_FILE)
#   PKG_PKEXEC          the pkexec command        (default: pkexec)
#   PKG_NO_ELEVATE      set: elevate() never re-executes (tests, or already prepared)
#   PKG_TEST_EUID       set to 0: pretend to be root in elevate() and apply's refresh (tests)
#   PKG_PACCACHE        paccache command for apply and `cache keep` (default: paccache)
#   PKG_QS              qs command for apply's statusbar refresh (default: qs; skipped when missing)
#   PKG_QS_TIMEOUT      seconds before that refresh is given up (default 5)
#   PKG_VERIFY_KERNEL|GPU|SERVICES|JOURNAL|NETWORK
#                       a command that replaces one verify check: exit 0 = PASS, else FAIL (tests)
#   PKG_RECOVERY_SRC    the recovery.sh promote installs (default: recovery.sh next to this file)
#
# Settings the root process gets from the user (the only PKG_ names elevate() forwards;
# a root process never reads $HOME, so the user's side resolves them before pkexec):
#   PKG_CACHE_KEEP         versions per package to keep, 1..20 (default 3)
#   PKG_PROTECTED_PATTERNS the protected name patterns, newline separated
#   PKG_USER_HOME          the user's home directory (for later steps that need it)

DEFAULT_PROTECTED_PATTERNS=(linux linux-headers 'linux-lts*' 'nvidia*' egl-wayland
    'linux-firmware*' amd-ucode intel-ucode 'mkinitcpio*' grub systemd systemd-libs
    glibc mesa vulkan-radeon libdrm)

pkg_recovery_dir()  { printf '%s\n' "${PKG_RECOVERY_DIR:-$RECOVERY_DIR}"; }
pkg_cache_dir()     { printf '%s\n' "${PKG_CACHE_DIR:-/var/cache/pacman/pkg}"; }
pkg_pacman_conf()   { printf '%s\n' "${PKG_PACMAN_CONF:-/etc/pacman.conf}"; }
pkg_protected_file(){ printf '%s\n' "${PKG_PROTECTED_FILE:-$PROTECTED_FILE}"; }
# Word-splitting is intended: PKG_PACMAN may be "pacman --config X".
# LC_ALL=C: output is parsed (field names, "error:" prefixes), so never translated.
# 200>&-: never hand the update lock (acquire_lock) to pacman or what its hooks start.
pkg_pacman()        { LC_ALL=C ${PKG_PACMAN:-pacman} "$@" 200>&-; }

# _is_root: really root, or pretending to be (PKG_TEST_EUID=0, tests). The variable can only
# add root-ness, never take it away: a real root with it set to something else is still root.
_is_root() { [ "$EUID" = 0 ] || [ "${PKG_TEST_EUID:-}" = 0 ]; }

pkg_dblock()          { printf '%s\n' "${PKG_PACMAN_DBLOCK:-/var/lib/pacman/db.lck}"; }
pkg_cache_keep_file() { printf '%s\n' "${PKG_CACHE_KEEP_FILE:-$CACHE_KEEP_FILE}"; }

# --- settings: the environment first, the user's files second --------------------
# Root gets the settings through PKG_CACHE_KEEP / PKG_PROTECTED_PATTERNS (see elevate),
# so with them set no file under $HOME is read.

# settings_cache_keep: versions per package to keep, an integer 1..20; anything else,
# or a missing setting, gives 3. PKG_CACHE_KEEP wins over the file.
settings_cache_keep() {
    local v=${PKG_CACHE_KEEP:-} file
    if [ -z "$v" ]; then
        file=$(pkg_cache_keep_file)
        [ -f "$file" ] && v=$(head -n 1 -- "$file" 2>/dev/null | tr -d '[:space:]')
    fi
    case $v in
        ''|*[!0-9]*) v=3 ;;
        *) v=$((10#$v)); [ "$v" -ge 1 ] && [ "$v" -le 20 ] || v=3 ;;
    esac
    printf '%s\n' "$v"
}

# _pattern_lines: stdin to stdout without CRs, surrounding blanks, empty and # lines.
_pattern_lines() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$line" in ''|'#'*) continue ;; esac
        printf '%s\n' "$line"
    done
}

# settings_protected: the protected name patterns, one per line. PKG_PROTECTED_PATTERNS
# (newline separated) wins; else the settings file (blanks and # lines skipped); else
# the default list when there is no env, no file or no pattern in it.
settings_protected() {
    local file found
    if [ -n "${PKG_PROTECTED_PATTERNS:-}" ]; then
        found=$(_pattern_lines <<<"$PKG_PROTECTED_PATTERNS")
        if [ -n "$found" ]; then printf '%s\n' "$found"; return 0; fi
    fi
    file=$(pkg_protected_file)
    if [ -f "$file" ]; then
        found=$(_pattern_lines < "$file")
        if [ -n "$found" ]; then printf '%s\n' "$found"; return 0; fi
    fi
    printf '%s\n' "${DEFAULT_PROTECTED_PATTERNS[@]}"
}

# Protected name patterns (see settings_protected).
protected_patterns() { settings_protected; }

# "name version" lines of every installed package (pacman -Q). Fails with a
# message on stderr when pacman fails, so no caller ever builds on an empty list.
pkg_installed() {
    local out
    if ! out=$(pkg_pacman -Q); then
        error "pacman -Q failed; cannot read the installed packages"
        return 1
    fi
    printf '%s\n' "$out"
}

# _pkg_exact_deps: "dependent<TAB>target" for every installed package with an exact versioned
# dependency (`target=X` or `target=X-REL`; never >=, <=, <, >) in `pacman -Qi`'s "Depends On"
# (continuation lines included). Fails with a message when pacman -Qi fails.
_pkg_exact_deps() {
    local info
    if ! info=$(pkg_pacman -Qi); then
        error "pacman -Qi failed; cannot read the package dependencies"
        return 1
    fi
    awk '
        /^[^ \t][^:]*: / {
            field = substr($0, 1, index($0, ":") - 1); sub(/[ \t]+$/, "", field)
            value = substr($0, index($0, ":") + 1)
            if (field == "Name") { name = value; gsub(/[ \t]/, "", name) }
            else if (field == "Depends On") emit(value)
            next
        }
        /^[ \t]/ { if (field == "Depends On") emit($0); next }
        { field = "" }
        function emit(v,   n, i, d) {
            n = split(v, d, /[ \t]+/)
            for (i = 1; i <= n; i++)
                if (d[i] ~ /^[^<>=]+=[^=<>]/) { sub(/=.*/, "", d[i]); print name "\t" d[i] }
        }' <<<"$info"
}

# "name version" lines of the protected set, sorted: every installed package matching a protected
# pattern (glob match; patterns matching nothing are ignored), plus the closure over exact reverse
# dependencies: every installed package with an exact (=) versioned dependency on a package already
# in the set, repeated until nothing is added (lib32-glibc needs glibc=<exact>, systemd-sysvcompat
# systemd=<exact>). Restoring the set in one `pacman -U` would otherwise break such a package.
protected_installed() {
    local -a patterns
    local name version pat installed seeds edges
    installed=$(pkg_installed) || return 1
    mapfile -t patterns < <(protected_patterns)
    seeds=$(while read -r name version; do
        for pat in "${patterns[@]}"; do
            # shellcheck disable=SC2053  # glob match is the point
            if [[ $name == $pat ]]; then
                printf '%s\n' "$name"
                break
            fi
        done
    done <<<"$installed")
    edges=$(_pkg_exact_deps) || return 1
    awk -v seeds="$seeds" -v edges="$edges" '
        BEGIN {
            n = split(seeds, s, "\n"); for (i = 1; i <= n; i++) if (s[i] != "") in_set[s[i]] = 1
            m = split(edges, e, "\n")
            do {
                added = 0
                for (i = 1; i <= m; i++) {
                    if (split(e[i], p, "\t") != 2) continue
                    if ((p[2] in in_set) && !(p[1] in in_set)) { in_set[p[1]] = 1; added = 1 }
                }
            } while (added)
        }
        NF >= 2 && ($1 in in_set) { print $1 " " $2 }' <<<"$installed" | LC_ALL=C sort -u
}

# manifest_json KIND: the manifest of the current state as JSON on stdout.
# KIND (known-good|pending) is reserved for per-kind fields; unused so far.
# packages[].archive/sha256 stay empty until the capture step fills them.
manifest_json() {
    local created kernel patterns packages installed
    created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    kernel=$(uname -r)
    patterns=$(protected_patterns)
    installed=$(pkg_installed) || return 1
    packages=$(protected_installed) || return 1
    jq -n --arg created "$created" --arg kernel "$kernel" \
        --arg patterns "$patterns" --arg packages "$packages" --arg installed "$installed" '
        def lines: split("\n") | map(select(. != ""));
        def pairs: lines | map(split(" ") | {name: .[0], version: .[1]});
        { created: $created, kernel: $kernel,
          patterns: ($patterns | lines),
          packages: ($packages | pairs | map(. + {archive: "", sha256: ""})),
          installed: ($installed | pairs) }'
}

# write_atomic FILE: stdin to FILE.tmp.$$, then rename over FILE.
write_atomic() {
    local file=$1 tmp="$1.tmp.$$"
    if cat > "$tmp" && mv -f "$tmp" "$file"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# pkg_record KIND: print the manifest of recovery-dir/KIND as JSON if it exists
# and parses, else nothing.
pkg_record() {
    local file
    file="$(pkg_recovery_dir)/$1/manifest.json"
    [ -f "$file" ] && jq -c . "$file" 2>/dev/null
}

# pkg_matches_known_good RECORD INSTALLED: succeeds when INSTALLED (the output of
# protected_installed) equals the record's packages by name + version.
pkg_matches_known_good() {
    local recorded
    recorded=$(jq -r '.packages[]? | "\(.name) \(.version)"' <<<"$1" | LC_ALL=C sort -u)
    [ "$recorded" = "$2" ]
}

# _pkg_status_record NAME: recovery-dir/NAME (pending, pending.discarded) for pkg_status: `null` when it does not
# exist, its manifest when that is a readable JSON object, else {"unreadable":true} (it exists but says nothing).
_pkg_status_record() {
    local dir r
    dir="$(pkg_recovery_dir)/$1"
    if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then echo null; return 0; fi
    if r=$(pkg_record "$1") && [ -n "$r" ] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$r"; then
        printf '%s\n' "$r"
    else
        echo '{"unreadable":true}'
    fi
}

# pkg_status: {known_good: null|{created,kernel,forced,source,verified}, pending: null|{state,started,changed},
#              discarded: null|{state,started,changed}, matches: bool}
# known_good.source is "checkpoint" (apply's step 4) or "promote"; verified is true only for a non-forced promote.
# A manifest without the keys (written before they existed) counts as source "promote", verified unless forced.
# pending / discarded: pending/ and pending.discarded/ (what `discard` kept); changed = the number of packages
# whose version the update changed (null when the record does not list them). One that exists without a readable
# record is {state: "unknown"}, never null.
pkg_status() {
    local kg pending discarded installed matches=false
    installed=$(protected_installed) || return 1
    kg=$(pkg_record known-good)
    pending=$(_pkg_status_record pending)
    discarded=$(_pkg_status_record pending.discarded)
    [ -n "$kg" ] && pkg_matches_known_good "$kg" "$installed" && matches=true
    jq -n --argjson kg "${kg:-null}" --argjson pending "$pending" --argjson discarded "$discarded" --argjson matches "$matches" '
        def summary: if . == null then null
            elif .unreadable == true then {state: "unknown"}
            else {state: (.state // "unknown"), started,
                  changed: (if (.packages | type) == "array" then (.packages | length) else null end)} end;
        { known_good: ($kg | if . == null then null else
              {created, kernel, forced: (.forced // false), source: (.source // "promote"),
               verified: (if has("verified") then .verified == true else .forced != true end)} end),
          pending: ($pending | summary),
          discarded: ($discarded | summary),
          matches: $matches }'
}

# same_fs A B: succeeds when both paths exist and are on one filesystem.
same_fs() {
    local a b
    a=$(stat -c %d -- "$1") && b=$(stat -c %d -- "$2") || return 1
    [ "$a" = "$b" ]
}

# archive_for NAME VERSION: print the cache file for exactly this package, i.e.
# NAME-VERSION-<arch>.pkg.tar.zst where <arch> is one token (x86_64, any, ...).
# The epoch colon stays literal, as pacman stores it. Exit 1 when there is none.
# Plain string comparison, no glob, so `linux-6.15` never matches
# `linux-headers-...` or `linux-6.15-1-...`, and `.sig` files are ignored.
archive_for() {
    local name=$1 version=$2 cache f base rest
    cache=$(pkg_cache_dir)
    for f in "$cache"/*.pkg.tar.zst; do
        [ -f "$f" ] || continue
        base=${f##*/}
        case $base in "$name-$version-"*) ;; *) continue ;; esac
        rest=${base#"$name-$version-"}
        rest=${rest%.pkg.tar.zst}
        case $rest in ''|*-*) continue ;; esac
        printf '%s\n' "$f"
        return 0
    done
    return 1
}

# known_good_matches: succeeds when the installed protected set equals
# known-good/manifest.json by name + version (set equality).
known_good_matches() {
    local kg installed
    installed=$(protected_installed) || return 1
    kg=$(pkg_record known-good)
    [ -n "$kg" ] && pkg_matches_known_good "$kg" "$installed"
}

# checkpoint_build TARGET_DIR [SOURCE]: hardlink the cache archive of every installed
# protected package into TARGET_DIR/archives/ and write TARGET_DIR/manifest.json
# (archive file name + sha256 filled in). SOURCE (checkpoint|promote) is the provenance the
# manifest records as `source`, with `verified` true for promote (pkg_promote marks a forced one
# false); without SOURCE the keys are left out. Built in TARGET_DIR.tmp.$$ and renamed,
# so a failure or INT/TERM never leaves a partial TARGET_DIR. An existing
# TARGET_DIR is replaced only once the new one is complete and stays intact on
# any failure. On missing archives every "name version" is printed to stderr and
# the exit status is 1. Directories are 755 and the manifest 644 whatever the umask.
# A caller's own INT/TERM traps are restored and the signal re-raised after cleanup.
# Durability: the finished tmp tree is flushed to disk before the rename, and the filesystem is
# committed after the renames and before the old TARGET_DIR is deleted, so a power loss cannot leave
# the new manifest empty with the old (possibly the only verified) copy already gone.
CHECKPOINT_TMP=""
CHECKPOINT_TARGET=""
CHECKPOINT_OLD_INT=""
CHECKPOINT_OLD_TERM=""

# _pkg_sync_tree DIR: flush a built checkpoint (manifest.json, the archives/ entries, the directories) to disk.
_pkg_sync_tree() {
    sync -- "$1/manifest.json" "$1/archives" "$1" && sync -f -- "$1/manifest.json"
}
# _pkg_syncfs PATH: commit the filesystem PATH is on (the renames done so far and the data they point to).
_pkg_syncfs() { sync -f -- "$1"; }

# Remove the tmp build; finish or undo a half-done swap of the old TARGET_DIR.
_checkpoint_cleanup() {
    [ -z "$CHECKPOINT_TMP" ] || rm -rf -- "$CHECKPOINT_TMP"
    if [ -n "$CHECKPOINT_TARGET" ] && [ -e "$CHECKPOINT_TARGET.old.$$" ]; then
        if [ -e "$CHECKPOINT_TARGET" ]; then
            rm -rf -- "$CHECKPOINT_TARGET.old.$$"
        else
            mv -- "$CHECKPOINT_TARGET.old.$$" "$CHECKPOINT_TARGET"
        fi
    fi
}

# _checkpoint_signal SIG NUM: clean up, give the caller's traps back, re-raise.
_checkpoint_signal() {
    _checkpoint_cleanup
    trap - INT TERM
    [ -z "$CHECKPOINT_OLD_INT" ] || eval "$CHECKPOINT_OLD_INT"
    [ -z "$CHECKPOINT_OLD_TERM" ] || eval "$CHECKPOINT_OLD_TERM"
    kill -s "$1" $$
    exit $((128 + $2))   # the caller's handler returned: this build is still aborted
}

checkpoint_build() {
    local target=${1:?checkpoint_build: TARGET_DIR missing} source=${2:-} cache parent
    local manifest newmanifest name version archive sha entries="" shas="" missing="" rc=0
    case $source in ''|checkpoint|promote) ;; *) error "checkpoint_build: unknown SOURCE: $source"; return 2 ;; esac
    cache=$(pkg_cache_dir)
    parent=$(dirname -- "$target")
    [ -d "$cache" ] || { error "cache dir not found: $cache"; return 1; }
    mkdir -p -- "$parent" || { error "cannot create $parent"; return 1; }
    if ! same_fs "$cache" "$parent"; then
        error "$parent and $cache are on different filesystems; hardlinks need one filesystem"
        return 1
    fi
    manifest=$(manifest_json known-good) || return 1
    if [ "$(jq '.packages|length' <<<"$manifest")" = 0 ]; then
        error "no protected package is installed; refusing to write an empty checkpoint"
        return 1
    fi

    # Resolve every archive before touching the disk.
    while IFS=$'\t' read -r name version; do
        if archive=$(archive_for "$name" "$version"); then
            entries+="$name"$'\t'"${archive##*/}"$'\n'
        else
            missing+="$name $version"$'\n'
        fi
    done < <(jq -r '.packages[] | [.name, .version] | @tsv' <<<"$manifest")
    if [ -n "$missing" ]; then
        error "package archive missing from $cache for:"
        printf '%s' "$missing" >&2
        return 1
    fi

    CHECKPOINT_TMP="$target.tmp.$$"
    CHECKPOINT_TARGET=$target
    CHECKPOINT_OLD_INT=$(trap -p INT)
    CHECKPOINT_OLD_TERM=$(trap -p TERM)
    trap '_checkpoint_signal INT 2' INT
    trap '_checkpoint_signal TERM 15' TERM
    rm -rf -- "$CHECKPOINT_TMP"
    mkdir -p -- "$CHECKPOINT_TMP/archives" || rc=1
    [ "$rc" != 0 ] || chmod 755 -- "$CHECKPOINT_TMP" "$CHECKPOINT_TMP/archives" || rc=1

    if [ "$rc" = 0 ]; then
        while IFS=$'\t' read -r name archive; do
            [ -n "$name" ] || continue
            if ! ln -- "$cache/$archive" "$CHECKPOINT_TMP/archives/$archive"; then
                error "cannot hardlink $cache/$archive"; rc=1; break
            fi
            if ! sha=$(sha256sum < "$CHECKPOINT_TMP/archives/$archive"); then
                error "sha256sum failed for $archive"; rc=1; break
            fi
            shas+="$name"$'\t'"$archive"$'\t'"${sha%% *}"$'\n'
        done <<<"$entries"
    fi
    if [ "$rc" = 0 ]; then
        if newmanifest=$(jq --arg map "$shas" --arg src "$source" '
                ($map | split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: {archive: .[1], sha256: .[2]}}) | from_entries) as $m
                | .packages |= map(. + $m[.name])
                | if $src == "" then . else . + {source: $src, verified: ($src == "promote")} end' <<<"$manifest") && [ -n "$newmanifest" ]; then
            printf '%s\n' "$newmanifest" | write_atomic "$CHECKPOINT_TMP/manifest.json" \
                && chmod 644 -- "$CHECKPOINT_TMP/manifest.json" || rc=1
        else
            error "could not build the checkpoint manifest"; rc=1
        fi
    fi
    if [ "$rc" = 0 ] && ! _pkg_sync_tree "$CHECKPOINT_TMP"; then
        error "cannot flush the new checkpoint to disk; nothing was changed"; rc=1
    fi
    if [ "$rc" = 0 ]; then
        if [ -e "$target" ]; then
            mv -- "$target" "$target.old.$$" && mv -- "$CHECKPOINT_TMP" "$target" || rc=1
        else
            mv -- "$CHECKPOINT_TMP" "$target" || rc=1
        fi
        if [ "$rc" = 0 ] && ! _pkg_syncfs "$parent"; then   # barrier before the old copy goes
            error "cannot commit the checkpoint to disk; the previous one is kept"
            mv -- "$target" "$CHECKPOINT_TMP" || true   # cleanup below then restores the old target
            rc=1
        fi
    fi
    _checkpoint_cleanup   # failure: drops the tmp dir / undoes the swap; success: drops the old dir
    trap - INT TERM
    [ -z "$CHECKPOINT_OLD_INT" ] || eval "$CHECKPOINT_OLD_INT"
    [ -z "$CHECKPOINT_OLD_TERM" ] || eval "$CHECKPOINT_OLD_TERM"
    CHECKPOINT_TMP=""; CHECKPOINT_TARGET=""
    return "$rc"
}

# pacman_conf_without_ignores SRC DEST: DEST = SRC minus every IgnorePkg and
# IgnoreGroup line (leading whitespace allowed). All other lines stay byte-identical
# (including a missing final newline). SRC is never modified; on failure no DEST is left.
pacman_conf_without_ignores() {
    local src=${1:?pacman_conf_without_ignores: SRC missing} dest=${2:?pacman_conf_without_ignores: DEST missing}
    [ -r "$src" ] || { error "cannot read pacman config: $src"; return 1; }
    if [ "$src" -ef "$dest" ]; then
        error "refusing to rewrite the pacman config in place: $src"
        return 1
    fi
    if ! sed -E '/^[[:space:]]*Ignore(Pkg|Group)[[:space:]]*(=|$)/d' -- "$src" > "$dest"; then
        rm -f -- "$dest"
        error "could not write $dest"
        return 1
    fi
}

# pkg_real_dbpath: the real pacman database directory (no trailing slash).
pkg_real_dbpath() {
    local p=${PKG_DBPATH:-}
    if [ -z "$p" ] && command -v pacman-conf >/dev/null 2>&1; then
        p=$(pacman-conf --config "$(pkg_pacman_conf)" DBPath 2>/dev/null)
    fi
    [ -d "$p" ] || p=/var/lib/pacman
    printf '%s\n' "${p%/}"
}

# pkg_private_dir DIR: make sure DIR is a real directory (not a symlink) owned by
# the current user with mode 700; create it when missing.
pkg_private_dir() {
    local dir=$1
    if [ -L "$dir" ]; then
        error "$dir is a symbolic link; refusing to use it"
        return 1
    fi
    [ -d "$dir" ] || mkdir -p -m 700 -- "$dir" || { error "cannot create $dir"; return 1; }
    if [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
        error "$dir is not a directory owned by you; refusing to use it"
        return 1
    fi
    chmod 700 -- "$dir" || { error "cannot secure $dir"; return 1; }
}

# _pkg_qu CONF DB: run `pacman -Qu` against the temp DB DB with config CONF and
# print the pending updates as "name old -> new" lines. Ignored packages (pacman
# prints them with a trailing [ignored] marker) are left out, as checkupdates does.
# pacman exits 1 with no output when there is nothing to update: that prints nothing
# and succeeds. Any other failure (or an error message, or output that is not
# "name old -> new") fails with a message and prints nothing.
_pkg_qu() {
    local conf=$1 db=$2 out err rc errfile lines good
    errfile=$(mktemp "${TMPDIR:-/tmp}/pkg-qu-err.XXXXXX") || { error "cannot create a temp file"; return 1; }
    out=$(pkg_pacman --config "$conf" -Qu --dbpath "$db" --color never 2>"$errfile"); rc=$?
    err=$(cat "$errfile"); rm -f "$errfile"
    if [ "$rc" = 1 ] && [ -z "$out" ] && ! grep -q 'error:' <<<"$err"; then
        return 0
    fi
    if [ "$rc" != 0 ]; then
        error "pacman -Qu failed (exit status $rc)${err:+: ${err%%$'\n'*}}"
        return 1
    fi
    out=$(grep -v '\[.*\]' <<<"$out")   # grep exits 1 when only held lines were left
    [ -n "$out" ] || return 0
    lines=$(grep -c . <<<"$out")
    good=$(awk 'NF == 4 && $3 == "->"' <<<"$out" | grep -c .)
    if [ "$lines" != "$good" ]; then
        error "unexpected output from pacman -Qu: ${out%%$'\n'*}"
        return 1
    fi
    printf '%s\n' "$out"
}

# _check_updates_run REFRESH SYSTEM BASE TMPD: the body of check_updates, run under its
# lock. TMPD is a scratch dir the caller removes.
_check_updates_run() {
    local refresh=$1 system=$2 base=$3 tmpd=$4
    local db="$base/pkg-check-db" real conf stripped f logfile
    local -a pm
    real=$(pkg_real_dbpath)
    conf=$(pkg_pacman_conf)
    if [ -z "$db" ] || [ "$db" -ef "$real" ]; then   # -Sy must never see the real DB
        error "refusing to sync the real pacman database"
        return 1
    fi

    # --refresh: start from nothing, so the sync databases are downloaded in full.
    if [ "$refresh" = true ] || [ -L "$db" ]; then
        rm -rf -- "$db"
    fi
    mkdir -p -m 700 -- "$db/sync" || { error "cannot create $db"; return 1; }
    [ -L "$db/local" ] || rm -rf -- "$db/local"
    ln -sfn -- "$real/local" "$db/local" || { error "cannot link the local database"; return 1; }
    if [ "$refresh" != true ] && [ -d "$real/sync" ]; then
        # Start from the real sync databases (timestamps kept) so pacman only fetches what changed.
        for f in "$real"/sync/*.db "$real"/sync/*.db.sig; do
            [ -f "$f" ] && cp -pu -- "$f" "$db/sync/" 2>/dev/null
        done
    fi

    # Same as checkupdates: as the normal user, under fakeroot, on the temp DB only.
    command -v fakeroot >/dev/null 2>&1 || { error "fakeroot is not installed (needed for the update check)"; return 1; }
    read -ra pm <<<"${PKG_PACMAN:-pacman}"
    logfile="$tmpd/sync.log"
    if ! LC_ALL=C fakeroot -- "${pm[@]}" --config "$conf" -Sy --disable-sandbox-filesystem \
            --dbpath "$db" --logfile /dev/null >"$logfile" 2>&1; then
        error "cannot fetch updates: $(grep . "$logfile" | tail -n 1)"
        return 1
    fi

    stripped="$tmpd/pacman.noignore.conf"
    pacman_conf_without_ignores "$conf" "$stripped" || return 1
    local normal="" all
    if [ "$system" = true ]; then
        all=$(_pkg_qu "$stripped" "$db") || return 1
    else
        normal=$(_pkg_qu "$conf" "$db") || return 1
        if cmp -s "$conf" "$stripped"; then
            all=$normal    # no Ignore lines: the second run would be identical
        else
            all=$(_pkg_qu "$stripped" "$db") || return 1
        fi
    fi

    # updates = everything the stripped config sees; held = not in the normal run.
    # count = updates that are NOT held; held_count = the held ones.
    jq -nc --arg normal "$normal" --arg all "$all" --argjson refreshed "$refresh" --argjson system "$system" '
        def parse: split("\n") | map(select(. != "") | [splits(" +")] | {name: .[0], old: .[1], new: .[3]});
        ($normal | parse | map(.name)) as $names
        | ($all | parse
           | map(. + {held: (if $system then false else (.name as $n | $names | any(. == $n) | not) end)})) as $updates
        | { updates: $updates,
            count: ($updates | map(select(.held | not)) | length),
            held_count: ($updates | map(select(.held)) | length),
            refreshed: $refreshed }'
}

# check_updates [--refresh] [--system]: JSON on stdout
#   {"updates":[{"name","old","new","held"}],"count":N,"held_count":M,"refreshed":bool}
# The way checkupdates works: no root, no change to the real pacman database. A
# private DB dir ${XDG_RUNTIME_DIR:-/tmp}/shroomery/pkg-check-db holds a symlink to the
# real `local` db and its own sync dbs; `-Sy` runs only against that dir (under fakeroot),
# then `-Qu`. A normal check reuses the dir; --refresh deletes it first (full re-download,
# the -Syyu equivalent). Held packages (IgnorePkg/IgnoreGroup) are listed in updates with
# held:true; `count` is the number of NOT held updates, `held_count` the held ones.
# --system evaluates against the config without those lines: nothing is held.
# A failing sync or -Qu exits 1 with a message on stderr and no JSON; it never reads as
# "no updates". Concurrent checks wait for each other (flock).
check_updates() {
    local refresh=false system=false arg base
    for arg in "$@"; do
        case "$arg" in
            --refresh) refresh=true ;;
            --system)  system=true ;;
            *) error "check: unknown option: $arg"; return 2 ;;
        esac
    done
    base="${XDG_RUNTIME_DIR:-/tmp}/shroomery"
    pkg_private_dir "$base" || return 1
    (
        flock -w 300 9 || { error "another update check is still running"; exit 1; }
        tmpd=$(mktemp -d "$base/run.XXXXXX") || { error "cannot create a temp dir in $base"; exit 1; }
        trap 'rm -rf -- "$tmpd"' EXIT
        _check_updates_run "$refresh" "$system" "$base" "$tmpd"
    ) 9>"$base/pkg-check.lock"
}

# --- fetch-missing: protected archives from the Arch Linux Archive ---------------

# missing_archives: "name version" lines of the installed protected packages that
# have no archive in the cache. Fails (prints nothing) when pacman fails, so a broken
# query never reads as "nothing missing".
missing_archives() {
    local list name version
    list=$(protected_installed) || return 1
    while read -r name version; do
        [ -n "$name" ] || continue
        archive_for "$name" "$version" >/dev/null || printf '%s %s\n' "$name" "$version"
    done <<<"$list"
}

# archive_url NAME VERSION ARCH: URL of the package in the Archive,
# <base>/<first letter>/<name>/<name>-<version>-<arch>.pkg.tar.zst, epoch colon as %3A.
# (The file saved in the cache keeps the literal colon, as pacman names it.)
archive_url() {
    local name=${1:?archive_url: NAME missing} version=${2:?archive_url: VERSION missing} arch=${3:?archive_url: ARCH missing}
    local base=${PKG_ARCHIVE_URL:-https://archive.archlinux.org/packages}
    printf '%s/%s/%s/%s-%s-%s.pkg.tar.zst\n' "${base%/}" "${name:0:1}" "$name" "$name" "${version//:/%3A}" "$arch"
}

# pkg_free_bytes DIR: bytes available to unprivileged writes on DIR's filesystem
# (the PKG_FREE_BYTES override wins). Fails when it cannot be measured.
pkg_free_bytes() {
    local blocks size
    if [ -n "${PKG_FREE_BYTES:-}" ]; then
        printf '%s\n' "$PKG_FREE_BYTES"
        return 0
    fi
    read -r blocks size < <(stat -f -c '%a %S' -- "$1" 2>/dev/null) || return 1
    case "$blocks$size" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' $((blocks * size))
}

# pkg_verify_signature SIGFILE PKGFILE: the default PKG_VERIFY. gpg checks the detached
# signature against the pacman keyring and the key must be trusted (fully or ultimately),
# the way pacman's default SigLevel treats packages. Reading the keyring's trust database
# needs root, so in practice this runs from the root re-exec (`fetch-missing` under pkexec).
pkg_verify_signature() {
    local sig=$1 pkg=$2 gpgdir status
    gpgdir=${PKG_GPG_DIR:-}
    if [ -z "$gpgdir" ] && command -v pacman-conf >/dev/null 2>&1; then
        gpgdir=$(pacman-conf --config "$(pkg_pacman_conf)" GPGDir 2>/dev/null)
    fi
    [ -n "$gpgdir" ] || gpgdir=/etc/pacman.d/gnupg
    [ -f "$sig" ] && [ -f "$pkg" ] || return 1
    command -v gpg >/dev/null 2>&1 || { error "gpg is not installed; cannot verify signatures"; return 1; }
    status=$(gpg --homedir "$gpgdir" --batch --no-tty --status-fd 1 --verify "$sig" "$pkg" 2>/dev/null) || return 1
    grep -q '^\[GNUPG:\] GOODSIG ' <<<"$status" \
        && grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$status" \
        && grep -Eq '^\[GNUPG:\] TRUST_(FULLY|ULTIMATE)' <<<"$status"
}

# _pkg_curl_proto: the protocols curl may use: https only, plus file when the Archive
# base is a file:// URL (tests). The same list applies to the redirects' --proto-redir (https).
_pkg_curl_proto() {
    case "${PKG_ARCHIVE_URL:-}" in
        file://*) printf '%s\n' '=https,file' ;;
        *) printf '%s\n' '=https' ;;
    esac
}

# _pkg_curl ARG...: curl for the Archive. -q first: no ~/.curlrc (root's included).
_pkg_curl() {
    curl -q --fail --location --silent --show-error --proto "$(_pkg_curl_proto)" --proto-redir '=https' \
        --connect-timeout 15 --max-time 1800 "$@" </dev/null
}

# _fetch_size URL: Content-Length of URL in bytes (HEAD, redirects followed). Fails when
# the request fails or the server gives no length.
_fetch_size() {
    local headers len
    headers=$(_pkg_curl --max-time 60 -I "$1") || return 1
    len=$(tr -d '\r' <<<"$headers" | awk 'tolower($1) == "content-length:" { v = $2 } END { print v }')
    case $len in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' "$len"
}

# _pkginfo_matches PKGFILE NAME VERSION: .PKGINFO pkgname and pkgver (epoch included,
# e.g. `pkgver = 2:2.16-1`) equal NAME and VERSION.
_pkginfo_matches() {
    local info n v
    info=$(bsdtar -xOf "$1" .PKGINFO 2>/dev/null) || return 1
    n=$(sed -n 's/^pkgname = //p' <<<"$info")
    v=$(sed -n 's/^pkgver = //p' <<<"$info")
    [ "$n" = "$2" ] && [ "$v" = "$3" ]
}

FETCH_PARTS=()
FETCH_OLD_INT=""
FETCH_OLD_TERM=""

_fetch_clean_parts() {
    [ "${#FETCH_PARTS[@]}" = 0 ] || rm -f -- "${FETCH_PARTS[@]}"
    FETCH_PARTS=()
}

# _fetch_signal SIG NUM: remove the part files, give the caller's traps back, re-raise.
_fetch_signal() {
    _fetch_clean_parts
    trap - INT TERM
    [ -z "$FETCH_OLD_INT" ] || eval "$FETCH_OLD_INT"
    [ -z "$FETCH_OLD_TERM" ] || eval "$FETCH_OLD_TERM"
    kill -s "$1" $$
    exit $((128 + $2))   # the caller's handler returned: the fetch is still aborted
}

# _fetch_one NAME VERSION ARCH: download, verify and install one archive into the cache.
# Files go to <final>.part / <final>.sig.part and are renamed into place only after the
# signature and .PKGINFO checks pass (sig first, so a package in the cache always has its
# sig). On any failure the part files are removed, the reason is printed on stderr
# (naming the package) and the status is 1.
_fetch_one() {
    local name=$1 version=$2 arch=$3 cache dest url why out
    local -a verify
    cache=$(pkg_cache_dir)
    dest="$cache/$name-$version-$arch.pkg.tar.zst"
    url=$(archive_url "$name" "$version" "$arch")
    FETCH_PARTS=("$dest.part" "$dest.sig.part")
    rm -f -- "${FETCH_PARTS[@]}"
    why=""
    if ! out=$(_pkg_curl -o "$dest.part" "$url" 2>&1); then
        why="download failed: ${out:-$url}"
    elif ! out=$(_pkg_curl -o "$dest.sig.part" "$url.sig" 2>&1); then
        why="signature download failed: ${out:-$url.sig}"
    else
        read -ra verify <<<"${PKG_VERIFY:-pkg_verify_signature}"
        if ! out=$("${verify[@]}" "$dest.sig.part" "$dest.part" 2>&1 </dev/null); then
            why="signature verification failed${out:+: ${out%%$'\n'*}}"
        elif ! _pkginfo_matches "$dest.part" "$name" "$version"; then
            why="the package is not $name $version (.PKGINFO pkgname/pkgver differ, or it is not a package)"
        elif ! chmod 644 -- "$dest.part" "$dest.sig.part" \
                || ! mv -f -- "$dest.sig.part" "$dest.sig" \
                || ! mv -f -- "$dest.part" "$dest"; then
            rm -f -- "$dest.sig"
            why="cannot move the files into $cache"
        fi
    fi
    _fetch_clean_parts
    [ -z "$why" ] && return 0
    error "$name $version: $why"
    return 1
}

# fetch_missing [--yes]: download the archives missing_archives lists from the Arch Linux
# Archive into the cache. Order: sizes (HEAD) of everything, free space check (sum + 10 %),
# the list and a y/N question on stdin (unless --yes), then one package at a time. A package
# whose HEAD or download fails, or whose signature or .PKGINFO does not check out, is
# reported by name and version, leaves nothing in the cache, and the others go on; the
# exit status is then 1. Not enough space refuses before any download (status 1).
# Declining downloads nothing and succeeds. Nothing missing succeeds. Needs write access
# to the cache (root, via the re-exec added with `apply`).
fetch_missing() {
    local yes=false arg line name version arch url size total=0 need free i tool
    local -a lines plan_n=() plan_v=() plan_a=() plan_s=() failed=()
    for arg in "$@"; do
        case "$arg" in
            --yes) yes=true ;;
            *) error "fetch-missing: unknown option: $arg"; return 2 ;;
        esac
    done
    for tool in curl bsdtar; do
        command -v "$tool" >/dev/null 2>&1 || { error "$tool is not installed (needed by fetch-missing)"; return 1; }
    done
    [ -d "$(pkg_cache_dir)" ] || { error "cache dir not found: $(pkg_cache_dir)"; return 1; }
    line=$(missing_archives) || return 1
    if [ -z "$line" ]; then
        echo "nothing missing: every protected package has an archive in the cache"
        return 0
    fi
    mapfile -t lines <<<"$line"

    # Plan: architecture and download size of every package. A package that fails here
    # counts as failed (reported, the others go on).
    for line in "${lines[@]}"; do
        read -r name version <<<"$line"
        if [[ ! $name =~ ^[A-Za-z0-9@_+][A-Za-z0-9@._+-]*$ || ! $version =~ ^[A-Za-z0-9][A-Za-z0-9._+:~-]*$ ]]; then
            error "$name $version: unsafe package name or version; not downloading it"
            failed+=("$name $version"); continue
        fi
        if ! arch=$(pkg_pacman -Qi "$name" </dev/null | awk '$1 == "Architecture" { print $3; exit }') \
                || [[ ! $arch =~ ^[A-Za-z0-9_]+$ ]]; then
            error "$name $version: cannot read the architecture of the installed package"
            failed+=("$name $version"); continue
        fi
        url=$(archive_url "$name" "$version" "$arch")
        if ! size=$(_fetch_size "$url"); then
            error "$name $version: not available in the Archive ($url)"
            failed+=("$name $version"); continue
        fi
        plan_n+=("$name"); plan_v+=("$version"); plan_a+=("$arch"); plan_s+=("$size")
        total=$((total + size))
    done
    if [ "${#plan_n[@]}" = 0 ]; then
        error "nothing can be downloaded"
        return 1
    fi

    need=$((total + (total + 9) / 10))
    if ! free=$(pkg_free_bytes "$(pkg_cache_dir)"); then
        error "cannot measure the free space in $(pkg_cache_dir); downloading nothing"
        return 1
    fi
    if [ "$free" -lt "$need" ]; then
        error "not enough free space in $(pkg_cache_dir): need $need bytes ($(numfmt --to=iec "$need")): downloads $total bytes plus 10%; available $free bytes ($(numfmt --to=iec "$free")). Downloading nothing."
        return 1
    fi

    echo "Archives to download from the Arch Linux Archive:"
    for i in "${!plan_n[@]}"; do
        printf '  %s %s  (%s)\n' "${plan_n[i]}" "${plan_v[i]}" "$(numfmt --to=iec --suffix=B "${plan_s[i]}")"
    done
    printf 'Total: %s\n' "$(numfmt --to=iec --suffix=B "$total")"
    if [ "$yes" != true ]; then
        printf 'Download %d archive(s)? [y/N] ' "${#plan_n[@]}" >&2
        if ! read -r arg; then arg=n; echo >&2; fi
        case "$arg" in
            y|Y|yes|YES|Yes) ;;
            *) echo "nothing downloaded"; return 0 ;;
        esac
    fi

    FETCH_OLD_INT=$(trap -p INT)
    FETCH_OLD_TERM=$(trap -p TERM)
    trap '_fetch_signal INT 2' INT
    trap '_fetch_signal TERM 15' TERM
    for i in "${!plan_n[@]}"; do
        echo "Fetching ${plan_n[i]} ${plan_v[i]} ..."
        _fetch_one "${plan_n[i]}" "${plan_v[i]}" "${plan_a[i]}" || failed+=("${plan_n[i]} ${plan_v[i]}")
    done
    trap - INT TERM
    [ -z "$FETCH_OLD_INT" ] || eval "$FETCH_OLD_INT"
    [ -z "$FETCH_OLD_TERM" ] || eval "$FETCH_OLD_TERM"

    if [ "${#failed[@]}" -gt 0 ]; then
        error "${#failed[@]} archive(s) not fetched:"
        printf '  %s\n' "${failed[@]}" >&2
        return 1
    fi
    echo "Fetched ${#plan_n[@]} archive(s) into $(pkg_cache_dir)"
}

# --- elevation, lock, log ------------------------------------------------------------
# Order in a root subcommand of pkg-update.sh:
#   elevate "$SELF" SUBCOMMAND ARGS...   (re-executes as root, or returns when root already)
#   acquire_lock                         (exit 3 when another update runs)
#   log_start NAME                       (LOG=<path> first, then everything goes to the log too)

# elevate SCRIPT [ARG...]: as the normal user, replace this process by
#   pkexec env WAYLAND_DISPLAY=… XDG_RUNTIME_DIR=… DISPLAY=… PKG_CACHE_KEEP=…
#       PKG_PROTECTED_PATTERNS=… PKG_USER_HOME=… SCRIPT ARG...
# (the same shape as LauncherApp's execRoot). SCRIPT is the absolute real path of the
# dispatcher, resolved by the caller; ARG... is the subcommand and its arguments. Only
# those variables reach the root process: pkexec clears the environment and `env` adds
# just the names listed, so no other PKG_* override (PKG_PACMAN, PKG_RECOVERY_DIR,
# PKG_NO_ELEVATE, PKG_ARCHIVE_URL, PKG_VERIFY, ...) can steer a root process. The two
# settings are resolved here, from the user's files or env, so root never reads $HOME.
# Returns 0 without doing anything when already root or when PKG_NO_ELEVATE is set.
# No pkexec: a message and exit 1, never an unprivileged run. After the re-exec stdin
# is whatever pkexec passes on; a prompt there (fetch-missing without --yes) only works
# from a terminal, so a UI always passes --yes.
# The elevated script lives in the user's own home, i.e. a user-writable file runs as
# root after the polkit prompt: inherent to the design, see shroomery/README.md.
elevate() {
    local script=${1:?elevate: SCRIPT missing} pkexec keep patterns
    shift
    ! _is_root || return 0
    [ -z "${PKG_NO_ELEVATE:-}" ] || return 0
    pkexec=${PKG_PKEXEC:-pkexec}
    if ! command -v "$pkexec" >/dev/null 2>&1; then
        error "pkexec not found (polkit is needed for root access); nothing was run"
        exit 1
    fi
    keep=$(settings_cache_keep)
    patterns=$(settings_protected)
    exec "$pkexec" env \
        "WAYLAND_DISPLAY=${WAYLAND_DISPLAY-}" "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR-}" "DISPLAY=${DISPLAY-}" \
        "PKG_CACHE_KEEP=$keep" "PKG_PROTECTED_PATTERNS=$patterns" "PKG_USER_HOME=${PKG_USER_HOME:-$HOME}" \
        "$script" "$@" || exit 1
}

# acquire_lock: take the update lock for the rest of the process. flock -n on
# <recovery dir>/lock, held on fd 200 until the process exits (the kernel drops it then,
# also on a kill). Held by someone else: message and exit 3. pacman's own database lock
# (PKG_PACMAN_DBLOCK, /var/lib/pacman/db.lck) present: message and exit 3.
# fd 200 is not close-on-exec in bash, so what runs long must not inherit it:
# pkg_pacman and log_start's tee close it (`200>&-`); do the same for any other
# command that may leave a background process behind.
LOCK_HELD=""
acquire_lock() {
    local dir lock
    [ -z "$LOCK_HELD" ] || return 0
    command -v flock >/dev/null 2>&1 || { error "flock is not installed"; exit 1; }
    dir=$(pkg_recovery_dir); lock="$dir/lock"
    if [ ! -d "$dir" ]; then
        (umask 022; mkdir -p -- "$dir") || { error "cannot create $dir"; exit 1; }
    fi
    { exec 200>>"$lock"; } 2>/dev/null || { error "cannot open the lock file $lock"; exit 1; }
    if ! flock -n 200; then
        error "another update operation is already running (lock: $lock)"
        exit 3
    fi
    LOCK_HELD=1
    if [ -e "$(pkg_dblock)" ]; then
        error "pacman is running or crashed: $(pkg_dblock) exists"
        exit 3
    fi
}

# log_start NAME: from now on stdout and stderr also go to <recovery dir>/logs/<UTC time>-NAME.log
# (logs/ 755, file 644; NAME is reduced to A-Za-z0-9._-). The first line on the original
# stdout is `LOG=<path>` (it is not in the log). stdout and stderr each go through their own
# `tee -a` (process substitution) that writes the log and passes the stream on to where it
# went before, so they stay separate for the caller. The tees run asynchronously, so the log
# is only complete once they have read everything: log_finish (run by an EXIT trap that
# log_start installs) points both streams at /dev/null, which makes the tees see EOF, then waits
# for them (at most 10 s, in case a background child still holds the pipe). The exit status
# is kept. A caller's existing EXIT trap runs first and is logged; set EXIT traps before
# log_start, and call log_finish yourself before an `exit` inside such a trap.
LOG_FILE=""
LOG_PIDS=()
LOG_OLD_EXIT=""
log_start() {
    local name=${1:?log_start: NAME missing} safe dir f stamp old n=0
    [ -z "$LOG_FILE" ] || { error "log_start was already called"; return 1; }
    safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
    dir="$(pkg_recovery_dir)/logs"
    if [ ! -d "$dir" ]; then
        (umask 022; mkdir -p -- "$dir") && chmod 755 -- "$dir" || { error "cannot create $dir"; return 1; }
    fi
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    f="$dir/$stamp-$safe.log"
    while ! (set -C; : > "$f") 2>/dev/null; do   # never reuse a log
        n=$((n + 1))
        [ "$n" -le 100 ] || { error "cannot create a log file in $dir"; return 1; }
        f="$dir/$stamp-$safe-$n.log"
    done
    chmod 644 -- "$f" || { error "cannot set the mode of $f"; return 1; }

    old=$(trap -p EXIT)
    LOG_OLD_EXIT=""
    if [ -n "$old" ]; then eval "set -- $old"; LOG_OLD_EXIT=${3-}; fi
    trap '_log_exit' EXIT

    printf 'LOG=%s\n' "$f"
    LOG_FILE=$f
    exec > >(tee --output-error=warn-nopipe -a -- "$f" 200>&-)
    LOG_PIDS=($!)
    exec 2> >(tee --output-error=warn-nopipe -a -- "$f" >&2 200>&-)
    LOG_PIDS+=($!)
}

# log_finish: flush and close the log (see log_start). Safe to call more than once.
log_finish() {
    local p i
    [ -n "$LOG_FILE" ] || return 0
    exec >/dev/null 2>&1
    for p in "${LOG_PIDS[@]}"; do
        for ((i = 0; i < 200; i++)); do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.05
        done
    done
    LOG_FILE=""; LOG_PIDS=()
}

_log_exit() {
    local rc=$?
    if [ -n "$LOG_OLD_EXIT" ]; then
        (exit "$rc")   # the caller's trap sees the real exit status in $?
        eval "$LOG_OLD_EXIT"
    fi
    log_finish
}

# --- apply / discard: the update transaction ------------------------------------------
# apply: checkpoint (when known-good does not describe the installed protected set), update,
# pending record. pkg_apply is a library function: the dispatcher has taken the lock and
# started the log (`elevate`, `acquire_lock`, `log_start apply`); never call the dispatcher
# from here (the lock would deadlock with exit 3).
#
# Recovery-dir changes, in order, and what an interruption leaves:
#   1. checkpoint_build into known-good (atomic; the old one stays until the new one is complete), recorded as
#      source "checkpoint", not verified. Skipped when known-good matches, when a pending record is kept
#      (--force), and when pending.discarded/ exists (an update was discarded since the last promote, so the
#      installed state is unverified): known-good is never rewritten from such a state.
#   1b. recovery.sh installed into the recovery dir (warns only), so it exists before pacman runs
#   2. pending/manifest.json state "running" (written before pacman is started, atomically)
#   3. pacman -Syuw, pacman -Syu
#   4. pending/manifest.json "awaiting-verification" or "failed" (atomically)
# Signals (INT/TERM/HUP to apply), by phase. pacman catches INT and HUP (a soft stop: it finishes
# the current package and releases db.lck) but NOT TERM (it dies on the spot, leaving a half-extracted
# package and a stale db.lck), so apply never sends TERM to pacman and never interrupts the -Syu transaction:
#   - before pacman starts: the record (if written) becomes "failed", cleanup, re-raise;
#   - during -Syuw (download only, nothing installed yet): INT is forwarded to pacman for any of the
#     three signals, pacman is waited for, the record becomes "failed", cleanup, re-raise;
#   - during -Syu: the signal is only remembered. apply keeps waiting for pacman, writes the final record
#     with the REAL outcome, skips paccache and the refresh, cleans up, restores the caller's traps and
#     re-raises the remembered signal. apply itself never interrupts pacman, but a Ctrl-C or a hang-up in
#     the terminal reaches pacman directly through the process group: pacman soft-stops part way (a
#     partial upgrade, its hooks not run; the record says failed). So at a terminal apply prints, just
#     before -Syu, not to press Ctrl-C or close the terminal; the Settings UI runs it without one;
#   - after the final record: cleanup and re-raise.
# SIGPIPE is ignored from the first trap on (the log's tee dies on a terminal close), so a handler
# or a message can never kill apply before the record is written; the record is written before
# anything is printed. Before step 2 nothing but known-good (untouched, or replaced by
# checkpoint_build) exists. known-good is never touched after step 1; a superseded one is kept as
# known-good.prev.
#   Not caught: SIGKILL / power loss while pacman runs leave the "running" record, which gates the
#   next apply like any other pending record until it is discarded or promoted.
#
# Environment (tests, besides the PKG_ ones above): PKG_PACCACHE (default paccache), PKG_QS
# (default qs; skipped silently when not on PATH), PKG_QS_TIMEOUT (seconds, default 5),
# PKG_SETPRIV (default setpriv: runs the refresh as the invoking user when apply is root).

APPLY_MIN_FREE_BYTES=$((64 * 1024 * 1024))   # margin on the recovery filesystem (hardlinks cost ~nothing)
APPLY_BEFORE=""      # "name version" lines before the update
APPLY_STARTED=""
APPLY_MODE=normal
APPLY_REPLACED=""    # compact JSON of the pending record that --force replaced
APPLY_PENDING=""     # <recovery>/pending
APPLY_CREATED=0      # pending/ was created by this run
APPLY_WRITTEN=0      # a complete pending/manifest.json of this run exists
APPLY_FINAL=0        # ... and it is the final one
APPLY_CHILD=""       # pid of the running pacman
APPLY_TMPD=""        # temp dir of the stripped pacman config (--system)
APPLY_TRAPS=0
APPLY_PHASE=""       # "" (before pacman), download, install, done
APPLY_SIG=""; APPLY_SIGNUM=0   # a signal remembered during -Syu, re-raised at the end
APPLY_OLD_INT=""; APPLY_OLD_TERM=""; APPLY_OLD_HUP=""; APPLY_OLD_PIPE=""

# pkg_pacman_bg ARG...: pkg_pacman as a background job (the pid is in $!). Run as a plain
# simple command so $! is pacman itself, which can then be signalled and waited for. Keeps
# stdin (an async job would get /dev/null) so pacman can ask questions at a terminal.
pkg_pacman_bg() { LC_ALL=C ${PKG_PACMAN:-pacman} "$@" <&0 200>&- & }

# _apply_pending_json STATE PACMAN_EXIT FINISHED AFTER ERROR: the pending record on stdout.
# packages: every name whose version differs between APPLY_BEFORE and AFTER, sorted by name,
# as {name, from, to}; from is null for an added and to for a removed package.
_apply_pending_json() {
    jq -n --arg started "$APPLY_STARTED" --arg finished "$3" --arg mode "$APPLY_MODE" \
        --arg pexit "$2" --arg state "$1" --arg before "$APPLY_BEFORE" --arg after "$4" \
        --arg error "$5" --argjson replaced "${APPLY_REPLACED:-null}" '
        def versions: split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: .[1]}) | from_entries;
        ($before | versions) as $b | ($after | versions) as $a
        | { started: $started,
            finished: (if $finished == "" then null else $finished end),
            mode: $mode,
            pacman_exit: (if $pexit == "" then null else ($pexit | tonumber) end),
            state: $state,
            packages: ([($b | keys[]), ($a | keys[])] | unique
                       | map(. as $n | select($b[$n] != $a[$n]) | {name: $n, from: $b[$n], to: $a[$n]})) }
          + (if $error == "" then {} else {error: $error} end)
          + (if $replaced == null then {} else {replaced: $replaced} end)'
}

# _apply_write_pending JSON: pending/manifest.json = JSON, written to a temp file and renamed.
_apply_write_pending() {
    printf '%s\n' "$1" | ( umask 022; write_atomic "$APPLY_PENDING/manifest.json" )
}

# _apply_finish STATE PACMAN_EXIT ERROR: write the final pending record from the installed
# set now. A -Q that fails afterwards makes the state "failed" with an error (never a record
# built on nothing). If the record cannot be built, a minimal "failed" one is written without jq.
_apply_finish() {
    local state=$1 pexit=$2 err=${3:-} after finished json
    case $pexit in ''|*[!0-9]*) pexit=1 ;; esac
    finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if ! after=$(pkg_installed); then
        state=failed
        err="${err:+$err; }could not read the installed packages after the update"
        after=$APPLY_BEFORE
    fi
    if json=$(_apply_pending_json "$state" "$pexit" "$finished" "$after" "$err") && [ -n "$json" ] \
            && _apply_write_pending "$json"; then
        APPLY_WRITTEN=1; APPLY_FINAL=1
        return 0
    fi
    error "could not write the pending record; writing a minimal one"
    if printf '{"started":"%s","finished":"%s","mode":"%s","pacman_exit":%s,"state":"failed","error":"the full pending record could not be written"}\n' \
            "$APPLY_STARTED" "$finished" "$APPLY_MODE" "$pexit" | ( umask 022; write_atomic "$APPLY_PENDING/manifest.json" ); then
        APPLY_WRITTEN=1; APPLY_FINAL=1
    fi
    return 1
}

# _apply_cleanup: the temp config, a temp record, an empty pending/ this run created. Idempotent.
_apply_cleanup() {
    [ -z "$APPLY_TMPD" ] || rm -rf -- "$APPLY_TMPD"
    APPLY_TMPD=""
    [ -z "$APPLY_PENDING" ] || rm -f -- "$APPLY_PENDING/manifest.json.tmp.$$"
    if [ "$APPLY_CREATED" = 1 ] && [ "$APPLY_WRITTEN" != 1 ] && [ -n "$APPLY_PENDING" ]; then
        rmdir -- "$APPLY_PENDING" 2>/dev/null
    fi
    return 0
}

_apply_traps_on() {
    APPLY_OLD_INT=$(trap -p INT); APPLY_OLD_TERM=$(trap -p TERM); APPLY_OLD_HUP=$(trap -p HUP)
    APPLY_OLD_PIPE=$(trap -p PIPE)
    trap '_apply_signal INT 2' INT
    trap '_apply_signal TERM 15' TERM
    trap '_apply_signal HUP 1' HUP
    trap '' PIPE
    APPLY_TRAPS=1
}

_apply_traps_off() {
    [ "$APPLY_TRAPS" = 1 ] || return 0
    APPLY_TRAPS=0
    trap - INT TERM HUP PIPE
    [ -z "$APPLY_OLD_PIPE" ] || eval "$APPLY_OLD_PIPE"
    [ -z "$APPLY_OLD_INT" ] || eval "$APPLY_OLD_INT"
    [ -z "$APPLY_OLD_TERM" ] || eval "$APPLY_OLD_TERM"
    [ -z "$APPLY_OLD_HUP" ] || eval "$APPLY_OLD_HUP"
}

# _apply_signal SIG NUM: see "Signals" above. Never sends TERM to pacman.
_apply_signal() {
    local sig=$1 num=$2 rc=$((128 + $2)) crc
    if [ "$APPLY_PHASE" = install ]; then
        [ -n "$APPLY_SIG" ] || { APPLY_SIG=$sig; APPLY_SIGNUM=$num; }
        return 0
    fi
    trap '' INT TERM HUP PIPE
    if [ -n "$APPLY_CHILD" ]; then   # -Syuw: pacman's soft stop, whichever signal apply got
        kill -s INT "$APPLY_CHILD" 2>/dev/null
        wait "$APPLY_CHILD" 2>/dev/null; crc=$?
        [ "$crc" = 127 ] || rc=$crc
        APPLY_CHILD=""
    fi
    if [ "$APPLY_WRITTEN" = 1 ] && [ "$APPLY_FINAL" != 1 ]; then
        _apply_finish failed "$rc" "interrupted by $sig" 2>/dev/null || true   # the record first, then talk
        error "interrupted ($sig): the update was cut short; recorded as failed" 2>/dev/null || true
    fi
    _apply_cleanup
    _apply_traps_off
    kill -s "$sig" "$BASHPID"
    exit $((128 + num))   # the caller's handler returned (or ignores it): this run is still aborted
}

# _apply_reraise: after a signal was remembered during -Syu: cleanup, give the caller's traps back, re-raise.
_apply_reraise() {
    local sig=$APPLY_SIG num=$APPLY_SIGNUM
    _apply_cleanup
    _apply_traps_off
    kill -s "$sig" "$BASHPID"
    exit $((128 + num))
}

# _apply_pacman ARG...: run pacman as a background job and wait for it, so a trapped signal is
# handled at once (a foreground child would delay the trap until it ends). A handler that
# returns (the -Syu phase) interrupts `wait`: wait again until pacman is gone, keep its real status.
_apply_pacman() {
    local rc r2
    pkg_pacman_bg "$@"
    APPLY_CHILD=$!
    while :; do
        wait "$APPLY_CHILD"; rc=$?
        [ "$rc" -ge 128 ] || break   # below 128 is pacman's own status (127: no such child any more)
        if ! kill -0 "$APPLY_CHILD" 2>/dev/null; then
            wait "$APPLY_CHILD" 2>/dev/null; r2=$?   # the status of a child that ended while a trap ran
            [ "$r2" = 127 ] || rc=$r2
            break
        fi
    done
    APPLY_CHILD=""
    return "$rc"
}

# _apply_refresh_statusbar: best effort, never fails. Skipped silently without qs on PATH.
# The user's quickshell is reachable only as the user (pkexec sets HOME=/root): as root the refresh
# runs through `setpriv --reuid=$PKEXEC_UID --regid=<gid> --init-groups env HOME=$PKG_USER_HOME ...`
# (PKG_SETPRIV overrides the setpriv command); root without PKEXEC_UID, PKG_USER_HOME or setpriv skips
# it: qs is never run as root. Not root (tests, PKG_NO_ELEVATE): run directly.
_apply_refresh_statusbar() {
    local -a qs runas=()
    local t=${PKG_QS_TIMEOUT:-5} uid gid sp
    case $t in ''|*[!0-9]*) t=5 ;; esac
    read -ra qs <<<"${PKG_QS:-qs}"
    [ "${#qs[@]}" -gt 0 ] && command -v "${qs[0]}" >/dev/null 2>&1 || return 0
    if _is_root; then
        uid=${PKEXEC_UID:-}
        [[ $uid =~ ^[0-9]+$ ]] && [ "$uid" != 0 ] && [ -n "${PKG_USER_HOME:-}" ] || return 0
        gid=$(id -g "$uid" 2>/dev/null) || return 0
        read -ra sp <<<"${PKG_SETPRIV:-setpriv}"
        command -v "${sp[0]}" >/dev/null 2>&1 || return 0
        runas=("${sp[@]}" --reuid="$uid" --regid="$gid" --init-groups env "HOME=$PKG_USER_HOME")
    fi
    timeout -k 1 "$t" "${runas[@]}" "${qs[@]}" ipc call updates refresh </dev/null >/dev/null 2>&1 200>&-
    return 0
}

# _apply_warn_superseded KG: loud warning before a mismatching known-good is replaced: its
# date and the protected packages whose versions differ from the installed set.
_apply_warn_superseded() {
    local rec created diff
    rec=$(pkg_record known-good)
    created=$(jq -r '.created // "unknown"' <<<"$rec" 2>/dev/null)
    diff=$(awk 'NR == FNR { o[$1] = $2; next }
                { n[$1] = $2 }
                END { for (k in o) if (!(k in n)) print "  " k " " o[k] " -> (not installed)";
                                    else if (o[k] != n[k]) print "  " k " " o[k] " -> " n[k];
                      for (k in n) if (!(k in o)) print "  " k " (not in the old record) -> " n[k] }' \
        <(jq -r '.packages[]? | "\(.name) \(.version)"' <<<"$rec" 2>/dev/null) <(protected_installed) | LC_ALL=C sort)
    warn "known-good (created ${created:-unknown}) does not match the installed protected packages, so it is replaced by the installed state (it may have been changed outside this tool). The old one is kept as known-good.prev. Differences (known-good -> installed):"
    [ -z "$diff" ] || printf '%s\n' "$diff" >&2
}

# _apply_partly_changed N: the alarm for a failed update that had already changed N packages.
_apply_partly_changed() {
    error "packages were partly changed ($1 package(s) at new versions) — do not reboot; restore now (sudo $(pkg_recovery_dir)/recovery.sh) or finish the update ('pkg-update.sh discard', then 'pkg-update.sh apply'; known-good is kept)"
}

# _apply_newest GLOB...: the newest existing path matching the glob (by mtime), or nothing.
_apply_newest() { ls -dt -- "$@" 2>/dev/null | head -n 1; }

# _apply_dir_complete DIR: DIR is a whole known-good copy (a manifest that lists packages, every
# listed archive present).
_apply_dir_complete() {
    local a
    [ -d "$1/archives" ] && jq -e '(.packages | length) > 0' "$1/manifest.json" >/dev/null 2>&1 || return 1
    while IFS= read -r a; do
        [ -n "$a" ] && [ -e "$1/archives/$a" ] || return 1
    done < <(jq -r '.packages[].archive' "$1/manifest.json" 2>/dev/null)
}

# _apply_swap_prev NEW: NEW (a complete copy of the superseded known-good) becomes known-good.prev; the
# old .prev is moved aside first and removed last. `mv -T`: a rename that cannot happen fails, it never
# nests NEW inside the old .prev. A failure puts the old .prev back.
_apply_swap_prev() {
    local new=$1 prev old
    prev="$(pkg_recovery_dir)/known-good.prev"; old="$prev.old.$$"
    rm -rf -- "$old"
    if [ -e "$prev" ] || [ -L "$prev" ]; then
        mv -T -- "$prev" "$old" || { warn "could not move the old known-good.prev aside"; return 1; }
    fi
    if ! mv -T -- "$new" "$prev"; then
        if [ -e "$old" ]; then mv -T -- "$old" "$prev"; fi
        warn "could not store known-good.prev"
        return 1
    fi
    if ! _pkg_syncfs "$prev"; then   # barrier: the new .prev is on disk before the old one is deleted
        warn "could not commit known-good.prev to disk; the older one is kept as $old"
        return 1
    fi
    rm -rf -- "$old"
}

# _apply_sweep: at the start of apply (lock held). Rollback state is RECOVERED before debris is
# deleted. A run killed in the middle of replacing known-good (checkpoint_build) leaves
# known-good.old.PID and no known-good: it is put back. A kill during the known-good.prev swap leaves
# known-good.prev.new.PID (the superseded known-good, a complete copy that differs from the new
# known-good) and/or known-good.prev.old.PID: the copy becomes .prev, else the old .prev comes back.
# Then the remaining temp copies (also pkg_promote's known-good.new.*, *.discard.*, recovery.sh.tmp.*), tmp/apply.* dirs and write probes go. A copy whose restore failed
# (known-good.prev.new.*) and any .prev.old.* with a manifest while .prev is missing are KEPT, with a warning.
_apply_sweep() {
    local rec kg newest n cand d keep_new="" kept=""
    rec=$(pkg_recovery_dir); kg="$rec/known-good"
    if [ ! -e "$kg" ] && [ ! -L "$kg" ]; then
        newest=$(_apply_newest "$kg".old.*)
        if [ -n "$newest" ] && [ -s "$newest/manifest.json" ] && mv -T -- "$newest" "$kg"; then
            warn "recovered known-good from ${newest##*/}: an earlier run was cut off while replacing it"
        fi
    fi
    if [ -e "$kg" ]; then
        cand=$(_apply_newest "$kg".prev.new.*)
        if [ -n "$cand" ] && _apply_dir_complete "$cand" && ! cmp -s "$cand/manifest.json" "$kg/manifest.json"; then
            if _apply_swap_prev "$cand"; then
                warn "recovered known-good.prev from ${cand##*/}: an earlier run was cut off after replacing known-good"
            else
                keep_new=$cand   # a failed restore keeps its source
            fi
        fi
    fi
    if [ ! -e "$kg.prev" ] && [ ! -L "$kg.prev" ]; then
        newest=$(_apply_newest "$kg".prev.old.*)
        if [ -n "$newest" ] && [ -s "$newest/manifest.json" ] && mv -T -- "$newest" "$kg.prev"; then
            warn "recovered known-good.prev from ${newest##*/}: an earlier run was cut off while replacing it"
        fi
    fi
    if [ -d "$rec/tmp" ]; then
        find "$rec/tmp" -mindepth 1 -maxdepth 1 -name 'apply.*' -exec rm -rf -- {} + 2>/dev/null
    fi
    find "$rec" -mindepth 1 -maxdepth 1 \( -name 'known-good.tmp.*' -o -name '.write-test.*' \
        -o -name 'known-good.new.*' -o -name 'known-good.discard.*' -o -name 'known-good.prev.discard.*' -o -name 'pending.discard.*' \
        -o -name 'recovery.sh.tmp.*' \) -exec rm -rf -- {} + 2>/dev/null   # (known-good.new.*, .discard.*, recovery.sh.tmp.*: pkg_promote's)
    for d in "$kg".prev.new.*; do   # debris, except the copy whose restore just failed
        [ -e "$d" ] || continue
        if [ "$d" = "$keep_new" ]; then kept+=" $d"; else rm -rf -- "$d"; fi
    done
    for d in "$kg".prev.old.*; do   # debris only once known-good.prev exists again
        [ -e "$d" ] || continue
        if [ -e "$kg.prev" ] || [ -L "$kg.prev" ] || [ ! -s "$d/manifest.json" ]; then rm -rf -- "$d"; else kept+=" $d"; fi
    done
    [ -z "$kept" ] || warn "could not restore known-good.prev; kept for the next run (they hold the superseded known-good):$kept"
    if [ -e "$kg" ]; then   # only now that known-good is there are its swap leftovers debris
        find "$rec" -mindepth 1 -maxdepth 1 -name 'known-good.old.*' -exec rm -rf -- {} + 2>/dev/null
    fi
    return 0
}

# _apply_run SYSTEM FORCE YES: spec "Update flow" steps 2-8 (step 1, the lock, is the caller's).
# Returns 0, 1 (failure, message on stderr) or 4 (an unpromoted pending record).
_apply_run() {
    local system=$1 force=$2 yes=$3
    local rec cache pending kg probe free have_pending=false state started changed keep conf missing json rc prevnew after saved_int saved_term saved_hup
    local -a pargs yes_args=() pc
    rec=$(pkg_recovery_dir); cache=$(pkg_cache_dir); pending="$rec/pending"; kg="$rec/known-good"
    [ "$yes" != true ] || yes_args=(--yes)

    # Step 2: storage writable, one filesystem with the cache, some free space. Nothing is changed yet.
    command -v jq >/dev/null 2>&1 || { error "jq is not installed"; return 1; }
    (umask 022; mkdir -p -- "$rec") || { error "cannot create the recovery storage $rec"; return 1; }
    if ! probe=$(mktemp "$rec/.write-test.XXXXXX" 2>/dev/null); then
        error "the recovery storage $rec is not writable"
        return 1
    fi
    rm -f -- "$probe"
    [ -d "$cache" ] || { error "cache dir not found: $cache"; return 1; }
    if ! same_fs "$cache" "$rec"; then
        error "$rec and $cache are on different filesystems; hardlinks need one filesystem. Nothing was changed."
        return 1
    fi
    if ! free=$(pkg_free_bytes "$rec") || [[ ! $free =~ ^[0-9]+$ ]]; then
        error "cannot measure the free space in $rec; nothing was changed"
        return 1
    fi
    if [ "$free" -lt "$APPLY_MIN_FREE_BYTES" ]; then
        error "not enough free space in $rec: $free bytes available, at least $APPLY_MIN_FREE_BYTES needed. Nothing was changed."
        return 1
    fi

    _apply_sweep   # recover rollback state a hard kill cut off, then remove the debris (we hold the lock)

    # Step 3: an unpromoted pending record is a hard stop; --force overrides only that.
    if [ -e "$pending" ] || [ -L "$pending" ]; then
        state=$(pkg_record pending | jq -r '.state // "unknown"' 2>/dev/null)
        started=$(pkg_record pending | jq -r '.started // "unknown"' 2>/dev/null)
        changed=$(pkg_record pending | jq -r 'if (.packages | type) == "array" then (.packages | length) else 0 end' 2>/dev/null)
        if [ "$force" != true ]; then
            error "an update is pending and has not been promoted (state: ${state:-unknown}, started: ${started:-unknown}). Nothing was changed."
            if [ "$state" = failed ] && [[ $changed =~ ^[0-9]+$ ]] && [ "$changed" -gt 0 ]; then
                _apply_partly_changed "$changed"
            fi
            error "Reboot and verify it, then promote it (pkg-update.sh verify, pkg-update.sh promote), or drop the record with 'pkg-update.sh discard' (the update stays installed; known-good is untouched, and the next apply does not replace it). '--force' overrides this stop; it never rewrites known-good."
            return 4
        fi
        have_pending=true
        warn "--force: continuing with an unpromoted pending update (state: ${state:-unknown}); known-good will not be rewritten"
    fi

    APPLY_BEFORE=$(pkg_installed) || return 1
    [ -n "$APPLY_BEFORE" ] || { error "pacman reports no installed packages; refusing to continue"; return 1; }

    # Step 4: known-good must describe the installed protected set.
    if [ "$have_pending" = true ]; then
        if [ ! -s "$kg/manifest.json" ]; then
            error "an update is pending and there is no known-good to roll back to; run 'pkg-update.sh discard' first so that apply can take a checkpoint of the current state. Nothing was changed."
            return 1
        fi
        echo "known-good left as it is (a pending update exists)"
    elif known_good_matches; then
        echo "known-good describes the installed protected packages; no checkpoint needed"
    elif [ -s "$kg/manifest.json" ] && { [ -e "$rec/pending.discarded" ] || [ -L "$rec/pending.discarded" ]; }; then
        # A discarded update (pending.discarded/) made the installed state: it was never verified, maybe half applied.
        warn "known-good does not match the installed protected packages, but an update was discarded since the last promote, so the installed state is not verified: known-good is not rewritten (the update goes ahead against it; recovery.sh restores it)"
    else
        echo "Taking a checkpoint of the installed protected packages ..."
        missing=$(missing_archives) || return 1
        if [ -n "$missing" ]; then
            echo "Archives missing from the cache; fetching them from the Arch Linux Archive ..."
            fetch_missing "${yes_args[@]}" || { error "the missing archives could not be fetched; nothing was changed"; return 1; }
            missing=$(missing_archives) || return 1
            if [ -n "$missing" ]; then
                error "no checkpoint without these archives; nothing was changed:"
                sed 's/^/  /' <<<"$missing" >&2
                return 1
            fi
        fi
        prevnew=""
        if [ -e "$kg" ] || [ -L "$kg" ]; then   # keep the superseded one: hardlinks, no space
            _apply_warn_superseded
            prevnew="$kg.prev.new.$$"
            rm -rf -- "$prevnew"
            cp -al -- "$kg" "$prevnew" || { rm -rf -- "$prevnew"; error "cannot keep the old known-good as known-good.prev; nothing was changed"; return 1; }
        fi
        if ! checkpoint_build "$kg" checkpoint; then   # on failure the old known-good is still in place
            [ -z "$prevnew" ] || rm -rf -- "$prevnew"
            error "the checkpoint could not be built; nothing was changed"
            return 1
        fi
        if [ -n "$prevnew" ]; then   # INT/TERM/HUP ignored for the two renames; a cut-off is recovered by the next sweep
            saved_int=$(trap -p INT); saved_term=$(trap -p TERM); saved_hup=$(trap -p HUP)
            trap '' INT TERM HUP
            _apply_swap_prev "$prevnew"
            trap - INT TERM HUP
            [ -z "$saved_int" ] || eval "$saved_int"
            [ -z "$saved_term" ] || eval "$saved_term"
            [ -z "$saved_hup" ] || eval "$saved_hup"
        fi
        echo "known-good now describes the installed state"
    fi
    _pkg_install_recovery "$rec" "the update goes ahead"   # the emergency tool exists before pacman runs (warns only)

    # From here on a signal ends in a "failed" pending record.
    keep=$(settings_cache_keep)
    _apply_traps_on
    APPLY_MODE=normal; [ "$system" != true ] || APPLY_MODE=system
    APPLY_PENDING=$pending
    APPLY_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    conf=$(pkg_pacman_conf)
    if [ "$system" = true ]; then
        # root's own place: never $XDG_RUNTIME_DIR or anything under the user's home
        (umask 022; mkdir -p -- "$rec/tmp") && APPLY_TMPD=$(mktemp -d "$rec/tmp/apply.XXXXXX") \
            || { error "cannot create a temp dir in $rec/tmp"; return 1; }
        pacman_conf_without_ignores "$conf" "$APPLY_TMPD/pacman.conf" || return 1
        conf=$APPLY_TMPD/pacman.conf
    fi
    if [ "$have_pending" = true ]; then
        APPLY_REPLACED=$(pkg_record pending | jq -c '{started, finished, mode, state, packages}' 2>/dev/null) || APPLY_REPLACED=""
        [ -d "$pending" ] && [ ! -L "$pending" ] || rm -f -- "$pending"   # a link or file: replace it, never write through it
    fi
    if [ ! -d "$pending" ]; then
        (umask 022; mkdir -- "$pending") || { error "cannot create $pending"; return 1; }
        APPLY_CREATED=1
    fi
    if ! json=$(_apply_pending_json running "" "" "$APPLY_BEFORE" "") || [ -z "$json" ] \
            || ! _apply_write_pending "$json"; then
        error "cannot write the pending record; nothing was updated"
        return 1
    fi
    APPLY_WRITTEN=1

    # Steps 5-6: download first, then install.
    pargs=(--config "$conf")
    if [ "$yes" = true ] || [ ! -t 0 ]; then pargs+=(--noconfirm); fi
    echo "Downloading the updates (pacman -Syuw, $APPLY_MODE) ..."
    APPLY_PHASE=download
    _apply_pacman "${pargs[@]}" -Syuw; rc=$?
    if [ "$rc" != 0 ]; then
        _apply_finish failed "$rc" "download failed (pacman -Syuw exit status $rc)"
        APPLY_PHASE=done
        error "pacman -Syuw failed (exit status $rc); nothing was installed"
        _apply_refresh_statusbar
        return 1
    fi
    APPLY_PHASE=install   # from here a signal never reaches pacman; see "Signals"
    echo "Installing the updates (pacman -Syu) ..."
    [ ! -t 0 ] || echo "Installing — do not press Ctrl-C or close this terminal until it finishes."
    if [ -n "$APPLY_SIG" ]; then   # a signal that came in before pacman exists: do not start the transaction
        _apply_finish failed "$((128 + APPLY_SIGNUM))" "interrupted by $APPLY_SIG before the installation started"
        APPLY_PHASE=done
        error "interrupted ($APPLY_SIG) before pacman -Syu started; nothing was installed"
        return 1
    fi
    _apply_pacman "${pargs[@]}" -Syu; rc=$?
    if [ "$rc" != 0 ]; then
        _apply_finish failed "$rc" "pacman -Syu failed (exit status $rc)"
        APPLY_PHASE=done
        error "pacman -Syu failed (exit status $rc); the update may be partly applied. known-good is untouched; $rec/recovery.sh restores it."
        changed=$(jq -r 'if (.packages | type) == "array" then (.packages | length) else 0 end' "$pending/manifest.json" 2>/dev/null)
        if [[ $changed =~ ^[0-9]+$ ]] && [ "$changed" -gt 0 ]; then
            _apply_partly_changed "$changed"
        fi
        [ -n "$APPLY_SIG" ] || _apply_refresh_statusbar
        return 1
    fi
    # Nothing changed (and no earlier pending record to keep): no empty record to verify.
    if [ "$have_pending" != true ] && after=$(pkg_installed) && [ "$after" = "$APPLY_BEFORE" ] \
            && rm -f -- "$pending/manifest.json" && rmdir -- "$pending"; then
        APPLY_WRITTEN=0; APPLY_FINAL=1; APPLY_PHASE=done
        echo "nothing to update: no package changed, no pending record kept"
        [ -n "$APPLY_SIG" ] || _apply_refresh_statusbar
        return 0
    fi
    _apply_finish awaiting-verification 0 "" || { APPLY_PHASE=done; return 1; }
    APPLY_PHASE=done
    if [ -n "$APPLY_SIG" ]; then   # interrupted while pacman ran: the record tells the real outcome
        error "interrupted (${APPLY_SIG}) during the update; pacman was left to finish, the pending record is awaiting-verification"
        return 1
    fi
    if [ "$(jq -r .state "$pending/manifest.json" 2>/dev/null)" != awaiting-verification ]; then
        error "the update ran but its state could not be read back from the pending record"
        return 1
    fi

    # Step 7: trim the cache, only after a successful update. known-good's hardlinks keep their archives.
    echo "Trimming the package cache (paccache -rk$keep) ..."
    _pkg_paccache "$keep" "$cache" || warn "paccache failed; the update itself succeeded"

    # Step 8
    _apply_refresh_statusbar
    echo "Update applied: state awaiting-verification, known-good untouched."
    echo "Reboot, then run 'pkg-update.sh verify' and 'pkg-update.sh promote'. If the machine misbehaves, run 'sudo $rec/recovery.sh' from a TTY."
    return 0
}

# pkg_apply [--system] [--force] [--yes]: see above. Exit status 0, 1, 2 (usage), 4 (pending gate).
#   --system  update without the IgnorePkg/IgnoreGroup lines (a temp copy of the pacman config)
#   --force   continue although an unpromoted pending record exists (never rewrites known-good)
#   --yes     no questions: passed on to fetch_missing, and pacman runs with --noconfirm
#             (without --yes pacman asks at a terminal; with no terminal it never asks)
pkg_apply() {
    local system=false force=false yes=false arg rc
    for arg in "$@"; do
        case "$arg" in
            --system) system=true ;;
            --force)  force=true ;;
            --yes)    yes=true ;;
            *) error "apply: unknown option: $arg"; return 2 ;;
        esac
    done
    APPLY_BEFORE=""; APPLY_STARTED=""; APPLY_MODE=normal; APPLY_REPLACED=""; APPLY_PENDING=""
    APPLY_CREATED=0; APPLY_WRITTEN=0; APPLY_FINAL=0; APPLY_CHILD=""; APPLY_TMPD=""
    APPLY_PHASE=""; APPLY_SIG=""; APPLY_SIGNUM=0
    _apply_run "$system" "$force" "$yes"; rc=$?
    [ -z "$APPLY_SIG" ] || _apply_reraise
    _apply_cleanup
    _apply_traps_off
    return "$rc"
}

# pkg_discard: end the pending record (the update in flight) without promoting it. The record is not deleted:
# pending/ is renamed to pending.discarded/ (an older pending.discarded/ is replaced), the evidence that the
# installed state is unverified: while it exists apply never rewrites known-good from the installed state, and
# promote deletes it. The update itself stays installed; known-good is never touched. Nothing pending is not an
# error. A pending that is not a directory (a symlink, a file) is removed, never kept as pending.discarded.
pkg_discard() {
    local rec pending kept old
    rec=$(pkg_recovery_dir); pending="$rec/pending"; kept="$rec/pending.discarded"
    if [ ! -e "$pending" ] && [ ! -L "$pending" ]; then
        echo "nothing to discard: there is no pending update record"
        return 0
    fi
    old="$rec/pending.discard.$$"   # (debris the sweep removes if a kill leaves it)
    rm -rf -- "$old"
    if [ -L "$pending" ] || [ ! -d "$pending" ]; then
        mv -T -- "$pending" "$old" || { error "cannot remove $pending"; return 1; }   # one rename: pending vanishes at once
        rm -rf -- "$old"
        echo "removed the pending update record (it was not a directory). The update stays installed; known-good is untouched."
        return 0
    fi
    if [ -e "$kept" ] || [ -L "$kept" ]; then
        mv -T -- "$kept" "$old" || { error "cannot replace the older $kept"; return 1; }
    fi
    if ! mv -T -- "$pending" "$kept"; then
        [ ! -e "$old" ] || mv -T -- "$old" "$kept"
        error "cannot move $pending to $kept"
        return 1
    fi
    rm -rf -- "$old"
    echo "discarded the pending update record (kept as $kept until the next promote). The update stays installed; known-good stays as it is and the next apply does not replace it. To go back to it: sudo $rec/recovery.sh"
}

# --- cache: size, keep, clear ---------------------------------------------------------------------
# pkg_cache_size is the only user-level one; keep and clear are library functions for the dispatcher
# (`elevate`, `acquire_lock`, `log_start cache-keep|cache-clear` come first). Known-good archives are
# hardlinks of cache files: trimming or wiping the cache only removes the cache's names, the data
# stays reachable through known-good (no function here ever touches the recovery dir).

# _pkg_paccache KEEP CACHE: `paccache -rk<KEEP> -c <CACHE>` (PKG_PACCACHE may hold arguments), no
# terminal, without the update lock fd (a leftover child must not hold the lock). Its exit status.
_pkg_paccache() {
    local -a pc
    read -ra pc <<<"${PKG_PACCACHE:-paccache}"
    "${pc[@]}" -rk"$1" -c "$2" </dev/null 200>&-
}

# pkg_cache_keep_valid N: N is exactly the canonical decimal form of an integer 1..20 (no sign, no
# leading zeros, no spaces: "007" and "+4" are rejected, not guessed at).
pkg_cache_keep_valid() {
    case ${1-} in
        [1-9]|1[0-9]|20) return 0 ;;
        *) return 1 ;;
    esac
}

# pkg_cache_size: total bytes of the package files in the cache dir, as a plain integer. A package file
# is a regular file `*.pkg.tar.*` directly in the dir that is neither a `.sig` nor a `.part`; the
# download-* directories (pacman's partial downloads) and anything else are not counted. Files are
# counted as they are: a file that is also hardlinked from known-good is counted once, by its name in
# the cache. No cache dir: 0. A dir that cannot be read: message, exit 1.
pkg_cache_size() {
    local cache sizes
    cache=$(pkg_cache_dir)
    if [ ! -e "$cache" ] && [ ! -L "$cache" ]; then
        echo 0
        return 0
    fi
    if [ ! -d "$cache" ] || [ ! -r "$cache" ] || [ ! -x "$cache" ]; then
        error "cannot read the package cache $cache"
        return 1
    fi
    # -H: the cache may be a symlink to a directory on another disk. find's own status is kept (a
    # failure part-way must not give a partial sum): its output is collected first, then summed.
    sizes=$(find -H "$cache" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' ! -name '*.part' -printf '%s\n' 2>&1) || {
        error "cannot list the package cache $cache: $(grep -v -E '^[0-9]+$' <<<"$sizes" | head -n 1)"
        return 1
    }
    grep -E '^[0-9]+$' <<<"$sizes" | awk '{ s += $1 } END { printf "%.0f\n", s }'
}

# pkg_cache_keep N: keep the N newest versions of every package (paccache -rk<N> -c <cache>), N 1..20
# (exit 2 otherwise). Does not write the cache-keep setting (the UI owns it). Exit 1 when paccache fails.
pkg_cache_keep() {
    local n=${1-} cache
    pkg_cache_keep_valid "$n" || { error "cache keep: N must be an integer from 1 to 20"; return 2; }
    cache=$(pkg_cache_dir)
    [ -d "$cache" ] || { error "no package cache at $cache"; return 1; }
    echo "Trimming the package cache (paccache -rk$n) ..."
    _pkg_paccache "$n" "$cache" || { error "paccache failed"; return 1; }
    echo "Package cache trimmed: the $n newest versions of each package stay. Known-good archives are untouched."
    _apply_refresh_statusbar
    return 0
}

# pkg_cache_clear: remove every package file from the cache (what `pacman -Scc` does).
# NOT `pacman -Scc --noconfirm`: --noconfirm answers each prompt with its default, and the default of
# "Do you want to remove ALL files from cache? [y/N]" is N, so that command removes nothing (checked
# with the real pacman 7.1 in a user namespace). Instead the answers come from a here-string on pacman's
# stdin: it never reads the caller's stdin and never needs a terminal, and when pacman asks more than
# there are answers it reads EOF = the default (it does not wait). Answers are "y" to everything pacman
# can ask: the cache dir(s), and "remove unused repositories?" (pacman then deletes the sync databases
# of repositories that are no longer in pacman.conf; the databases of configured repos stay).
# Stale download-* directories (partial downloads) go first: pacman cannot remove a directory, it
# reports "Is a directory" and exits 255 although the packages are gone. The result is checked, not
# trusted: package files left in the cache, or a failing pacman, are exit 1.
pkg_cache_clear() {
    local cache answers=$'y\ny\ny\ny' left rc dir
    cache=$(pkg_cache_dir)
    [ -d "$cache" ] || { error "no package cache at $cache"; return 1; }
    # find -H: the cache may be a symlink to a directory (without -H find would not enter it, the
    # post-check below would count 0 files and pass whatever pacman did).
    find -H "$cache" -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} + 2>/dev/null
    echo "Clearing the package cache (pacman -Scc) ..."
    pkg_pacman -Scc <<<"$answers"; rc=$?
    if [ "$rc" -ne 0 ]; then
        dir=$(find -H "$cache" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
        if [ "$rc" -eq 255 ] && [ -n "$dir" ]; then
            error "pacman -Scc failed: it cannot remove the directory $dir from the cache (move it away and retry)"
        else
            error "pacman -Scc failed (exit $rc)"
        fi
        return 1
    fi
    left=$(find -H "$cache" -maxdepth 1 -name '*.pkg.tar.*' 2>&1) || {
        error "cannot list the package cache $cache: $(head -n 1 <<<"$left")"
        return 1
    }
    left=$(grep -c . <<<"$left")
    if [ "$left" -gt 0 ]; then
        error "pacman -Scc left $left package file(s) in $cache"
        return 1
    fi
    echo "Package cache cleared. Known-good archives are untouched (hardlinks)."
    _apply_refresh_statusbar
    return 0
}

# --- verify / promote ---------------------------------------------------------------------
# verify_system: the checks that say whether a freshly updated system is fit to become the new
# known-good. Runs as the normal user (no root, no lock, changes nothing). One line per check on
# stdout, `STATUS check[: detail]`, STATUS = PASS | FAIL | WARN | SKIP, in this order:
#   kernel    the running `uname -r` equals the release of the installed kernel package
#             (linux, linux-lts, linux-zen, linux-hardened, linux-rt, linux-rt-lts: any installed one
#             may be the running one). FAIL when none matches (the update was not booted yet).
#             SKIP when none of those packages is installed (a custom kernel: nothing to compare).
#   gpu       `nvidia-smi -L` lists a GPU. SKIP when no package named nvidia* is installed.
#   services  `systemctl --failed --no-legend` lists nothing.
#   journal   priority-err messages of this boot: PASS with none, WARN with a count. Never a FAIL
#             (also WARN when the journal cannot be read): the count is reported, not judged.
#   network   an IPv4 or IPv6 default route exists.
# A check whose command cannot run is a FAIL (fail closed); only kernel (no kernel package), gpu
# (no nvidia package) say SKIP, and journal says WARN. Exit status 1 when any check FAILs, else 0.
# PKG_VERIFY_<KERNEL|GPU|SERVICES|JOURNAL|NETWORK> (tests; never forwarded to the root process by
# elevate) replaces a whole check by a command: exit 0 = PASS, anything else = FAIL, the first
# line it prints is the detail; blank = no override.
VERIFY_KERNEL_PKGS=(linux linux-lts linux-zen linux-hardened linux-rt linux-rt-lts)

# _verify_line STATUS CHECK [DETAIL]
_verify_line() { printf '%s %s%s\n' "$1" "$2" "${3:+: $(tr '\n' ' ' <<<"$3" | sed 's/ *$//')}"; }

# _verify_kernel_release PKG VERSION: the `uname -r` the installed kernel package PKG at VERSION
# gives. Arch's pkgver is `6.15.3.arch1-1` and the kernel calls itself `6.15.3-arch1-1`; `6.16.arch1-1`
# is `6.16.0-arch1-1`; an epoch (`1:`) is not part of it; the variants add their name
# (`linux-lts 6.12.30-1` is `6.12.30-1-lts`, `linux-zen 6.15.3.zen1-1` is `6.15.3-zen1-1-zen`,
# `linux-rt 6.14.0.rt3.arch1-1` is `6.14.0-rt3-arch1-1-rt`: every `.tag` becomes `-tag`).
# Fails with no output when VERSION has no pkgrel.
_verify_kernel_release() {
    local pkg=$1 v=$2 ver rel base tag="" sfx=""
    [[ $v =~ ^[0-9]+: ]] && v=${v#*:}
    [[ $v == *-* ]] || return 1
    rel=${v##*-}; ver=${v%-*}
    [ -n "$ver" ] && [ -n "$rel" ] || return 1
    base=$ver
    if [[ $ver =~ ^([0-9]+(\.[0-9]+)*)((\.[A-Za-z][A-Za-z0-9]*)+)$ ]]; then   # .arch1 / .rt3.arch1 / .zen1
        base=${BASH_REMATCH[1]}; tag=${BASH_REMATCH[3]//./-}
    fi
    [[ $base =~ ^[0-9]+\.[0-9]+$ ]] && base=$base.0
    case $pkg in linux) ;; linux-*) sfx=-${pkg#linux-} ;; esac
    printf '%s%s-%s%s\n' "$base" "$tag" "$rel" "$sfx"
}

_verify_kernel() {
    local running installed pkg ver want found="" matched="" tried=""
    if ! running=$(uname -r 2>/dev/null) || [ -z "$running" ]; then
        _verify_line FAIL kernel "cannot read the running kernel (uname -r failed)"; return 1
    fi
    if ! installed=$(pkg_installed); then
        _verify_line FAIL kernel "cannot read the installed packages"; return 1
    fi
    for pkg in "${VERIFY_KERNEL_PKGS[@]}"; do
        ver=$(awk -v n="$pkg" '$1 == n { print $2; exit }' <<<"$installed")
        [ -n "$ver" ] || continue
        found+=" $pkg"
        want=$(_verify_kernel_release "$pkg" "$ver") || want="(unreadable version)"
        tried+="${tried:+, }$pkg $ver (expects $want)"
        [ "$want" != "$running" ] || matched="$pkg $ver"
    done
    if [ -z "$found" ]; then
        _verify_line SKIP kernel "no kernel package (${VERIFY_KERNEL_PKGS[*]}) is installed, so the running kernel $running cannot be compared"
        return 0
    fi
    if [ -n "$matched" ]; then
        _verify_line PASS kernel "running $running is the installed $matched"
        return 0
    fi
    _verify_line FAIL kernel "running kernel $running does not match the installed kernel package: $tried. The new kernel is not running yet: reboot first"
    return 1
}

# _verify_cmd CMD ARG...: run CMD with stdin closed and the update lock fd closed; stdout goes to
# V_OUT, stderr to V_ERR (never merged: a warning on stderr is not output to parse). Returns CMD's status
# (1 with V_ERR set when the temp file for stderr cannot be made).
V_OUT=""; V_ERR=""
_verify_cmd() {
    local errf rc
    V_OUT=""; V_ERR=""
    if ! errf=$(mktemp "${TMPDIR:-/tmp}/pkg-verify-err.XXXXXX" 2>/dev/null); then
        V_ERR="cannot create a temp file"; return 1
    fi
    V_OUT=$("$@" 2>"$errf" </dev/null 200>&-); rc=$?
    V_ERR=$(cat "$errf" 2>/dev/null); rm -f -- "$errf"
    return "$rc"
}

_verify_gpu() {
    local installed nv out
    if ! installed=$(pkg_installed); then
        _verify_line FAIL gpu "cannot read the installed packages"; return 1
    fi
    nv=$(awk '$1 ~ /^nvidia/ { printf "%s%s", (n++ ? ", " : ""), $1 }' <<<"$installed")
    if [ -z "$nv" ]; then
        _verify_line SKIP gpu "no nvidia package is installed"; return 0
    fi
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        _verify_line FAIL gpu "$nv is installed but nvidia-smi was not found"; return 1
    fi
    if _verify_cmd timeout 30 nvidia-smi -L && grep -q '^GPU ' <<<"$V_OUT"; then
        _verify_line PASS gpu "$(head -n 1 <<<"$V_OUT")"; return 0
    fi
    out=${V_ERR:-$V_OUT}
    _verify_line FAIL gpu "nvidia-smi -L did not list a GPU${out:+: $(head -n 1 <<<"$out")}"
    return 1
}

_verify_services() {
    local out units
    if ! _verify_cmd systemctl --failed --no-legend --plain; then
        out=${V_ERR:-$V_OUT}
        _verify_line FAIL services "systemctl --failed did not run${out:+: $(head -n 1 <<<"$out")}"; return 1
    fi
    out=$V_OUT
    if [ -z "$(tr -d '[:space:]' <<<"$out")" ]; then
        _verify_line PASS services "no failed units"; return 0
    fi
    units=$(sed -E 's/^[^A-Za-z0-9@_.-]*//' <<<"$out" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $1 }')
    _verify_line FAIL services "failed units: $units"
    return 1
}

_verify_journal() {
    local out n
    if ! out=$(journalctl -b -p err -q --no-pager 2>/dev/null </dev/null 200>&-); then   # stderr: hints are not messages
        _verify_line WARN journal "could not read this boot's journal (journalctl failed)"; return 0
    fi
    n=$(grep -c . <<<"$out")
    if [ "$n" = 0 ]; then
        _verify_line PASS journal "no error-priority messages this boot"
    else
        _verify_line WARN journal "$n error-priority message(s) this boot; look at them with: journalctl -b -p err"
    fi
    return 0
}

_verify_network() {
    local r4 r6="" route
    if ! command -v ip >/dev/null 2>&1; then
        _verify_line FAIL network "the ip command was not found"; return 1
    fi
    if ! _verify_cmd ip -4 route show default; then
        _verify_line FAIL network "ip route did not run: $(head -n 1 <<<"${V_ERR:-$V_OUT}")"; return 1
    fi
    r4=$V_OUT
    _verify_cmd ip -6 route show default || V_OUT=""   # IPv6 may be switched off: not an error
    r6=$V_OUT
    route=$(grep -m1 . <<<"$r4"; true)
    [ -n "$route" ] || route=$(grep -m1 . <<<"$r6"; true)
    if [ -n "$route" ]; then
        _verify_line PASS network "$route"; return 0
    fi
    _verify_line FAIL network "no default route"
    return 1
}

# _verify_run NAME: one check, or its PKG_VERIFY_<NAME> override. Returns 1 for a FAIL.
_verify_run() {
    local name=$1 var cmd out rc
    var=PKG_VERIFY_$(tr 'a-z' 'A-Z' <<<"$name")
    read -ra cmd <<<"${!var:-}"
    if [ "${#cmd[@]}" = 0 ]; then
        "_verify_$name"
        return
    fi
    out=$("${cmd[@]}" 2>&1 </dev/null 200>&-); rc=$?
    if [ "$rc" = 0 ]; then
        _verify_line PASS "$name" "$(head -n 1 <<<"$out")"
    else
        _verify_line FAIL "$name" "$(head -n 1 <<<"$out")"
        return 1
    fi
}

verify_system() {
    local fails=0 name
    for name in kernel gpu services journal network; do
        _verify_run "$name" || fails=$((fails + 1))
    done
    if [ "$fails" -gt 0 ]; then
        error "verify: $fails check(s) failed"
        return 1
    fi
    return 0
}

# pkg_promote [--force] [--yes]: spec "Verify and promote". The dispatcher has taken the lock and
# started the log (`elevate`, `acquire_lock`, `log_start promote`); never call the dispatcher from
# here (the lock would deadlock with exit 3). Exit status 0 promoted, 1 refused or failed, 2 usage.
# `known-good` is the only verified rollback point, so nothing here may lose it:
#   0. sweep (as apply does): a cut-off earlier promote/apply is recovered before anything else;
#   1. verify_system, and the pending record's state: any FAIL, a pending update that `failed` or is
#      still `running` (or replaced such an older one: `replaced.state`), or an unreadable pending
#      record, refuses (exit 1, nothing changed) unless --force, which says loudly what it overrides.
#      awaiting-verification, or no pending record at all (a manual pacman update, an apply that changed
#      nothing), are fine: the current verified state is what gets checkpointed;
#   2. checkpoint_build of the installed protected set into known-good.new.PID, next to known-good
#      (one filesystem; built in .tmp and renamed, so it is complete or absent). A missing archive
#      fails here, with the old known-good, pending and known-good.prev untouched;
#      The new tree is flushed to disk (sync) before the swap and the filesystem is committed (sync -f)
#      after the renames and before the old copy is deleted, so a power loss cannot leave an empty new
#      manifest with the old (only verified) copy gone. --force marks the new manifest
#      (forced: true, verify_failures: [check names]) and first makes a hardlink copy of the old
#      known-good (known-good.prev.new.PID) that becomes known-good.prev through _apply_swap_prev after the swap
#      (the sweep finishes that if a kill cuts it off), so a forced promotion never leaves zero verified rollbacks.
#   3. the swap: known-good -> known-good.old.PID, known-good.new.PID -> known-good. A failing rename
#      puts the old one back. A cut-off between the renames (SIGKILL, power loss) leaves no known-good
#      but known-good.old.PID: _apply_sweep (next apply or promote) renames it back, and the
#      pending record is still there, so the machine is exactly as before the promote;
#   4. then known-good.old.PID (renamed to known-good.discard.PID first, which the sweep deletes and never restores),
#      pending/, pending.discarded/ (a discarded update is superseded by the verified state) and, unless forced, known-good.prev (a promoted, verified state supersedes
#      the unverified one apply kept) are deleted and recovery.sh is installed (copy to a temp file,
#      chmod 755, rename; a missing source or a failing copy only warns, the promotion stands).
# Signals (INT/TERM/HUP): before the swap, the new directory is removed, the caller's traps come
# back and the signal is re-raised (known-good is untouched). From the swap on the signal is only
# remembered: the renames and the clean-up finish (the renames run with the signals ignored, so a
# terminal's Ctrl-C does not kill a mv half way) and then the signal is re-raised. SIGPIPE is ignored
# from the start (the log's tee dies on a terminal close).
# Test env: PKG_RECOVERY_SRC (recovery.sh to install; default scripts/recovery.sh next to this file),
# PKG_VERIFY_* (see verify_system), PKG_QS & co. (the statusbar refresh, as in apply).
PKG_LIB_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
PROMOTE_NEW=""
PROMOTE_PREVNEW=""   # forced: the hardlink copy of the old known-good, until it is .prev
PROMOTE_PHASE=""     # "" (before the swap), swap, post
PROMOTE_SIG=""; PROMOTE_SIGNUM=0
PROMOTE_TRAPS=0
PROMOTE_OLD_INT=""; PROMOTE_OLD_TERM=""; PROMOTE_OLD_HUP=""; PROMOTE_OLD_PIPE=""

_promote_cleanup() {
    [ -z "$PROMOTE_NEW" ] || rm -rf -- "$PROMOTE_NEW" "$PROMOTE_NEW.tmp.$$"
    PROMOTE_NEW=""
    [ -z "$PROMOTE_PREVNEW" ] || rm -rf -- "$PROMOTE_PREVNEW"   # (cleared once it has become .prev or is kept for the sweep)
    PROMOTE_PREVNEW=""
    return 0
}

_promote_traps_on() {
    PROMOTE_OLD_INT=$(trap -p INT); PROMOTE_OLD_TERM=$(trap -p TERM); PROMOTE_OLD_HUP=$(trap -p HUP)
    PROMOTE_OLD_PIPE=$(trap -p PIPE)
    trap '_promote_signal INT 2' INT
    trap '_promote_signal TERM 15' TERM
    trap '_promote_signal HUP 1' HUP
    trap '' PIPE
    PROMOTE_TRAPS=1
}

_promote_traps_off() {
    [ "$PROMOTE_TRAPS" = 1 ] || return 0
    PROMOTE_TRAPS=0
    trap - INT TERM HUP PIPE
    [ -z "$PROMOTE_OLD_PIPE" ] || eval "$PROMOTE_OLD_PIPE"
    [ -z "$PROMOTE_OLD_INT" ] || eval "$PROMOTE_OLD_INT"
    [ -z "$PROMOTE_OLD_TERM" ] || eval "$PROMOTE_OLD_TERM"
    [ -z "$PROMOTE_OLD_HUP" ] || eval "$PROMOTE_OLD_HUP"
}

# _promote_signal SIG NUM: see "Signals" above.
_promote_signal() {
    local sig=$1 num=$2
    if [ "$PROMOTE_PHASE" = swap ] || [ "$PROMOTE_PHASE" = post ]; then
        [ -n "$PROMOTE_SIG" ] || { PROMOTE_SIG=$sig; PROMOTE_SIGNUM=$num; }
        return 0
    fi
    trap '' INT TERM HUP PIPE
    _promote_cleanup
    _promote_traps_off
    kill -s "$sig" "$BASHPID"
    exit $((128 + num))   # the caller's handler returned (or ignores it): this promote is still aborted
}

# _promote_reraise: a signal was remembered during the swap/clean-up: give the caller's traps back, re-raise.
_promote_reraise() {
    local sig=$PROMOTE_SIG num=$PROMOTE_SIGNUM
    _promote_cleanup
    _promote_traps_off
    kill -s "$sig" "$BASHPID"
    exit $((128 + num))
}

# _promote_mv SRC DEST: one rename, with INT/TERM/HUP ignored in the process that does it (the
# ignore is inherited by mv), so a Ctrl-C to the process group cannot cut a rename short. `mv -T`: a
# rename that cannot happen fails, it never moves SRC into an existing directory.
_promote_mv() { ( trap '' INT TERM HUP; mv -T -- "$1" "$2" ); }

# _promote_drop PATH TAG: delete PATH (a directory, or a link or file) so that it vanishes at once:
# one rename to PATH-ish.discard.PID (swept if a kill leaves it), then the removal.
_promote_drop() {
    local path=$1 aside=$2.discard.$$
    [ -e "$path" ] || [ -L "$path" ] || return 0
    rm -rf -- "$aside"
    mv -T -- "$path" "$aside" || return 1
    rm -rf -- "$aside"
}

# _pkg_install_recovery REC WHAT: recovery.sh -> REC/recovery.sh, mode 755, by temp file + rename (an existing
# copy stays complete until the new one is). Used by apply (after the checkpoint, before pacman) and promote.
# Only warns, WHAT ending the warning ("known-good was updated", "the update goes ahead"): it never stops the caller.
_pkg_install_recovery() {
    local rec=$1 what=$2 src=${PKG_RECOVERY_SRC:-$PKG_LIB_DIR/recovery.sh} dest tmp
    dest="$rec/recovery.sh"; tmp="$dest.tmp.$$"
    if [ ! -f "$src" ]; then
        warn "recovery.sh not installed: $src does not exist. $what; install recovery.sh before you need it."
        return 0
    fi
    if (umask 022; cp -- "$src" "$tmp") && chmod 755 -- "$tmp" && mv -T -- "$tmp" "$dest"; then
        echo "installed $dest"
    else
        rm -rf -- "$tmp"
        warn "recovery.sh could NOT be installed in $rec (an older copy, if any, is unchanged). $what."
    fi
    return 0
}

# _promote_run FORCE: steps 0-4 above. Returns 0 or 1.
_promote_run() {
    local force=$1 rec kg pending prev new old report vrc reason state rstate rj had_old=false probe kernel created rc=0 installed
    local forced=false vnames vjson mj prevnew=""
    local -a reasons=()
    rec=$(pkg_recovery_dir); kg="$rec/known-good"; pending="$rec/pending"; prev="$kg.prev"

    command -v jq >/dev/null 2>&1 || { error "jq is not installed"; return 1; }
    (umask 022; mkdir -p -- "$rec") || { error "cannot create the recovery storage $rec"; return 1; }
    if ! probe=$(mktemp "$rec/.write-test.XXXXXX" 2>/dev/null); then
        error "the recovery storage $rec is not writable"
        return 1
    fi
    rm -f -- "$probe"
    _apply_sweep   # recover rollback state a hard kill cut off (we hold the lock)

    # 1. verify, and what the pending record says
    report=$(verify_system); vrc=$?
    [ -z "$report" ] || printf '%s\n' "$report"
    if [ "$vrc" != 0 ]; then
        while IFS= read -r reason; do reasons+=("$reason"); done < <(grep '^FAIL ' <<<"$report")
        [ "${#reasons[@]}" -gt 0 ] || reasons+=("FAIL verify: the checks did not pass")
    fi
    if [ -e "$pending" ] || [ -L "$pending" ]; then
        rj=$(pkg_record pending)
        if [ -z "$rj" ]; then
            reasons+=("the pending update record is unreadable, so it is unknown whether that update finished (run 'pkg-update.sh discard' to drop it)")
        else
            state=$(jq -r '.state // "unknown"' <<<"$rj" 2>/dev/null)
            case $state in
                awaiting-verification) ;;
                failed|running)
                    reasons+=("the pending update is '$state': an update that failed or was cut short is not promoted (run 'pkg-update.sh discard' to drop it, then apply again)") ;;
                *) reasons+=("the pending update has state '$state', not awaiting-verification (run 'pkg-update.sh discard' to drop it)") ;;
            esac
            rstate=$(jq -r 'if .replaced == null then "" else (.replaced.state // "unknown") end' <<<"$rj" 2>/dev/null)
            case $rstate in
                ''|awaiting-verification) ;;
                *) reasons+=("the pending update (apply --force) replaced an older pending update that was '$rstate', so the installed packages hold an update that never completed (run 'pkg-update.sh discard' to drop the record)") ;;
            esac
        fi
    else
        echo "no pending update record: promoting the current state (a manual pacman update, or an apply that changed nothing)"
    fi
    if [ "${#reasons[@]}" -gt 0 ]; then
        if [ "$force" != true ]; then
            error "promote refused; known-good, pending and known-good.prev were not changed:"
            for reason in "${reasons[@]}"; do echo "  $reason" >&2; done
            error "'pkg-update.sh promote --force' promotes anyway."
            return 1
        fi
        forced=true
        for reason in "${reasons[@]}"; do warn "--force: promoting although: $reason"; done
        warn "--force: the new known-good is marked forced, and the previous known-good is kept as known-good.prev"
        case ${reasons[*]} in
            *"FAIL kernel"*) warn "--force: the running kernel is NOT the installed one: the new known-good will hold packages (kernel, modules) that this boot has not run. Reboot and verify before you rely on it." ;;
        esac
    fi

    # 2. build the new known-good next to the old one
    new="$kg.new.$$"
    PROMOTE_NEW=$new
    rm -rf -- "$new" "$new.tmp.$$"
    echo "Building the new known-good from the installed protected packages ..."
    if ! checkpoint_build "$new" promote; then
        error "the new known-good could not be built; known-good, the pending record and known-good.prev are unchanged. If archives are missing from the cache: pkg-update.sh fetch-missing"
        return 1
    fi
    if [ "$forced" = true ]; then   # the record says it was forced, and which checks it overrode
        vnames=$(grep '^FAIL ' <<<"$report" | awk '{ sub(/:$/, "", $2); print $2 }')
        if ! vjson=$(jq -nc --arg n "$vnames" '$n | split("\n") | map(select(. != ""))') \
                || ! mj=$(jq --argjson v "$vjson" '. + {forced: true, verify_failures: $v, verified: false}' "$new/manifest.json") || [ -z "$mj" ] \
                || ! printf '%s\n' "$mj" | (umask 022; write_atomic "$new/manifest.json") \
                || ! chmod 644 -- "$new/manifest.json"; then
            error "could not mark the new known-good as forced; known-good was not changed"
            return 1
        fi
    fi
    if ! _apply_dir_complete "$new"; then
        error "the new known-good is incomplete; known-good was not changed"
        return 1
    fi
    if ! installed=$(protected_installed) || ! pkg_matches_known_good "$(jq -c . "$new/manifest.json" 2>/dev/null)" "$installed"; then
        error "the installed protected packages changed while promote ran; known-good was not changed"
        return 1
    fi
    if [ ! -e "$kg" ] && [ ! -L "$kg" ]; then   # the sweep restores a cut-off swap: one it could not restore is not ours to bury
        for old in "$kg".old.*; do
            [ -s "$old/manifest.json" ] || continue
            error "there is no known-good, but $old (the previous one) could not be restored by the sweep; not touching anything. Rename it to $kg by hand."
            return 1
        done
    fi

    # Durability barrier: the new tree is on disk before the old known-good is touched.
    if ! _pkg_sync_tree "$new"; then
        error "cannot flush the new known-good to disk; known-good was not changed"
        return 1
    fi
    if [ "$forced" = true ] && { [ -e "$kg" ] || [ -L "$kg" ]; }; then   # a forced promotion keeps the superseded one as .prev
        prevnew="$kg.prev.new.$$"
        PROMOTE_PREVNEW=$prevnew
        rm -rf -- "$prevnew"
        if ! cp -al -- "$kg" "$prevnew"; then
            error "cannot keep the old known-good as known-good.prev; known-good was not changed"
            return 1
        fi
    fi

    # 3. the swap: old -> known-good.old.PID, new -> known-good
    old="$kg.old.$$"
    _promote_drop "$old" "$kg" || { error "cannot clear a stale $old; known-good was not changed"; return 1; }
    PROMOTE_PHASE=swap
    if [ -e "$kg" ] || [ -L "$kg" ]; then
        if ! _promote_mv "$kg" "$old"; then
            PROMOTE_PHASE=""
            error "cannot move the old known-good aside; known-good was not changed"
            return 1
        fi
        had_old=true
    fi
    if ! _promote_mv "$new" "$kg"; then
        if [ "$had_old" = true ] && ! _promote_mv "$old" "$kg"; then
            error "CRITICAL: the old known-good is now $old and could not be put back. Rename it to $kg (the next apply or promote does it too)."
        else
            error "cannot move the new known-good into place; the old known-good is unchanged"
        fi
        PROMOTE_PHASE=""
        return 1
    fi
    if ! _pkg_syncfs "$rec"; then   # barrier: renames and data are on disk before the old known-good is deleted
        if _promote_mv "$kg" "$new" && { [ "$had_old" != true ] || _promote_mv "$old" "$kg"; }; then
            error "cannot commit the new known-good to disk; the old known-good is back and unchanged"
        else
            error "CRITICAL: the new known-good could not be committed to disk and the swap could not be undone. The previous one is $old; rename it to $kg if $kg is missing or wrong."
        fi
        PROMOTE_PHASE=""
        return 1
    fi
    PROMOTE_NEW=""
    PROMOTE_PHASE=post

    # 4. the promotion is done; clean up
    if [ -n "$prevnew" ]; then   # the superseded known-good becomes .prev (same crash-safe steps as apply's)
        if ! ( trap '' INT TERM HUP; _apply_swap_prev "$prevnew" ); then
            error "known-good WAS updated, but the superseded known-good could not be kept as known-good.prev; $prevnew keeps it and the next apply or promote retries"
            rc=1
        fi
        PROMOTE_PREVNEW=""
    fi
    _promote_drop "$old" "$kg" || warn "known-good was updated, but $old could not be removed (the next apply removes it)"
    if ! _promote_drop "$pending" "$rec/pending"; then
        error "known-good WAS updated, but the pending record could not be removed; run 'pkg-update.sh discard'"
        rc=1
    fi
    _promote_drop "$rec/pending.discarded" "$rec/pending" || warn "known-good was updated, but pending.discarded could not be removed"
    if [ "$forced" != true ]; then   # a verified promotion supersedes .prev; a forced one keeps (and renewed) it
        _promote_drop "$prev" "$prev" || warn "known-good was updated, but known-good.prev could not be removed"
    fi
    _pkg_install_recovery "$rec" "known-good was updated"
    created=$(jq -r '.created // "unknown"' "$kg/manifest.json" 2>/dev/null)
    kernel=$(jq -r '.kernel // "unknown"' "$kg/manifest.json" 2>/dev/null)
    PROMOTE_PHASE=""
    [ -n "$PROMOTE_SIG" ] || _apply_refresh_statusbar
    [ "$forced" != true ] || echo "known-good updated by --force (marked forced); the previous known-good is kept as known-good.prev"
    echo "known-good updated: $created, kernel $kernel"
    return "$rc"
}

pkg_promote() {
    local force=false arg rc
    for arg in "$@"; do
        case "$arg" in
            --force) force=true ;;
            --yes)   ;;
            *) error "promote: unknown option: $arg"; return 2 ;;
        esac
    done
    PROMOTE_NEW=""; PROMOTE_PREVNEW=""; PROMOTE_PHASE=""; PROMOTE_SIG=""; PROMOTE_SIGNUM=0
    _promote_traps_on
    _promote_run "$force"; rc=$?
    PROMOTE_PHASE=""
    [ -z "$PROMOTE_SIG" ] || _promote_reraise
    _promote_cleanup
    _promote_traps_off
    return "$rc"
}
