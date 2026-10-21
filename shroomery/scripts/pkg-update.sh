#!/usr/bin/env bash
# Safe system update: checkpoint, update, verify, promote. See shroomery/README.md
# ("Safe update") and quickshell/docs/superpowers/specs/2026-10-17-safe-system-update-design.md.
#
# Usage: pkg-update.sh status
#        pkg-update.sh check [--refresh] [--system]
#        pkg-update.sh checkpoint TARGET_DIR   (internal, for testing)
#        pkg-update.sh fetch-missing [--yes]
#        pkg-update.sh apply [--system] [--force] [--yes]
#        pkg-update.sh discard
#        pkg-update.sh verify
#        pkg-update.sh promote [--force] [--yes]
#        pkg-update.sh cache size | cache keep N | cache clear
#   status  JSON: {known_good: null|{created,kernel,forced,source,verified}, pending: null|{state,started,changed},
#           discarded: null|{state,started,changed}, matches: bool}. source = checkpoint|promote, verified = a
#           non-forced promote (older manifests without the keys: promote, verified unless forced); changed = packages
#           whose version the update changed; a pending/ or pending.discarded/ without a readable record is
#           {state: "unknown"}.
#   check   pending updates as JSON {updates:[{name,old,new,held}], count, held_count, refreshed};
#           count = updates not held back by IgnorePkg/IgnoreGroup, held_count = the held ones.
#           No root: uses a temp DB under $XDG_RUNTIME_DIR. --refresh re-downloads the sync
#           databases in full; --system ignores IgnorePkg/IgnoreGroup (nothing is held).
#           Exit 1 with a message on stderr when the sync or the query fails.
#   checkpoint  build a checkpoint (hardlinked archives + manifest.json) of the
#           installed protected set in TARGET_DIR; exit 1 and list what is missing
#   fetch-missing  download the protected packages' archives that the pacman cache lacks from the
#           Arch Linux Archive (signature and .PKGINFO verified, free space checked first).
#           Lists them and asks y/N on stdin unless --yes; declined = nothing downloaded, exit 0.
#           A package that fails is reported and skipped; exit 1 if any failed or space is short.
#           Needs write access to the cache: it re-executes itself as root through pkexec
#           (elevate), takes the update lock and logs to <recovery dir>/logs/ (first line
#           `LOG=<path>`). A UI always passes --yes: there is no terminal for the question.
#
#   apply   the update transaction (spec "Update flow"): checks storage (writable, same filesystem as
#           the cache, free space), stops with exit 4 while an unpromoted pending update exists,
#           makes sure known-good describes the installed protected set (taking a checkpoint,
#           fetching missing archives first), then pacman -Syuw and -Syu, and records the result in
#           pending/manifest.json (state awaiting-verification, or failed). After a successful update:
#           paccache -rk<cache-keep> -c <cache>, and a statusbar refresh (as the invoking user). A
#           mismatching known-good is kept as known-good.prev when replaced. No package changed: no
#           pending record is left. Signals: see pkg-lib.sh (apply never sends TERM to pacman and never interrupts
#           -Syu itself; but a Ctrl-C or hang-up in the terminal reaches pacman through the process group, so at a
#           terminal apply first says not to press Ctrl-C or close it). Its checkpoint is recorded as `source:
#           checkpoint`, not verified; while pending.discarded/ exists (a discarded update) known-good is never
#           rewritten from the installed state. recovery.sh is installed into the recovery dir before pacman runs.
#           A failed update that already changed packages says so (do not reboot; restore or finish).
#           --system also updates the packages IgnorePkg/IgnoreGroup hold back (a temp copy
#           of the pacman config; /etc/pacman.conf is never edited). --force overrides only the
#           pending stop (known-good stays as it is). --yes: no questions (also passed to
#           fetch-missing, pacman gets --noconfirm; a UI always passes it).
#           Exit: 0 done, 1 failed, 2 usage, 3 another update runs (lock / db.lck), 4 pending gate.
#   discard end the pending record without promoting it: pending/ becomes pending.discarded/ (replacing an older
#           one; promote deletes it). The update stays installed and known-good is untouched; while the discarded
#           record exists apply does not replace known-good. Nothing pending exits 0.
#   verify  run the post-update checks as the normal user (no root, no lock, changes nothing) and print one
#           `PASS|FAIL|WARN|SKIP <check>[: detail]` line each: kernel (running uname -r = the installed kernel
#           package), gpu (nvidia-smi -L when an nvidia* package is installed), services (systemctl --failed
#           empty), journal (count of priority-err lines this boot: WARN, never FAIL), network (a default
#           route). Exit 1 when any check FAILs. See pkg-lib.sh verify_system.
#   promote [--force] [--yes]  make the installed, verified state the new known-good (spec "Verify and
#           promote"): runs verify first and refuses (exit 1, nothing changed) on any FAIL, on a pending
#           update that failed / is still running / replaced such a one, or an unreadable pending record,
#           unless --force (which says what it overrides). Builds the new known-good from the installed
#           protected packages (a missing archive keeps the old one and exits 1), swaps it in so that
#           known-good never goes missing, then deletes the old one, pending/ and known-good.prev and installs
#           recovery.sh into the recovery dir. With no pending record it checkpoints the current state.
#           A --force promotion marks the new known-good (`forced: true`, `verify_failures: [...]` in its
#           manifest.json, `forced` in `status`) and keeps the superseded one as known-good.prev.
#           --yes is accepted and ignored (promote never asks). Root: same elevation, lock (exit 3) and log
#           as apply. Exit: 0 promoted, 1 refused/failed, 2 usage, 3 another update runs.
#   cache size   total bytes of the package files in the cache (`*.pkg.tar.*` that are not `.sig`/`.part`; download-*
#           dirs and other files not counted; hardlinks counted as they are in the cache), one integer. No root, no
#           lock; no cache dir prints 0; an unreadable one is exit 1.
#   cache keep N  paccache -rk<N> -c <cache>, N an integer 1..20 in canonical form (else exit 2 before pkexec). Root:
#           same elevation, lock (exit 3) and log as apply. Does not write the cache-keep setting. Exit 1 when
#           paccache fails.
#   cache clear   remove every package file from the cache with `pacman -Scc`, answered on stdin (never
#           --noconfirm: its default for that prompt is N, so nothing would be removed) and verified afterwards
#           (package files left or pacman failing = exit 1). Root like keep. Known-good archives are hardlinks
#           and stay. After keep and clear the statusbar is refreshed (best effort).
#
# Root subcommands start with `elevate "$SELF" SUBCOMMAND ARGS...`; the root process reads no
# file under $HOME, it gets the user's settings through PKG_CACHE_KEEP, PKG_PROTECTED_PATTERNS
# and PKG_USER_HOME (pkg-lib.sh). Exit 3 = another update runs (lock or pacman's db.lck).
SELF="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF")"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/pkg-lib.sh"

