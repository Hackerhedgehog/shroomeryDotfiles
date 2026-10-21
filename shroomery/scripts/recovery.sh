#!/usr/bin/env bash
# recovery.sh: put the protected packages (kernel, GPU driver, firmware, boot loader, core
# libraries) back to the versions of a recovery point after a bad update. Run it from a TTY.
# Installed by `pkg-update.sh apply` (before pacman runs) and `promote` as <storage>/recovery.sh
# (/var/lib/shroomery/recovery/recovery.sh);
# that copy is the one to run in an emergency. Standalone on purpose: bash, coreutils
# (sha256sum), pacman, jq, flock, and gum when present. It sources nothing and reads nothing
# under $HOME or ~/.config, so it still works when the desktop and the user's config are broken.
#
# Usage: recovery.sh [-h|--help]
#
# Flow: lists the recovery points (known-good, known-good.prev, pending), each labelled by its provenance
# (verified = promoted; a checkpoint of the installed state or a forced promote is NOT verified; a verified
# known-good.prev is listed before an unverified known-good), checks the sha256 of
# every archive of the chosen one, shows name / installed version / target version, asks, then
# runs ONE `pacman -U` over the archives whose version differs from the installed one, then
# `mkinitcpio -P` and `grub-mkconfig -o /boot/grub/grub.cfg`. Never `-dd`, never `--overwrite`.
# Not root: re-executes itself through sudo.
#
# Environment overrides (tests; a sudo-started root process gets none of them, sudo resets the environment):
#   PKG_RECOVERY_DIR    recovery storage          (default: /var/lib/shroomery/recovery)
#   PKG_PACMAN          pacman command, may hold arguments (default: pacman)
#   PKG_MKINITCPIO      mkinitcpio command        (default: mkinitcpio)
#   PKG_GRUB_MKCONFIG   grub-mkconfig command     (default: grub-mkconfig)
#   PKG_PACMAN_DBLOCK   pacman's database lock    (default: /var/lib/pacman/db.lck)
#   PKG_ASSUME_YES      set: no confirmation, and the first recovery point without asking
#   PKG_NO_GUM          set: never use gum (a numbered prompt instead)
#   PKG_NO_ELEVATE      set: never re-execute through sudo
#   PKG_SUDO            the sudo command          (default: sudo)
#
# Exit status: 0 done (or nothing to restore), 1 failed / declined / nothing to restore from,
# 2 usage, 3 another update operation or pacman is running.

RECOVERY_DIR=${PKG_RECOVERY_DIR:-/var/lib/shroomery/recovery}
GRUB_CFG=/boot/grub/grub.cfg

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() {  # fail STATUS MESSAGE...
    local rc=$1; shift
    printf 'ERROR: %s\n' "$*" >&2
    exit "$rc"
}

usage() {
    cat <<'EOF'
Usage: recovery.sh [-h|--help]

Reinstalls the protected packages (kernel, GPU driver, firmware, boot loader, core libraries)
from the archives of a recovery point, then runs mkinitcpio -P and grub-mkconfig.
Asks before it changes anything. Run it as root, from a TTY if the desktop is broken.
EOF
}

case ${1-} in
    '') ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

# --- root -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ] && [ -z "${PKG_NO_ELEVATE:-}" ]; then
    read -ra sudo_cmd <<<"${PKG_SUDO:-sudo}"
    command -v "${sudo_cmd[0]}" >/dev/null 2>&1 || fail 1 "recovery.sh needs root and ${sudo_cmd[0]} was not found; log in as root or run it with root rights. Nothing was changed."
    say "recovery.sh needs root: running it through ${sudo_cmd[0]}"
    exec "${sudo_cmd[@]}" "$(readlink -f -- "$0")" "$@"
    fail 1 "could not run ${sudo_cmd[0]}"
fi

command -v jq >/dev/null 2>&1 || fail 1 "jq is required to read the recovery manifests (pacman -S jq). Nothing was changed."
[ -d "$RECOVERY_DIR" ] || fail 1 "no recovery storage at $RECOVERY_DIR: nothing to restore from"

# --- lock: not while an update runs or pacman is busy -------------------------------------
# Same lock file and meaning as acquire_lock in pkg-lib.sh. Held on fd 200 until exit.
# An unusable lock file is only a warning: an emergency restore must not be blocked by it.
lock="$RECOVERY_DIR/lock"
if command -v flock >/dev/null 2>&1 && { { exec 200>>"$lock"; } 2>/dev/null || { exec 200<"$lock"; } 2>/dev/null; }; then
    flock -n 200 || fail 3 "another update operation is already running (lock: $lock); nothing was changed"
else
    warn "cannot take the update lock $lock; continuing without it"
