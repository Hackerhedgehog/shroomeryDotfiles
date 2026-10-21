#!/usr/bin/env bash
# Tests for scripts/recovery.sh. Offline: a fake pacman, stub mkinitcpio/grub-mkconfig/sudo and a
# temp storage dir, never the real /var/lib/shroomery, the real pacman database, /boot or sudo.
# known-good trees are built with checkpoint_build from pkg-lib.sh (recovery.sh itself sources nothing).
# Run: bash ~/.config/shroomery/tests/recovery.sh
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/../lib.sh"
source "$HERE/../scripts/pkg-lib.sh"
RECOVERY="$HERE/../scripts/recovery.sh"

fails=0
check() {  # check NAME EXPECTED ACTUAL
    if [ "$2" != "$3" ]; then
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}
# has NAME PATTERN TEXT: 1 when TEXT contains the fixed string PATTERN (check wants an exact value).
has() { grep -qF -- "$2" <<<"$3" && echo 1 || echo 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ORIG_PATH=$PATH

# new_env: temp dirs, every override exported, stubs, and the machine as it was when known-good was
# taken (linux 6.15.3, nvidia-open 575.64-2, linux-firmware-amd, grub 2:2.16-1). No known-good yet.
new_env() {
    env_dir=$(mktemp -d -p "$tmp")
    mkdir -p "$env_dir/recovery" "$env_dir/cache" "$env_dir/bin"
    export PKG_RECOVERY_DIR="$env_dir/recovery"
    export PKG_CACHE_DIR="$env_dir/cache"
    export PKG_PACMAN="$HERE/fakes/pacman"
    export PKG_PACMAN_CONF="$env_dir/pacman.conf"
    export PKG_PROTECTED_FILE="$env_dir/recovery-protected"   # missing = default list
    export FAKE_PACMAN_DB="$env_dir/db"
    export FAKE_PACMAN_LOG="$env_dir/pacman.log"
    export FAKE_PACMAN_ENVLOG="$env_dir/pacman.envlog"
    : > "$FAKE_PACMAN_LOG"; : > "$FAKE_PACMAN_ENVLOG"
    unset FAKE_PACMAN_EXIT FAKE_PACMAN_U_EXIT FAKE_PACMAN_U_ERR FAKE_PACMAN_DEPS
    export PKG_NO_ELEVATE=1 PKG_NO_GUM=1
    unset PKG_ASSUME_YES PKG_SUDO PKG_TEST_EUID; REC_IN=""
    export PKG_PACMAN_DBLOCK="$env_dir/no-db.lck"
    export PKG_MKINITCPIO="$env_dir/bin/mkinitcpio" PKG_GRUB_MKCONFIG="$env_dir/bin/grub-mkconfig"
    export STEPS="$env_dir/steps"; : > "$STEPS"
    for s in mkinitcpio grub-mkconfig; do
        cat > "$env_dir/bin/$s" <<STUB
#!/usr/bin/env bash
echo "$s \$* [U-calls-so-far=\$(grep -c -- '^-U ' "$FAKE_PACMAN_ENVLOG")]" >> "$STEPS"
exit \${STUB_${s//-/_}_EXIT:-0}
STUB
        chmod +x "$env_dir/bin/$s"
    done
    unset STUB_mkinitcpio_EXIT STUB_grub_mkconfig_EXIT
    set_db "linux 6.15.3.arch1-1" "nvidia-open 575.64-2" "linux-firmware-amd 20260916-1" "firefox 130-1" "grub 2:2.16-1"
}
set_db() { printf '%s\n' "$@" > "$FAKE_PACMAN_DB"; }
# mkcache: a cache file for every installed protected package (content names the package + version).
mkcache() {
    local n v
    while read -r n v; do
        [ -e "$PKG_CACHE_DIR/$n-$v-x86_64.pkg.tar.zst" ] || printf 'archive of %s %s\n' "$n" "$v" > "$PKG_CACHE_DIR/$n-$v-x86_64.pkg.tar.zst"
    done < <(protected_installed)
}
# known_good [NAME]: checkpoint the installed protected set as NAME (default known-good).
known_good() { mkcache; checkpoint_build "$PKG_RECOVERY_DIR/${1:-known-good}"; }
# bad_update: the machine after the update that went wrong.
bad_update() {
    set_db "linux 6.16.0.arch1-1" "nvidia-open 580.1-1" "linux-firmware-amd 20260916-1" "firefox 131-1" "grub 2:2.16-1"
}
# new_failed_env: known-good taken, then the bad update installed.
new_failed_env() { new_env; known_good; bad_update; }

# rec [ARG...]: run recovery.sh with REC_IN on stdin (not a terminal). Sets REC_OUT (stdout + stderr) and REC_RC.
rec() { REC_OUT=$(printf '%s' "${REC_IN-}" | bash "$RECOVERY" "$@" 2>&1); REC_RC=$?; }
ucalls() { grep -c -- '^-U ' "$FAKE_PACMAN_ENVLOG"; }
steps() { cat "$STEPS"; }

# --- no recovery point at all
new_env
rec
check "empty storage: exit 1" 1 "$REC_RC"
check "empty storage: says there is no recovery point" 1 "$(has x 'no recovery point' "$REC_OUT")"
check "empty storage: pacman -U never called" 0 "$(ucalls)"
rm -rf "$PKG_RECOVERY_DIR"
rec
check "missing storage dir: exit 1" 1 "$REC_RC"
check "missing storage dir: says there is nothing to restore from" 1 "$(has x 'nothing to restore from' "$REC_OUT")"
new_env
mkdir -p "$PKG_RECOVERY_DIR/known-good"; echo 'not json' > "$PKG_RECOVERY_DIR/known-good/manifest.json"
rec
check "corrupt manifest: exit 1" 1 "$REC_RC"
check "corrupt manifest: no recovery point" 1 "$(has x 'no recovery point' "$REC_OUT")"
check "corrupt manifest: nothing steps" "" "$(steps)"

# --- usage
new_failed_env
rec --bogus
check "unknown argument: exit 2" 2 "$REC_RC"
check "unknown argument: pacman -U never called" 0 "$(ucalls)"
rec --help
check "--help: exit 0" 0 "$REC_RC"
check "--help: shows usage" 1 "$(has x 'Usage:' "$REC_OUT")"

# --- a corrupt archive: exit 1, nothing run
new_failed_env
echo corrupted > "$PKG_RECOVERY_DIR/known-good/archives/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst"   # same inode as the cache file: fine, temp dir
export PKG_ASSUME_YES=1
rec
check "corrupt archive: exit 1" 1 "$REC_RC"
check "corrupt archive: names the archive" 1 "$(has x 'linux-6.15.3.arch1-1-x86_64.pkg.tar.zst' "$REC_OUT")"
check "corrupt archive: says checksum mismatch" 1 "$(has x 'MISMATCH' "$REC_OUT")"
check "corrupt archive: pacman -U never called" 0 "$(ucalls)"
check "corrupt archive: no mkinitcpio/grub" "" "$(steps)"
check "corrupt archive: no table shown" 0 "$(has x 'will be reinstalled' "$REC_OUT")"
new_failed_env
rm "$PKG_RECOVERY_DIR/known-good/archives/grub-2:2.16-1-x86_64.pkg.tar.zst"   # an UNCHANGED package: still checked
export PKG_ASSUME_YES=1
rec
check "missing archive of an unchanged package: exit 1" 1 "$REC_RC"
check "missing archive: says MISSING and names it" "1 1" "$(has x MISSING "$REC_OUT") $(has x 'grub-2:2.16-1-x86_64.pkg.tar.zst' "$REC_OUT")"
check "missing archive: pacman -U never called" 0 "$(ucalls)"
new_failed_env
rm "$PKG_RECOVERY_DIR/known-good/archives/grub-2:2.16-1-x86_64.pkg.tar.zst"
jq '.packages[0].archive = "../escape.pkg.tar.zst"' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m.json" && cp "$env_dir/m.json" "$PKG_RECOVERY_DIR/known-good/manifest.json"
export PKG_ASSUME_YES=1
rec
check "archive name with a slash: not a recovery point" "1 0" "$REC_RC $(ucalls)"

# --- happy path: downgrade the two changed protected packages
new_failed_env
sed -i 's/^grub .*/grub 2:2.15-1/' "$FAKE_PACMAN_DB"        # an epoch version that differs too
export PKG_ASSUME_YES=1
rec
check "downgrade: exit 0" 0 "$REC_RC"
check "downgrade: pacman -U called once" 1 "$(ucalls)"
u=$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")
kg="$PKG_RECOVERY_DIR/known-good/archives"
check "downgrade: -U has the linux archive" 1 "$(has x " $kg/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst" "$u")"
check "downgrade: -U has the nvidia archive" 1 "$(has x " $kg/nvidia-open-575.64-2-x86_64.pkg.tar.zst" "$u")"
check "downgrade: -U has the epoch grub archive (colon kept)" 1 "$(has x " $kg/grub-2:2.16-1-x86_64.pkg.tar.zst" "$u")"
check "downgrade: -U lacks the unchanged firmware archive" 0 "$(has x 'linux-firmware-amd' "$u")"
check "downgrade: -U runs with LC_ALL=C" 1 "$(has x 'LC_ALL=C' "$u")"
check "downgrade: --noconfirm only after recovery.sh confirmed" 1 "$(has x -- '-U --noconfirm' "$u")"
check "downgrade: never -dd, -d, --nodeps, --overwrite" 0 "$(grep -cE -- ' -dd? | --nodeps| --overwrite|--force' <<<"$u")"
check "downgrade: every pacman call has LC_ALL=C" 0 "$(grep -vc 'LC_ALL=C$' "$FAKE_PACMAN_ENVLOG")"
check "downgrade: mkinitcpio -P after the -U" "mkinitcpio -P [U-calls-so-far=1]" "$(grep '^mkinitcpio' "$STEPS")"
check "downgrade: grub-mkconfig -o after mkinitcpio" "grub-mkconfig -o /boot/grub/grub.cfg [U-calls-so-far=1]" "$(grep '^grub-mkconfig' "$STEPS")"
check "downgrade: mkinitcpio before grub-mkconfig" "mkinitcpio grub-mkconfig" "$(cut -d' ' -f1 "$STEPS" | paste -sd' ')"
check "downgrade: table lists linux current -> target" 1 "$(grep -cE '^ +linux +6\.16\.0\.arch1-1 +6\.15\.3\.arch1-1' <<<"$REC_OUT")"
check "downgrade: table lists the epoch grub" 1 "$(grep -cE '^ +grub +2:2\.15-1 +2:2\.16-1' <<<"$REC_OUT")"
check "downgrade: unchanged package not in the table" 0 "$(grep -cE '^ +linux-firmware-amd ' <<<"$REC_OUT")"
check "downgrade: tells to reboot" 1 "$(has x 'reboot' "$REC_OUT")"
log=$(ls "$PKG_RECOVERY_DIR"/logs/*-restore.log 2>/dev/null)
check "downgrade: one log named <UTC time>-restore.log" 1 "$(grep -cE '/[0-9]{8}T[0-9]{6}Z-restore\.log$' <<<"$log")"
check "downgrade: log holds the table and the steps" "1 1" "$(grep -c 'will be reinstalled' "$log") $(grep -c 'mkinitcpio' "$log")"
check "downgrade: log dir 755, log 644" "755 644" "$(stat -c %a "$PKG_RECOVERY_DIR/logs") $(stat -c %a "$log")"

# --- confirmation by reading stdin (no PKG_ASSUME_YES)
new_failed_env
REC_IN=$'n\n'; rec
check "answer n: exit 1" 1 "$REC_RC"
check "answer n: nothing was called" "0|" "$(ucalls)|$(steps)"
check "answer n: says nothing was changed" 1 "$(has x 'Nothing was changed' "$REC_OUT")"
REC_IN=''; rec
check "no answer at all (EOF): treated as no" "1 0" "$REC_RC $(ucalls)"
REC_IN=$'maybe\n'; rec
check "answer that is not yes: treated as no" "1 0" "$REC_RC $(ucalls)"
REC_IN=$'y\n'; rec
check "answer y: exit 0, restored" "0 1" "$REC_RC $(ucalls)"
check "answer y: asked once, no --noconfirm before" 1 "$(has x 'Reinstall these' "$REC_OUT")"

# --- the fallback prompt works with gum absent from PATH
new_failed_env
farm="$env_dir/nogum"; mkdir -p "$farm"
for c in bash sh env jq sha256sum awk date mkdir cat tee ls chmod flock stat dirname basename readlink tr sed grep head rm sort uname sleep id cut paste wc printf; do
    p=$(command -v "$c" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$farm/$c"
done
check "gum-less PATH really has no gum" 1 "$(PATH=$farm command -v gum >/dev/null 2>&1; echo $?)"
unset PKG_NO_GUM
REC_OUT=$(printf 'y\n' | PATH=$farm "$farm/bash" "$RECOVERY" 2>&1); REC_RC=$?
check "gum absent: exit 0, restored" "0 1" "$REC_RC $(ucalls)"
# gum present but stdin not a terminal: never used
cat > "$farm/gum" <<STUB
#!$farm/bash
echo called >> "$env_dir/gum.called"
exit 1
STUB
chmod +x "$farm/gum"
: > "$FAKE_PACMAN_ENVLOG"
REC_OUT=$(printf 'y\n' | PATH=$farm "$farm/bash" "$RECOVERY" 2>&1); REC_RC=$?
check "gum present, stdin not a terminal: gum not used, fallback prompt works" "0 1 no" "$REC_RC $(ucalls) $([ -e "$env_dir/gum.called" ] && echo yes || echo no)"
export PKG_NO_GUM=1

# --- pacman -U fails: exit 1, message shown, no mkinitcpio
new_failed_env
export PKG_ASSUME_YES=1
FAKE_PACMAN_U_EXIT=1 FAKE_PACMAN_U_ERR='error: failed to prepare transaction (could not satisfy dependencies)' rec
check "pacman -U failure: exit 1" 1 "$REC_RC"
check "pacman -U failure: pacman's message shown" 1 "$(has x 'could not satisfy dependencies' "$REC_OUT")"
check "pacman -U failure: no mkinitcpio, no grub" "" "$(steps)"
check "pacman -U failure: -U was tried once, without -dd" "1 0" "$(ucalls) $(grep -c -- ' -dd' "$FAKE_PACMAN_ENVLOG")"
check "pacman -U failure: says it was not forced" 1 "$(has x 'never uses -dd' "$REC_OUT")"
check "pacman -U failure: says it may be partly applied, not to reboot, to run recovery.sh again" "1 1 1" \
    "$(has x 'partly applied' "$REC_OUT") $(has x 'do not reboot' "$REC_OUT") $(has x 'run recovery.sh again' "$REC_OUT")"

# --- glibc / systemd moved: packages outside the patterns that pin them to one version (lib32-glibc needs
# glibc=<exact>) are part of the recovery point, so the one pacman -U does not break them. The fake -U rejects a
# transaction that breaks an exact dependency of an installed package outside it, as pacman does.
glibc_env() {  # glibc_env WITH_CLOSURE: known-good taken (with or without the dependency data), then glibc moved
    new_env
    set_db "linux 6.15.3.arch1-1" "glibc 2.44-1" "lib32-glibc 2.44-1" "systemd 262-1" "systemd-sysvcompat 262-1" "firefox 130-1"
    printf 'lib32-glibc glibc=2.44\nsystemd-sysvcompat systemd=262\nfirefox glibc>=2.40\n' > "$env_dir/deps"
    [ "$1" = yes ] && export FAKE_PACMAN_DEPS="$env_dir/deps"
    known_good
    export FAKE_PACMAN_DEPS="$env_dir/deps"
    set_db "linux 6.15.3.arch1-1" "glibc 2.45-1" "lib32-glibc 2.45-1" "systemd 263-1" "systemd-sysvcompat 263-1" "firefox 131-1"
    printf 'lib32-glibc glibc=2.45\nsystemd-sysvcompat systemd=263\nfirefox glibc>=2.40\n' > "$env_dir/deps"
}
glibc_env yes
check "glibc moved: known-good holds lib32-glibc and systemd-sysvcompat" "lib32-glibc systemd-sysvcompat" \
    "$(jq -r '.packages[].name' "$PKG_RECOVERY_DIR/known-good/manifest.json" | grep -E '^(lib32-glibc|systemd-sysvcompat)$' | paste -sd' ')"
export PKG_ASSUME_YES=1
rec
u=$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")
check "glibc moved, with the closure: the restore passes, exit 0" "0 1" "$REC_RC $(ucalls)"
check "glibc moved, with the closure: -U holds glibc and lib32-glibc together" "1 1 1 1" \
    "$(has x 'archives/glibc-2.44-1-x86_64' "$u") $(has x 'lib32-glibc-2.44-1-x86_64' "$u") $(has x 'archives/systemd-262-1-x86_64' "$u") $(has x 'systemd-sysvcompat-262-1-x86_64' "$u")"
glibc_env no
export PKG_ASSUME_YES=1
rec
check "glibc moved, without the closure: the fake -U rejects the restore (exit 1, nothing else run)" "1 1 " "$REC_RC $(ucalls) $(steps)"
check "glibc moved, without the closure: pacman names the broken dependency" 1 "$(has x "breaks dependency 'glibc=2.45' required by lib32-glibc" "$REC_OUT")"

# --- Ctrl-C while pacman -U runs: the script goes on (pacman handles INT itself) and finishes the steps.
# The stub sends INT to its own process group, i.e. recovery.sh, its log tee and itself, as a terminal does;
# setsid gives the run a group of its own so the test shell is not in it.
new_failed_env
cat > "$env_dir/bin/intpacman" <<STUB
#!/usr/bin/env bash
if [ "\$1" = -U ]; then
    trap : INT; kill -INT 0; sleep 0.3
    echo "\$*" >> "$FAKE_PACMAN_ENVLOG"; echo "pacman finished after the interrupt"; exit 0
fi
exec "$HERE/fakes/pacman" "\$@"
STUB
chmod +x "$env_dir/bin/intpacman"
REC_OUT=$(PKG_ASSUME_YES=1 PKG_PACMAN="$env_dir/bin/intpacman" setsid -w bash "$RECOVERY" </dev/null 2>&1); REC_RC=$?
check "Ctrl-C during pacman -U: the run goes on to the end, exit 0" "0 1" "$REC_RC $(has x 'pacman finished after the interrupt' "$REC_OUT")"
check "Ctrl-C during pacman -U: mkinitcpio and grub-mkconfig still ran" 2 "$(wc -l < "$STEPS")"

# --- HUP during pacman -U (SSH drop, closed terminal): the same, the script keeps going.
new_failed_env
cat > "$env_dir/bin/huppacman" <<STUB
#!/usr/bin/env bash
if [ "\$1" = -U ]; then
    trap : HUP; kill -HUP 0; sleep 0.3
    echo "\$*" >> "$FAKE_PACMAN_ENVLOG"; echo "pacman finished after the hangup"; exit 0
fi
exec "$HERE/fakes/pacman" "\$@"
STUB
chmod +x "$env_dir/bin/huppacman"
REC_OUT=$(PKG_ASSUME_YES=1 PKG_PACMAN="$env_dir/bin/huppacman" setsid -w bash "$RECOVERY" </dev/null 2>&1); REC_RC=$?
check "HUP during pacman -U: the run goes on to the end, exit 0, both steps ran" "0 2" "$REC_RC $(wc -l < "$STEPS")"

# --- the log tee dies during pacman -U (killed outright): pacman finishes, the script goes on and exits with the real status.
# The stub kills the tee that is a child of recovery.sh, waits, then does its work and writes to the dead pipe.
new_failed_env
cat > "$env_dir/bin/teekill" <<STUB
#!/usr/bin/env bash
if [ "\$1" = -U ]; then
    pkill -KILL -P "\$PPID" -x tee; sleep 0.3
    echo "pacman status line after the tee died"
    echo "\$*" >> "$FAKE_PACMAN_ENVLOG"; echo done > "$env_dir/u.done"
    exit \${TEEKILL_EXIT:-0}
fi
exec "$HERE/fakes/pacman" "\$@"
STUB
chmod +x "$env_dir/bin/teekill"
REC_OUT=$(PKG_ASSUME_YES=1 PKG_PACMAN="$env_dir/bin/teekill" bash "$RECOVERY" </dev/null 2>&1); REC_RC=$?
check "tee dies during pacman -U: pacman reached its end" "done" "$(cat "$env_dir/u.done" 2>/dev/null)"
check "tee dies during pacman -U: exit 0 (not 141), mkinitcpio and grub-mkconfig ran" "0 2" "$REC_RC $(wc -l < "$STEPS")"
new_failed_env
rm -f "$env_dir/u.done"
REC_OUT=$(TEEKILL_EXIT=1 PKG_ASSUME_YES=1 PKG_PACMAN="$env_dir/bin/teekill" bash "$RECOVERY" </dev/null 2>&1); REC_RC=$?
check "tee dies, pacman -U fails: exit 1 (the real status), no mkinitcpio" "1 0" "$REC_RC $(wc -l < "$STEPS")"

# --- mkinitcpio / grub-mkconfig fail after a good -U: loud, exit 1, packages are restored
new_failed_env
export PKG_ASSUME_YES=1
STUB_mkinitcpio_EXIT=3 rec
check "mkinitcpio failure: exit 1" 1 "$REC_RC"
check "mkinitcpio failure: says the packages ARE restored and what to re-run" "1 1" "$(has x 'already restored' "$REC_OUT") $(has x 'mkinitcpio -P' "$REC_OUT")"
check "mkinitcpio failure: grub-mkconfig still ran" 1 "$(grep -c '^grub-mkconfig' "$STEPS")"
new_failed_env
export PKG_ASSUME_YES=1
STUB_grub_mkconfig_EXIT=2 rec
check "grub-mkconfig failure: exit 1" 1 "$REC_RC"
check "grub-mkconfig failure: names the command to re-run" 1 "$(has x 'grub-mkconfig -o /boot/grub/grub.cfg' "$REC_OUT")"

# --- nothing to restore
new_env
known_good
export PKG_ASSUME_YES=1
rec
check "already at known-good: exit 0" 0 "$REC_RC"
check "already at known-good: says nothing to restore" 1 "$(has x 'nothing to restore' "$REC_OUT")"
check "already at known-good: no pacman -U, no mkinitcpio, no grub" "0|" "$(ucalls)|$(steps)"

# --- pacman -Q fails: cannot compare, exit 1, nothing run
new_failed_env
export PKG_ASSUME_YES=1
FAKE_PACMAN_EXIT=1 rec
check "pacman -Q failure: exit 1, nothing run" "1 0" "$REC_RC $(ucalls)"

# --- a package not installed any more is reinstalled
new_failed_env
sed -i '/^nvidia-open /d' "$FAKE_PACMAN_DB"
export PKG_ASSUME_YES=1
rec
check "removed package: exit 0 and in the -U" "0 1" "$REC_RC $(has x nvidia-open-575.64-2 "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
check "removed package: table says not installed" 1 "$(grep -cE '^ +nvidia-open +\(not installed\) +575\.64-2' <<<"$REC_OUT")"

# --- points: known-good, previous, pending (selected by number on stdin)
new_env
known_good known-good.prev                       # state A: the older known-good
set_db "linux 6.15.4.arch1-1" "nvidia-open 575.70-1" "linux-firmware-amd 20260916-1" "firefox 130-1" "grub 2:2.16-1"
known_good                                       # state B: known-good
set_db "linux 6.16.0.arch1-1" "nvidia-open 580.1-1" "linux-firmware-amd 20260916-1" "firefox 131-1" "grub 2:2.16-1"   # state C: installed
mkdir -p "$PKG_RECOVERY_DIR/pending"
cat > "$PKG_RECOVERY_DIR/pending/manifest.json" <<'JSON'
{"started":"2026-10-17T10:00:00Z","finished":"2026-10-17T10:05:00Z","mode":"normal","pacman_exit":0,"state":"awaiting-verification",
 "packages":[{"name":"linux","from":"6.15.4.arch1-1","to":"6.16.0.arch1-1"},{"name":"nvidia-open","from":"575.70-1","to":"580.1-1"},{"name":"newpkg","from":null,"to":"1-1"}]}
JSON
REC_IN=$'1\nn\n'; rec
check "points: three listed" "1 1 1" "$(grep -cE '^ +1\) known-good' <<<"$REC_OUT") $(grep -cE '^ +2\) known-good\.prev' <<<"$REC_OUT") $(grep -cE '^ +3\) pending' <<<"$REC_OUT")"
check "points: known-good is labelled by its provenance (an older manifest: a verified promote)" 1 "$(grep -cE '^ +1\) known-good: verified \(promoted [0-9]{4}-[0-9]{2}-[0-9]{2}\)$' <<<"$REC_OUT")"
check "points: previous is labelled as the previous point, with its provenance" 1 "$(grep -cE '^ +2\) known-good\.prev: previous recovery point, verified \(promoted [0-9-]{10}\)$' <<<"$REC_OUT")"
check "points: pending shows from -> to" "1 1 1" "$(grep -cE 'linux +6\.15\.4\.arch1-1 -> 6\.16\.0\.arch1-1' <<<"$REC_OUT") $(grep -cE 'nvidia-open +575\.70-1 -> 580\.1-1' <<<"$REC_OUT") $(grep -cE 'newpkg +\(not installed\) -> 1-1' <<<"$REC_OUT")"
check "points: pending shows its state" 1 "$(has x 'awaiting-verification' "$REC_OUT")"
check "points: a choice of 1 then n changes nothing" "1 0" "$REC_RC $(ucalls)"
REC_IN=$'1\ny\n'; rec
check "known-good chosen: restores state B" "0 1 1" "$REC_RC $(ucalls) $(has x 'linux-6.15.4.arch1-1-x86_64.pkg.tar.zst' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
: > "$FAKE_PACMAN_ENVLOG"; : > "$STEPS"
REC_IN=$'3\ny\n'; rec
check "pending chosen: restores the known-good archives (state B)" "0 1 1 0" "$REC_RC $(ucalls) $(has x 'linux-6.15.4.arch1-1-x86_64.pkg.tar.zst' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")") $(has x 'linux-6.15.3' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
: > "$FAKE_PACMAN_ENVLOG"; : > "$STEPS"
REC_IN=$'2\ny\n'; rec
check "previous chosen: restores state A" "0 1 1" "$REC_RC $(ucalls) $(has x 'known-good.prev/archives/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
: > "$FAKE_PACMAN_ENVLOG"
REC_IN=$'9\n0\nx\n2\nn\n'; rec
check "invalid choices are asked again" "1 0 1" "$REC_RC $(ucalls) $(has x 'Reinstall these' "$REC_OUT")"
: > "$FAKE_PACMAN_ENVLOG"
REC_IN=''; rec
check "no choice at all (EOF): exit 1, nothing run" "1 0" "$REC_RC $(ucalls)"
export PKG_ASSUME_YES=1
rec
check "PKG_ASSUME_YES with several points: the first (known-good) without asking" "0 1 1" "$REC_RC $(ucalls) $(has x 'linux-6.15.4.arch1-1' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
unset PKG_ASSUME_YES
# the previous generation's archive is checked too
: > "$FAKE_PACMAN_ENVLOG"
echo broken > "$PKG_RECOVERY_DIR/known-good.prev/archives/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst"
REC_IN=$'2\ny\n'; rec
check "previous chosen with a corrupt archive: exit 1, nothing run" "1 0 1" "$REC_RC $(ucalls) $(has x MISMATCH "$REC_OUT")"
# a pending record without a usable known-good has nothing to restore
rm -rf "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.prev"
REC_IN=''; rec
check "pending only: no recovery point to restore" "1 0 1" "$REC_RC $(ucalls) $(has x 'no recovery point' "$REC_OUT")"

# --- forced promotion is labelled
new_failed_env
jq '. + {forced: true, verify_failures: ["gpu", "services"]}' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m.json" && cp "$env_dir/m.json" "$PKG_RECOVERY_DIR/known-good/manifest.json"
REC_IN=$'n\n'; rec
check "forced known-good: labelled with the failed checks, not verified" "1 1 1" "$(has x 'promoted with --force' "$REC_OUT") $(has x 'verify failed: gpu, services' "$REC_OUT") $(grep -cE '^ +1\) known-good: promoted with --force [0-9-]{10}, NOT verified$' <<<"$REC_OUT")"
new_failed_env
REC_IN=$'n\n'; rec
check "normal known-good: not labelled forced" 0 "$(has x 'promoted with --force' "$REC_OUT")"

# --- provenance (C2): an unverified checkpoint is never called verified; a verified .prev is listed first
new_env
known_good known-good.prev
set_db "linux 6.15.4.arch1-1" "nvidia-open 575.70-1" "linux-firmware-amd 20260916-1" "firefox 130-1" "grub 2:2.16-1"
mkcache; checkpoint_build "$PKG_RECOVERY_DIR/known-good" checkpoint     # apply's checkpoint of an unverified state
jq '.created = "2026-10-18T09:00:00Z"' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m.json" && cp "$env_dir/m.json" "$PKG_RECOVERY_DIR/known-good/manifest.json"
jq '. + {source: "promote", verified: true, created: "2026-10-01T09:00:00Z"}' "$PKG_RECOVERY_DIR/known-good.prev/manifest.json" > "$env_dir/m.json" && cp "$env_dir/m.json" "$PKG_RECOVERY_DIR/known-good.prev/manifest.json"
set_db "linux 6.16.0.arch1-1" "nvidia-open 580.1-1" "linux-firmware-amd 20260916-1" "firefox 131-1" "grub 2:2.16-1"
mkdir -p "$PKG_RECOVERY_DIR/pending"
echo '{"started":"2026-10-18T10:00:00Z","state":"failed","packages":[{"name":"linux","from":"6.15.4.arch1-1","to":"6.16.0.arch1-1"}]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
REC_IN=$'1\nn\n'; rec
check "provenance: the verified .prev is listed first" 1 "$(grep -cE '^ +1\) known-good\.prev: previous recovery point, verified \(promoted 2026-10-01\)$' <<<"$REC_OUT")"
check "provenance: the checkpoint is called NOT verified, never verified" "1 0" \
    "$(grep -cE '^ +2\) known-good: checkpoint of the installed state 2026-10-18, NOT verified$' <<<"$REC_OUT") $(grep -c 'known-good: verified' <<<"$REC_OUT")"
check "provenance: pending says it restores known-good (point 2)" 1 "$(has x 'restores the archives of point 2 (known-good)' "$REC_OUT")"
: > "$FAKE_PACMAN_ENVLOG"
REC_IN=$'3\ny\n'; rec
check "provenance: pending chosen restores known-good, not the .prev listed first" "0 1 0" \
    "$REC_RC $(has x 'recovery/known-good/archives/linux-6.15.4.arch1-1' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")") $(has x 'known-good.prev/' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
: > "$FAKE_PACMAN_ENVLOG"
PKG_ASSUME_YES=1 rec
check "provenance: PKG_ASSUME_YES takes the verified point" "0 1" "$REC_RC $(has x 'known-good.prev/archives/linux-6.15.3.arch1-1' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
check "after a restore with a pending record: points to pkg-update.sh discard" 1 "$(has x 'pkg-update.sh discard' "$REC_OUT")"
rm -rf "$PKG_RECOVERY_DIR/pending"
PKG_ASSUME_YES=1 rec
check "after a restore without a pending record: no discard hint" "0 0" "$REC_RC $(has x 'pkg-update.sh discard' "$REC_OUT")"
# a discarded record is not a pending one: no discard hint either, and not offered as a point
mkdir -p "$PKG_RECOVERY_DIR/pending.discarded"; echo '{"state":"failed","packages":[]}' > "$PKG_RECOVERY_DIR/pending.discarded/manifest.json"
PKG_ASSUME_YES=1 rec
check "a discarded record: no discard hint, not a point" "0 0 0" "$REC_RC $(has x 'pkg-update.sh discard' "$REC_OUT") $(has x 'pending' "$(grep -E '^ +[0-9]\) ' <<<"$REC_OUT")")"
# a .prev that is a checkpoint too: known-good stays first
new_env
known_good known-good.prev
jq '. + {source: "checkpoint", verified: false}' "$PKG_RECOVERY_DIR/known-good.prev/manifest.json" > "$env_dir/m.json" && cp "$env_dir/m.json" "$PKG_RECOVERY_DIR/known-good.prev/manifest.json"
set_db "linux 6.15.4.arch1-1" "nvidia-open 575.70-1" "linux-firmware-amd 20260916-1" "firefox 130-1" "grub 2:2.16-1"
known_good
bad_update
REC_IN=$'1\nn\n'; rec
check "provenance: verified known-good first, checkpoint .prev second and NOT verified" "1 1" \
    "$(grep -cE '^ +1\) known-good: verified' <<<"$REC_OUT") $(grep -cE '^ +2\) known-good\.prev: previous recovery point, checkpoint of the installed state [0-9-]{10}, NOT verified$' <<<"$REC_OUT")"

# --- known-good missing, an interrupted update left copies
new_failed_env
mv "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.old.4242"
REC_IN=$'y\n'; rec
check "interrupted swap: copy listed as left by an interrupted update" "1 1" "$(has x 'known-good.old.4242' "$REC_OUT") $(has x 'interrupted' "$REC_OUT")"
check "interrupted swap: restore from it works" "0 1" "$REC_RC $(ucalls)"
check "interrupted swap: the -U names that copy's archives" 1 "$(has x 'known-good.old.4242/archives/linux-6.15.3.arch1-1' "$(grep -- '^-U ' "$FAKE_PACMAN_ENVLOG")")"
new_failed_env
cp -al "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.old.77"
REC_IN=$'n\n'; rec
check "known-good present: .old.* leftovers are debris, not offered" 0 "$(has x 'known-good.old.77' "$REC_OUT")"
new_failed_env
mv "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.new.9"
cp -al "$PKG_RECOVERY_DIR/known-good.new.9" "$PKG_RECOVERY_DIR/known-good.old.8"
rm "$PKG_RECOVERY_DIR/known-good.old.8/manifest.json"; echo 'garbage' > "$PKG_RECOVERY_DIR/known-good.old.8/manifest.json"   # (cp -al shares the inode)
REC_IN=$'n\n'; rec
check "interrupted swap: a copy with an unreadable manifest is skipped, a readable one listed" "1 0" "$(has x 'known-good.new.9' "$REC_OUT") $(has x 'known-good.old.8' "$REC_OUT")"

# --- locking: pacman's db.lck and another run holding the lock
new_failed_env
export PKG_ASSUME_YES=1
: > "$PKG_PACMAN_DBLOCK"
rec
check "db.lck present: exit 3, nothing run" "3 0" "$REC_RC $(ucalls)"
check "db.lck present: message names it" 1 "$(has x "$PKG_PACMAN_DBLOCK" "$REC_OUT")"
rm -f "$PKG_PACMAN_DBLOCK"
REC_OUT=$( ( exec 9>>"$PKG_RECOVERY_DIR/lock"; flock -n 9 || exit 99; printf '' | bash "$RECOVERY" 9>&- 2>&1 ) ); REC_RC=$?
check "another run holds <storage>/lock: exit 3, nothing run" "3 0" "$REC_RC $(ucalls)"
check "lock held: message says another run is active" 1 "$(has x 'already running' "$REC_OUT")"
rec
check "lock released: runs" "0 1" "$REC_RC $(ucalls)"

# --- logging never blocks a restore
new_failed_env
export PKG_ASSUME_YES=1
echo "not a dir" > "$PKG_RECOVERY_DIR/logs"
rec
check "logs/ unusable: warns and still restores" "0 1 1" "$REC_RC $(ucalls) $(has x 'without a log' "$REC_OUT")"
new_failed_env
export PKG_ASSUME_YES=1
mkdir -p "$PKG_RECOVERY_DIR/logs"
rec; rec
check "two runs in one second: two distinct logs" 2 "$(ls "$PKG_RECOVERY_DIR/logs" | wc -l)"

# --- elevation: not root re-executes through sudo (stubbed), env overrides do not travel by themselves
if [ "$EUID" != 0 ]; then
    new_failed_env
    cat > "$env_dir/bin/sudo" <<STUB
#!/usr/bin/env bash
echo "\$*" > "$env_dir/sudo.args"
exit 0
STUB
    chmod +x "$env_dir/bin/sudo"
    unset PKG_NO_ELEVATE
    export PKG_SUDO="$env_dir/bin/sudo"
    rec
    check "not root: re-executes through PKG_SUDO with the script's real path" "$(readlink -f "$RECOVERY")" "$(cat "$env_dir/sudo.args" 2>/dev/null)"
    check "not root: exit status is the sudo command's, nothing run here" "0 0" "$REC_RC $(ucalls)"
    export PKG_SUDO="$env_dir/bin/no-such-sudo"
    rec
    check "not root, no sudo: exit 1 with a message, nothing run" "1 0 1" "$REC_RC $(ucalls) $(has x 'sudo' "$REC_OUT")"
    export PKG_NO_ELEVATE=1
    unset PKG_SUDO
else
    echo "SKIP elevation tests (running as root)"
fi

# --- no dependency on lib.sh, pkg-lib.sh or the user's config
check "recovery.sh sources no other file" 0 "$(grep -cE '^[[:space:]]*(source|\.)[[:space:]]' "$RECOVERY")"
check "recovery.sh does not mention lib.sh, ~/.config or \$HOME" 0 "$(grep -v '^[[:space:]]*#' "$RECOVERY" | grep -cE 'lib\.sh|\.config|\$HOME|\$\{HOME')"
new_failed_env
export PKG_ASSUME_YES=1
home_probe="$env_dir/home"; mkdir -p "$home_probe"
REC_OUT=$(printf '' | HOME="$home_probe/none" XDG_CONFIG_HOME="$home_probe/none" bash "$RECOVERY" 2>&1); REC_RC=$?
check "works with an unusable HOME and no config" "0 1" "$REC_RC $(ucalls)"

# --- syntax
check "bash -n recovery.sh" 0 "$(bash -n "$RECOVERY" >/dev/null 2>&1; echo $?)"

PATH=$ORIG_PATH
if [ "$fails" -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