usage() {
    echo "Usage: pkg-update.sh status | check [--refresh] [--system] | checkpoint TARGET_DIR | fetch-missing [--yes]" >&2
    echo "       pkg-update.sh apply [--system] [--force] [--yes] | discard | verify | promote [--force] [--yes]" >&2
    echo "       pkg-update.sh cache size | cache keep N (1..20) | cache clear" >&2
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
    status) pkg_status ;;
    check) check_updates "$@" ;;
    checkpoint) [ $# -eq 1 ] || { usage; exit 2; }; checkpoint_build "$1" checkpoint ;;
    fetch-missing)
        for arg in "$@"; do   # a typo never reaches the password prompt
            case "$arg" in --yes) ;; *) usage; exit 2 ;; esac
        done
        elevate "$SELF" fetch-missing "$@"
        acquire_lock
        log_start fetch-missing || exit 1
        fetch_missing "$@" ;;
    apply)
        for arg in "$@"; do   # a typo never reaches the password prompt
            case "$arg" in --system|--force|--yes) ;; *) usage; exit 2 ;; esac
        done
        elevate "$SELF" apply "$@"
        acquire_lock
        log_start apply || exit 1
        pkg_apply "$@" ;;
    discard)
        [ $# -eq 0 ] || { usage; exit 2; }
        elevate "$SELF" discard
        acquire_lock
        log_start discard || exit 1
        pkg_discard ;;
    verify)
        [ $# -eq 0 ] || { usage; exit 2; }
        verify_system ;;
    promote)
        for arg in "$@"; do   # a typo never reaches the password prompt
            case "$arg" in --force|--yes) ;; *) usage; exit 2 ;; esac
        done
        elevate "$SELF" promote "$@"
        acquire_lock
        log_start promote || exit 1
        pkg_promote "$@" ;;
    cache)
        sub=${1:-}
        [ $# -gt 0 ] && shift
        case "$sub" in
            size)
                [ $# -eq 0 ] || { usage; exit 2; }
                pkg_cache_size ;;
            keep)   # N is validated before pkexec: a bad value never reaches the password prompt
                [ $# -eq 1 ] && pkg_cache_keep_valid "$1" || { usage; error "cache keep: N must be an integer from 1 to 20"; exit 2; }
                elevate "$SELF" cache keep "$1"
                acquire_lock
                log_start cache-keep || exit 1
                pkg_cache_keep "$1" ;;
            clear)
                [ $# -eq 0 ] || { usage; exit 2; }
                elevate "$SELF" cache clear
                acquire_lock
                log_start cache-clear || exit 1
                pkg_cache_clear ;;
            *) usage; exit 2 ;;
        esac ;;
    *) usage; exit 2 ;;
esac