fi
dblock=${PKG_PACMAN_DBLOCK:-/var/lib/pacman/db.lck}
if [ -e "$dblock" ]; then
    fail 3 "pacman is running or crashed: $dblock exists. If no pacman runs, remove that file and start again. Nothing was changed."
fi

# --- log: stdout and stderr are one stream, copied to logs/<UTC time>-restore.log ----------
# One tee for both keeps the prompts and the output in order. A log that cannot be written
# is a warning, never a reason to stop.
exec 5>&2   # the real terminal, for gum
LOG_FILE="" LOG_PID=""
log_finish() {
    local i
    [ -n "$LOG_PID" ] || return 0
    exec >/dev/null 2>&1
    for ((i = 0; i < 200; i++)); do
        kill -0 "$LOG_PID" 2>/dev/null || break
        sleep 0.05
    done
    LOG_PID=""
}
log_start() {
    local dir="$RECOVERY_DIR/logs" stamp f n=0
    if [ ! -d "$dir" ]; then
        (umask 022; mkdir -p -- "$dir") 2>/dev/null && chmod 755 -- "$dir" 2>/dev/null || { warn "cannot create $dir: going on without a log"; return 0; }
    fi
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    f="$dir/$stamp-restore.log"
    while ! (set -C; : > "$f") 2>/dev/null; do   # never reuse a log
        n=$((n + 1))
        [ "$n" -le 100 ] || { warn "cannot create a log file in $dir: going on without a log"; return 0; }
        f="$dir/$stamp-restore-$n.log"
    done
    chmod 644 -- "$f" 2>/dev/null
    LOG_FILE=$f
    trap log_finish EXIT
    # sh, not a bash subshell: an INT trap set in a bash subshell does not survive the exec of tee. Ctrl-C, a hangup
    # and TERM must not kill tee. Should it die anyway, SIGPIPE is ignored (below): writes fail with EPIPE instead of
    # killing the script, or pacman half-way through a package.
    exec > >(sh -c 'trap "" INT HUP TERM; exec tee --output-error=warn-nopipe -a -- "$1"' sh "$f" 200>&-) 2>&1
    LOG_PID=$!
    say "Log: $f"
}
# Children inherit the ignore, as in the other pkg scripts: a dead log tee never kills pacman or this script.
trap '' PIPE
log_start

# --- recovery points --------------------------------------------------------------------
P_KIND=() P_DIR=() P_TITLE=() P_DETAIL=()   # restore|pending, directory, one line, extra lines
add_point() { P_KIND+=("$1"); P_DIR+=("$2"); P_TITLE+=("$3"); P_DETAIL+=("${4-}"); }

# manifest_ok DIR: DIR/manifest.json lists packages with name, version, archive (a plain file name), sha256.
manifest_ok() {
    [ -f "$1/manifest.json" ] && jq -e '
        (.packages | type == "array") and (.packages | length > 0)
        and all(.packages[]; (.name | type == "string" and length > 0) and (.version | type == "string" and length > 0)
            and (.archive | type == "string" and length > 0 and (contains("/") | not))
            and (.sha256 | type == "string"))' "$1/manifest.json" >/dev/null 2>&1
}

# provenance DIR: how the point was made, from its manifest: "verified (promoted DATE)", "checkpoint of the
# installed state DATE, NOT verified" (apply's checkpoint) or "promoted with --force DATE, NOT verified". A manifest
# without `source`/`verified` (older) counts as a promote, verified unless forced.
provenance() {
    jq -r '((.created // "unknown") | tostring | .[0:10]) as $d
        | (if has("verified") then .verified == true else .forced != true end) as $v
        | if $v then "verified (promoted \($d))"
          elif (.source // "promote") == "checkpoint" then "checkpoint of the installed state \($d), NOT verified"
          elif .forced == true then "promoted with --force \($d), NOT verified"
          else "promoted \($d), NOT verified" end' "$1/manifest.json" 2>/dev/null
}
# verified DIR: the point's manifest says it was verified (see provenance).
verified() { jq -e 'if has("verified") then .verified == true else .forced != true end' "$1/manifest.json" >/dev/null 2>&1; }

# restore_detail DIR: what is worth knowing about a restore point.
restore_detail() {
    jq -r '"created \(.created // "unknown"), kernel \(.kernel // "unknown"), \(.packages | length) protected packages"
        + (if .forced == true then "\npromoted with --force (verify failed: \((.verify_failures // []) | join(", ")))" else "" end)' \
        "$1/manifest.json" 2>/dev/null
}

kg="$RECOVERY_DIR/known-good"
prev="$RECOVERY_DIR/known-good.prev"
kg_ok="" prev_ok=""
manifest_ok "$kg" && kg_ok=1
manifest_ok "$prev" && prev_ok=1
add_prev() { add_point restore "$prev" "known-good.prev: previous recovery point, $(provenance "$prev")" "$(restore_detail "$prev")"; }
# The verified point first: a .prev that is verified comes before a known-good that is not.
prev_first=""
if [ -n "$kg_ok" ] && [ -n "$prev_ok" ] && ! verified "$kg" && verified "$prev"; then
    prev_first=1; add_prev
fi
if [ -n "$kg_ok" ]; then
    add_point restore "$kg" "known-good: $(provenance "$kg")" "$(restore_detail "$kg")"
else
    [ ! -e "$kg" ] || warn "$kg has no usable manifest"
    # An update cut off while it swapped the checkpoint can leave the copies as .old.* / .new.*:
    # still a source for an emergency restore.
    while IFS= read -r d; do
        [ -n "$d" ] && manifest_ok "$d" || continue
        add_point restore "$d" "${d##*/}: left by an interrupted update" "$(restore_detail "$d")"
    done < <(ls -dt -- "$kg".old.* "$kg".new.* 2>/dev/null)
fi
if [ -n "$prev_ok" ] && [ -z "$prev_first" ]; then
    add_prev
fi
pend="$RECOVERY_DIR/pending"
if [ "${#P_KIND[@]}" -gt 0 ] && [ -f "$pend/manifest.json" ] && jq -e . "$pend/manifest.json" >/dev/null 2>&1; then
    # Shown so the user sees what the update changed; it restores known-good (the state that update started
    # from), else the first restore point.
    pi=0
    for i in "${!P_DIR[@]}"; do [ "${P_DIR[i]}" != "$kg" ] || pi=$i; done
    pdetail=$(jq -r '.packages[]? | [.name, (.from // "(not installed)"), (.to // "(removed)")] | @tsv' "$pend/manifest.json" 2>/dev/null \
        | while IFS=$'\t' read -r n f t; do printf '%-24s %s -> %s\n' "$n" "$f" "$t"; done)
    ptitle=$(jq -r '"pending: the update that was applied (state \(.state // "unknown"), started \(.started // "unknown"))"' "$pend/manifest.json")
    [ -n "$pdetail" ] || pdetail="no package changes recorded"
    add_point pending "${P_DIR[pi]}" "$ptitle" "$pdetail"$'\n'"choosing it restores the archives of point $((pi + 1)) (${P_TITLE[pi]%%:*})"
fi

if [ "${#P_KIND[@]}" -eq 0 ]; then
    fail 1 "no recovery point found in $RECOVERY_DIR (no usable known-good). Nothing was changed. Reinstall from an Arch ISO if the system cannot boot."
fi

say ""
say "Recovery points in $RECOVERY_DIR:"
for i in "${!P_KIND[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${P_TITLE[i]}"
    while IFS= read -r line; do
        [ -z "$line" ] || printf '       %s\n' "$line"
    done <<<"${P_DETAIL[i]}"
done
say ""

# --- prompts --------------------------------------------------------------------------------
use_gum() { [ -z "${PKG_NO_GUM:-}" ] && command -v gum >/dev/null 2>&1 && [ -t 0 ]; }

# confirm PROMPT: yes only for an explicit yes. PKG_ASSUME_YES skips the question.
confirm() {
    local ans
    [ -z "${PKG_ASSUME_YES:-}" ] || return 0
    if use_gum; then
        gum confirm --default=false "$1" >&5 2>&5
        return
    fi
    printf '%s [y/N] ' "$1"
    read -r ans || { echo; return 1; }
    case ${ans,,} in y|yes) return 0 ;; *) return 1 ;; esac
}

chosen=0
if [ "${#P_KIND[@]}" -gt 1 ] && [ -z "${PKG_ASSUME_YES:-}" ]; then
    if use_gum; then
        labels=()
        for i in "${!P_KIND[@]}"; do labels+=("$((i + 1))) ${P_TITLE[i]}"); done
        sel=$(gum choose "${labels[@]}" 2>&5) || fail 1 "cancelled; nothing was changed"
        for i in "${!labels[@]}"; do [ "${labels[i]}" = "$sel" ] && chosen=$i; done
    else
        while :; do
            printf 'Restore which point? [1-%d, 1] ' "${#P_KIND[@]}"
            read -r ans || { echo; fail 1 "no choice made; nothing was changed"; }
            ans=${ans:-1}
            if [[ $ans =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#P_KIND[@]}" ]; then
                chosen=$((ans - 1)); break
            fi
            say "Please answer with a number from 1 to ${#P_KIND[@]}."
        done
    fi
fi
src=${P_DIR[chosen]}
what=${P_TITLE[chosen]%%:*}
[ "${P_KIND[chosen]}" != pending ] || what="${src##*/} (chosen via pending)"
say "Recovery point: $what ($src)"

# --- checksums: every archive of the point, before anything else ------------------------------
say "Checking the archives..."
names=() versions=() archives=() shas=()
while IFS=$'\t' read -r n v a s; do
    names+=("$n"); versions+=("$v"); archives+=("$a"); shas+=("$s")
done < <(jq -r '.packages[] | [.name, .version, .archive, .sha256] | @tsv' "$src/manifest.json")
bad=0
for i in "${!archives[@]}"; do
    f="$src/archives/${archives[i]}"
    if [ ! -f "$f" ]; then
        say "  MISSING   ${archives[i]}"; bad=$((bad + 1)); continue
    fi
    if ! got=$(sha256sum < "$f" 2>/dev/null) || [ "${got%% *}" != "${shas[i]}" ]; then
        say "  MISMATCH  ${archives[i]} (sha256 differs from the manifest or cannot be read)"; bad=$((bad + 1))
    fi
done
if [ "$bad" -gt 0 ]; then
    fail 1 "$bad archive(s) of this recovery point failed the check; it cannot be trusted. Nothing was changed. Run recovery.sh again and pick another point if there is one."
fi
say "  all ${#archives[@]} archive(s) match their sha256"

# --- what differs from the installed system ---------------------------------------------------
installed=$(LC_ALL=C ${PKG_PACMAN:-pacman} -Q 200>&-) || fail 1 "pacman -Q failed: cannot compare with the installed versions. Nothing was changed."
declare -A inst=()
while read -r n v; do [ -z "$n" ] || inst[$n]=$v; done <<<"$installed"

files=() rows=()
same=0
for i in "${!names[@]}"; do
    cur=${inst[${names[i]}]-}
    if [ "$cur" = "${versions[i]}" ]; then same=$((same + 1)); continue; fi
    files+=("$src/archives/${archives[i]}")
    rows+=("$(printf '  %-28s %-24s %s' "${names[i]}" "${cur:-(not installed)}" "${versions[i]}")")
done

if [ "${#files[@]}" -eq 0 ]; then
    say ""
    say "All ${#names[@]} protected packages are already at the versions of this recovery point: nothing to restore."
    exit 0
fi

say ""
say "${#files[@]} package(s) will be reinstalled ($same already at the target version):"
printf '  %-28s %-24s %s\n' NAME INSTALLED TARGET
printf '%s\n' "${rows[@]}"
say ""
if ! confirm "Reinstall these ${#files[@]} package(s) with pacman -U?"; then
    say "Nothing was changed."
    exit 1
fi

# --- restore ---------------------------------------------------------------------------------
# From here Ctrl-C, a hangup (SSH drop, closed terminal) and TERM only end what is running (pacman
# handles them itself): the script goes on and reports. A child that dies of one is a failed step
# below. Its own messages may find the output gone (EPIPE, SIGPIPE is ignored); that changes nothing.
INTERRUPTED=""
trap 'INTERRUPTED=1' INT HUP TERM

say ""
say "Running pacman -U ..."
LC_ALL=C ${PKG_PACMAN:-pacman} -U --noconfirm "${files[@]}" 200>&-
rc=$?
if [ "$rc" -ne 0 ]; then
    say ""
    fail 1 "pacman -U failed (exit $rc, its message is above)${INTERRUPTED:+ after an interrupt}. The transaction may be partly applied: do not reboot. Recovery stopped: mkinitcpio and grub-mkconfig were not run, and no dependency check was skipped (recovery never uses -dd). Fix what pacman reports, or pick another recovery point, and run recovery.sh again before you reboot."
fi
say "pacman -U finished."

failed=()
say ""
say "Running mkinitcpio -P ..."
${PKG_MKINITCPIO:-mkinitcpio} -P 200>&-
rc=$?; [ "$rc" -eq 0 ] || { say "mkinitcpio -P failed (exit $rc)"; failed+=("mkinitcpio -P"); }
say ""
say "Running grub-mkconfig -o $GRUB_CFG ..."
${PKG_GRUB_MKCONFIG:-grub-mkconfig} -o "$GRUB_CFG" 200>&-
rc=$?; [ "$rc" -eq 0 ] || { say "grub-mkconfig failed (exit $rc)"; failed+=("grub-mkconfig -o $GRUB_CFG"); }

say ""
if [ "${#failed[@]}" -gt 0 ]; then
    printf 'ERROR: the packages are already restored, but %s failed. Run the failed command(s) by hand before you reboot:\n' "${failed[*]}" >&2
    for c in "${failed[@]}"; do printf '    %s\n' "$c" >&2; done
    exit 1
fi
say "Done: ${#files[@]} package(s) restored from $what. Reboot now (systemctl reboot) to run the restored versions."
if [ -e "$pend" ] || [ -L "$pend" ]; then
    say "The update's pending record is still there and blocks the next update: after the reboot, run 'pkg-update.sh discard' (in the shroomery scripts directory) as your user. It is kept as pending.discarded; known-good stays as it is."
fi
exit 0
