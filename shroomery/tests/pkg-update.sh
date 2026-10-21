#!/usr/bin/env bash
# Tests for scripts/pkg-lib.sh and scripts/pkg-update.sh. Offline: a fake pacman
# and a temp storage dir, never the real /var/lib/shroomery or pacman database.
# Run: bash ~/.config/shroomery/tests/pkg-update.sh
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/../lib.sh"
source "$HERE/../scripts/pkg-lib.sh"
PKG_UPDATE="$HERE/../scripts/pkg-update.sh"

fails=0
check() {  # check NAME EXPECTED ACTUAL
    if [ "$2" != "$3" ]; then
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# new_env: a fresh temp dir with every override exported and the default fake
# package database. Sets $env_dir.
new_env() {
    env_dir=$(mktemp -d -p "$tmp")
    mkdir -p "$env_dir/recovery" "$env_dir/cache"
    export PKG_RECOVERY_DIR="$env_dir/recovery"
    export PKG_CACHE_DIR="$env_dir/cache"
    export PKG_PACMAN="$HERE/fakes/pacman"
    export PKG_PACMAN_CONF="$env_dir/pacman.conf"
    export PKG_PROTECTED_FILE="$env_dir/recovery-protected"   # missing = default list
    export FAKE_PACMAN_DB="$env_dir/db"
    export FAKE_PACMAN_LOG="$env_dir/pacman.log"
    unset FAKE_PACMAN_EXIT FAKE_PACMAN_DEPS
    # Never elevate for real: no root needed, and a stray elevate() fails instead of calling pkexec.
    export PKG_NO_ELEVATE=1 PKG_PKEXEC=false
    export PKG_PACMAN_DBLOCK="$env_dir/no-db.lck"
    export PKG_CACHE_KEEP_FILE="$env_dir/cache-keep"
    unset PKG_CACHE_KEEP PKG_PROTECTED_PATTERNS PKG_USER_HOME PKG_TEST_EUID
    cat > "$FAKE_PACMAN_DB" <<'DB'
linux 6.15.3.arch1-1
nvidia-open 575.64-2
linux-firmware-amd 20260916-1
firefox 130-1
grub 2:2.16-1
DB
}
# known_good_from_installed: record the current protected set as known-good.
known_good_from_installed() {
    mkdir -p "$PKG_RECOVERY_DIR/known-good"
    manifest_json known-good | write_atomic "$PKG_RECOVERY_DIR/known-good/manifest.json"
}
status_json() { "$PKG_UPDATE" status; }

# --- protected_patterns
new_env
check "default patterns first" linux "$(protected_patterns | head -n 1)"
check "default patterns count" 16 "$(protected_patterns | wc -l)"
printf 'linux\n\n# comment\n  zzz*  \n' > "$PKG_PROTECTED_FILE"
check "file patterns (blank/comment skipped, trimmed)" "linux zzz*" "$(protected_patterns | paste -sd' ')"

# --- protected_installed
new_env
check "protected set" "grub 2:2.16-1
linux 6.15.3.arch1-1
linux-firmware-amd 20260916-1
nvidia-open 575.64-2" "$(protected_installed)"
check "firefox not protected" 0 "$(protected_installed | grep -c '^firefox ')"
printf 'linux\nnothing-like-this*\n' > "$PKG_PROTECTED_FILE"
check "pattern matching nothing adds nothing" "linux 6.15.3.arch1-1" "$(protected_installed)"
printf 'linux\n' > "$PKG_PROTECTED_FILE"
check "exact pattern does not glob-extend" "linux 6.15.3.arch1-1" "$(protected_installed)"

# --- protected_installed: the closure over exact (=) versioned reverse dependencies
# A restore of glibc alone breaks lib32-glibc (it depends on glibc=<that exact version>), so such a package belongs
# to the set; transitively, and only for `=` constraints (=X and =X-REL), never >=, <=, <, >.
new_env
export FAKE_PACMAN_DEPS="$env_dir/deps"
cat >> "$FAKE_PACMAN_DB" <<'DB'
glibc 2.44-1
lib32-glibc 2.44-1
lib32-chain 1.0-1
systemd 262-1
systemd-sysvcompat 262-1
greedy 5-1
loose 1-1
DB
cat > "$FAKE_PACMAN_DEPS" <<'DEPS'
lib32-glibc glibc=2.44
lib32-chain lib32-glibc=2.44-1  bash
systemd-sysvcompat systemd=262
greedy glibc>=2.40  systemd<=263  linux<7  grub>1
loose firefox=130-1
firefox glibc
DEPS
pi=$(protected_installed)
check "closure: lib32-glibc pulled in by glibc=X" 1 "$(grep -c '^lib32-glibc 2.44-1$' <<<"$pi")"
check "closure: transitively, lib32-chain by lib32-glibc=X-REL" 1 "$(grep -c '^lib32-chain 1.0-1$' <<<"$pi")"
check "closure: systemd-sysvcompat by systemd=262" 1 "$(grep -c '^systemd-sysvcompat 262-1$' <<<"$pi")"
check "closure: >=, <=, < and > do not count" 0 "$(grep -c '^greedy ' <<<"$pi")"
check "closure: an exact dependency on an unprotected package does not count" 0 "$(grep -c -E '^(loose|firefox) ' <<<"$pi")"
check "closure: the whole set, sorted" "glibc 2.44-1
grub 2:2.16-1
lib32-chain 1.0-1
lib32-glibc 2.44-1
linux 6.15.3.arch1-1
linux-firmware-amd 20260916-1
nvidia-open 575.64-2
systemd 262-1
systemd-sysvcompat 262-1" "$pi"
check "closure: the manifest lists the added packages too" 9 "$(manifest_json known-good | jq '.packages | length')"
check "closure: the queries run with LC_ALL=C" 0 "$(FAKE_PACMAN_ENVLOG="$env_dir/envlog" protected_installed >/dev/null; grep -E '^-Qi?( |$)' "$env_dir/envlog" | grep -vc 'LC_ALL=C$')"
# a closure member without an archive is missing like any protected package
for p in $(protected_installed | awk '{ print $1 "-" $2 }'); do : > "$PKG_CACHE_DIR/$p-x86_64.pkg.tar.zst"; done
rm "$PKG_CACHE_DIR"/lib32-chain-*
check "closure: a member without an archive is reported missing" "lib32-chain 1.0-1" "$(missing_archives)"
checkpoint_build "$env_dir/cp" 2>"$env_dir/err"; rc=$?
check "closure: checkpoint_build refuses it, naming it" "1 1" "$rc $(grep -c 'lib32-chain 1.0-1' "$env_dir/err")"
# pacman -Qi failing is an error, never a set without its dependents
cat > "$env_dir/qi-fails" <<STUB
#!/usr/bin/env bash
case "\$1" in -Qi) echo "error: boom" >&2; exit 1 ;; esac
exec "$HERE/fakes/pacman" "\$@"
STUB
chmod +x "$env_dir/qi-fails"
out=$(PKG_PACMAN="$env_dir/qi-fails" protected_installed 2>"$env_dir/err"); rc=$?
check "closure: pacman -Qi failing fails, prints nothing" "1 " "$rc $out"
check "closure: says pacman -Qi failed" 1 "$(grep -c 'pacman -Qi' "$env_dir/err")"
unset FAKE_PACMAN_DEPS

# --- manifest_json
new_env
m=$(manifest_json known-good)
check "manifest valid json" true "$(jq -e . <<<"$m" >/dev/null 2>&1 && echo true || echo false)"
check "manifest installed count" 5 "$(jq '.installed|length' <<<"$m")"
check "manifest packages count" 4 "$(jq '.packages|length' <<<"$m")"
check "manifest kernel" "$(uname -r)" "$(jq -r '.kernel' <<<"$m")"
check "manifest patterns copied" 16 "$(jq '.patterns|length' <<<"$m")"
check "manifest created is iso time" 1 "$(jq -r '.created' <<<"$m" | grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$')"
check "manifest epoch version kept" "2:2.16-1" "$(jq -r '.packages[]|select(.name=="grub").version' <<<"$m")"
check "manifest archive empty until task 2" "" "$(jq -r '.packages[]|select(.name=="grub").archive' <<<"$m")"
check "manifest sha256 empty until task 2" "" "$(jq -r '.packages[]|select(.name=="grub").sha256' <<<"$m")"
check "manifest installed has firefox" 130-1 "$(jq -r '.installed[]|select(.name=="firefox").version' <<<"$m")"

# --- write_atomic
new_env
echo hello | write_atomic "$env_dir/out.txt"
check "write_atomic content" hello "$(cat "$env_dir/out.txt")"
check "write_atomic leaves no temp" 1 "$(ls "$env_dir" | grep -c '^out.txt')"
echo again | write_atomic "$env_dir/out.txt"
check "write_atomic replaces" again "$(cat "$env_dir/out.txt")"

# --- status
new_env
s=$(status_json)
check "status no storage: known_good null" null "$(jq -c '.known_good' <<<"$s")"
check "status no storage: pending null" null "$(jq -c '.pending' <<<"$s")"
check "status no storage: matches false" false "$(jq -c '.matches' <<<"$s")"

known_good_from_installed
s=$(status_json)
check "status known_good kernel" "$(uname -r)" "$(jq -r '.known_good.kernel' <<<"$s")"
check "status known_good has created" true "$(jq '.known_good.created|length>0' <<<"$s")"
check "status matches when unchanged" true "$(jq -c '.matches' <<<"$s")"
echo "firefox 131-1" >> "$FAKE_PACMAN_DB"; sed -i '/^firefox 130-1$/d' "$FAKE_PACMAN_DB"
check "status ignores non-protected changes" true "$(status_json | jq -c '.matches')"
sed -i 's/^nvidia-open .*/nvidia-open 580.1-1/' "$FAKE_PACMAN_DB"
check "status differs on protected version" false "$(status_json | jq -c '.matches')"
sed -i 's/^nvidia-open .*/nvidia-open 575.64-2/' "$FAKE_PACMAN_DB"
echo "mesa 25.0-1" >> "$FAKE_PACMAN_DB"
check "status differs on new protected package" false "$(status_json | jq -c '.matches')"
sed -i '/^mesa /d' "$FAKE_PACMAN_DB"
sed -i '/^grub /d' "$FAKE_PACMAN_DB"
check "status differs on removed protected package" false "$(status_json | jq -c '.matches')"

new_env
mkdir -p "$PKG_RECOVERY_DIR/pending"
echo '{"state":"awaiting-verification","started":"2026-10-17T10:00:00Z","mode":"normal"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
s=$(status_json)
check "status pending state" awaiting-verification "$(jq -r '.pending.state' <<<"$s")"
check "status pending started" 2026-10-17T10:00:00Z "$(jq -r '.pending.started' <<<"$s")"
check "status pending only state+started+changed" "changed started state" "$(jq -r '.pending|keys|join(" ")' <<<"$s")"
check "status pending without known-good: matches false" false "$(jq -c '.matches' <<<"$s")"

new_env
mkdir -p "$PKG_RECOVERY_DIR/known-good"
echo 'not json' > "$PKG_RECOVERY_DIR/known-good/manifest.json"
check "status corrupt manifest: known_good null" null "$(status_json | jq -c '.known_good')"

# --- a failing pacman -Q is an error, never an empty result
new_env
export FAKE_PACMAN_EXIT=1
out=$(protected_installed 2>/dev/null); rc=$?
check "protected_installed fails when pacman fails" 1 "$rc"
check "protected_installed prints nothing on failure" "" "$out"
out=$(manifest_json known-good 2>/dev/null); rc=$?
check "manifest_json fails when pacman fails" 1 "$rc"
check "manifest_json prints no JSON on failure" "" "$out"
check "failure names pacman on stderr" 1 "$(manifest_json known-good 2>&1 >/dev/null | grep -c 'pacman -Q failed')"
out=$("$PKG_UPDATE" status 2>/dev/null); rc=$?
check "status fails when pacman fails" 1 "$rc"
check "status prints nothing on failure" "" "$out"
unset FAKE_PACMAN_EXIT

# --- lib.sh paths survive an exported override
new_env
check "lib.sh keeps PKG_CACHE_DIR override" "$env_dir/cache" "$(bash -c "source '$HERE/../lib.sh'; echo \$PKG_CACHE_DIR")"
check "lib.sh RECOVERY_DIR default" /var/lib/shroomery/recovery "$(bash -c "source '$HERE/../lib.sh'; echo \$RECOVERY_DIR")"
check "lib.sh CACHE_KEEP_FILE" "$HOME/.config/shroomery/settings/cache-keep" "$(bash -c "source '$HERE/../lib.sh'; echo \$CACHE_KEEP_FILE")"

# --- dispatcher
new_env
"$PKG_UPDATE" bogus >/dev/null 2>&1; check "unknown subcommand exits 2" 2 "$?"
"$PKG_UPDATE" >/dev/null 2>&1; check "no subcommand exits 2" 2 "$?"
check "usage on stderr only" "" "$("$PKG_UPDATE" bogus 2>/dev/null)"

# --- fake pacman
new_env
check "fake -Q name" "linux 6.15.3.arch1-1" "$($PKG_PACMAN -Q linux)"
$PKG_PACMAN -Q nope >/dev/null 2>&1; check "fake -Q missing exits 1" 1 "$?"
$PKG_PACMAN -Syu --noconfirm; check "fake other flags exit 0" 0 "$?"
check "fake logs other flags" "-Syu --noconfirm" "$(cat "$FAKE_PACMAN_LOG")"
FAKE_PACMAN_EXIT=3 $PKG_PACMAN -Syu; check "fake honors FAKE_PACMAN_EXIT" 3 "$?"
FAKE_PACMAN_EXIT=3 $PKG_PACMAN -Q >/dev/null 2>&1; check "fake -Q honors FAKE_PACMAN_EXIT" 3 "$?"
check "fake -Q prints nothing on failure" "" "$(FAKE_PACMAN_EXIT=3 $PKG_PACMAN -Q 2>&1)"

# --- archive_for: exact NAME-VERSION-<arch>.pkg.tar.zst, epoch colon literal
new_env
c="$PKG_CACHE_DIR"
touch "$c/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst" "$c/linux-headers-6.15.3.arch1-1-x86_64.pkg.tar.zst" \
      "$c/grub-2:2.16-1-x86_64.pkg.tar.zst" "$c/linux-firmware-20260916-1-any.pkg.tar.zst" \
      "$c/linux-firmware-amd-20260916-1-any.pkg.tar.zst" "$c/linux-6.15-1-x86_64.pkg.tar.zst" \
      "$c/mesa-25.0-1-x86_64.pkg.tar.zst.sig" "$c/glibc-2.40-1-x86_64.pkg.tar"
check "archive_for plain" "$c/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst" "$(archive_for linux 6.15.3.arch1-1)"
check "archive_for epoch keeps colon" "$c/grub-2:2.16-1-x86_64.pkg.tar.zst" "$(archive_for grub 2:2.16-1)"
check "archive_for arch any" "$c/linux-firmware-20260916-1-any.pkg.tar.zst" "$(archive_for linux-firmware 20260916-1)"
check "archive_for family member" "$c/linux-firmware-amd-20260916-1-any.pkg.tar.zst" "$(archive_for linux-firmware-amd 20260916-1)"
archive_for linux 6.15 >/dev/null 2>&1; check "archive_for version prefix is not a match" 1 "$?"
archive_for linux 6.15.3 >/dev/null 2>&1; check "archive_for partial version no match" 1 "$?"
archive_for mesa 25.0-1 >/dev/null 2>&1; check "archive_for ignores .sig" 1 "$?"
archive_for glibc 2.40-1 >/dev/null 2>&1; check "archive_for only .pkg.tar.zst" 1 "$?"
archive_for nope 1-1 >/dev/null 2>&1; check "archive_for missing exits 1" 1 "$?"
rm "$c/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst"
archive_for linux 6.15.3.arch1-1 >/dev/null 2>&1; check "archive_for name prefix of linux-headers: no wrong file" 1 "$?"
check "archive_for missing prints nothing" "" "$(archive_for linux 6.15.3.arch1-1 2>/dev/null)"
rm -rf "$c"; PKG_CACHE_DIR="$env_dir/no-such-cache"
archive_for linux 1-1 >/dev/null 2>&1; check "archive_for missing cache dir exits 1" 1 "$?"

# --- same_fs
new_env
check "same_fs same dir" 0 "$(same_fs "$env_dir" "$env_dir/cache"; echo $?)"
check "same_fs nonexistent path fails" 1 "$(same_fs "$env_dir" "$env_dir/nope" 2>/dev/null; echo $?)"
if [ -d /dev/shm ] && [ "$(stat -c %d /dev/shm)" != "$(stat -c %d "$tmp")" ]; then
    check "same_fs different filesystems" 1 "$(same_fs /dev/shm "$env_dir"; echo $?)"
else
    echo "SKIP same_fs different filesystems (/dev/shm is on the temp dir's filesystem)"
fi

# --- checkpoint_build
# mkcache: a cache file for every installed protected package.
mkcache() {
    local n v
    while read -r n v; do
        printf 'archive of %s %s\n' "$n" "$v" > "$PKG_CACHE_DIR/$n-$v-x86_64.pkg.tar.zst"
    done < <(protected_installed)
}
new_env
mkcache
touch "$PKG_CACHE_DIR/linux-headers-6.15.3.arch1-1-x86_64.pkg.tar.zst" "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst.sig"
target="$PKG_RECOVERY_DIR/cp-test"
checkpoint_build "$target"; check "checkpoint_build exits 0" 0 "$?"
check "checkpoint archives count" 4 "$(ls "$target/archives" | wc -l)"
for f in "$target"/archives/*; do
    check "checkpoint hardlink inode $(basename "$f")" "$(stat -c %i "$PKG_CACHE_DIR/$(basename "$f")")" "$(stat -c %i "$f")"
done
check "checkpoint epoch archive present" 1 "$(ls "$target/archives" | grep -c '^grub-2:2.16-1-x86_64.pkg.tar.zst$')"
check "checkpoint no stray headers/sig" 0 "$(ls "$target/archives" | grep -c 'headers\|\.sig')"
m=$(cat "$target/manifest.json")
check "checkpoint manifest valid json" true "$(jq -e . <<<"$m" >/dev/null 2>&1 && echo true || echo false)"
check "checkpoint grub archive name" "grub-2:2.16-1-x86_64.pkg.tar.zst" "$(jq -r '.packages[]|select(.name=="grub").archive' <<<"$m")"
check "checkpoint grub sha256" "$(sha256sum < "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst" | cut -d' ' -f1)" "$(jq -r '.packages[]|select(.name=="grub").sha256' <<<"$m")"
check "checkpoint all sha256 filled" 0 "$(jq '[.packages[]|select(.sha256|test("^[0-9a-f]{64}$")|not)]|length' <<<"$m")"
check "checkpoint all archives filled" 0 "$(jq '[.packages[]|select(.archive=="")]|length' <<<"$m")"
check "checkpoint manifest keeps installed" 5 "$(jq '.installed|length' <<<"$m")"
check "checkpoint leaves no temp dirs" "cp-test" "$(ls "$PKG_RECOVERY_DIR")"
check "checkpoint manifest has no tmp file" "archives manifest.json" "$(ls "$target" | paste -sd' ')"
mv "$target" "$PKG_RECOVERY_DIR/known-good"
known_good_matches; check "known_good_matches after promote" 0 "$?"
sed -i 's/^nvidia-open .*/nvidia-open 580.1-1/' "$FAKE_PACMAN_DB"
known_good_matches; check "known_good_matches false on version change" 1 "$?"
sed -i 's/^nvidia-open .*/nvidia-open 575.64-2/' "$FAKE_PACMAN_DB"
echo "mesa 25.0-1" >> "$FAKE_PACMAN_DB"
known_good_matches; check "known_good_matches false on extra protected package" 1 "$?"
sed -i '/^mesa /d' "$FAKE_PACMAN_DB"
echo "firefox 131-1" >> "$FAKE_PACMAN_DB"
known_good_matches; check "known_good_matches ignores non-protected" 0 "$?"
rm "$PKG_RECOVERY_DIR/known-good/manifest.json"
known_good_matches; check "known_good_matches false without manifest" 1 "$?"
FAKE_PACMAN_EXIT=1 known_good_matches 2>/dev/null; check "known_good_matches fails when pacman fails" 1 "$?"

# replacing an existing checkpoint dir
new_env
mkcache
mkdir -p "$PKG_RECOVERY_DIR/known-good/archives"; echo old > "$PKG_RECOVERY_DIR/known-good/stale"
checkpoint_build "$PKG_RECOVERY_DIR/known-good"; check "checkpoint_build over existing exits 0" 0 "$?"
check "checkpoint_build over existing replaces" "archives manifest.json" "$(ls "$PKG_RECOVERY_DIR/known-good" | paste -sd' ')"
check "checkpoint_build over existing leaves nothing else" "known-good" "$(ls "$PKG_RECOVERY_DIR")"

# one archive missing: exit 1, named on stderr, no directory
new_env
mkcache
rm "$PKG_CACHE_DIR/nvidia-open-575.64-2-x86_64.pkg.tar.zst"
rm "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst"
target="$PKG_RECOVERY_DIR/cp-test"
err=$(checkpoint_build "$target" 2>&1 >/dev/null); rc=$?
check "missing archive exits 1" 1 "$rc"
check "missing archive names nvidia-open" 1 "$(grep -cx 'nvidia-open 575.64-2' <<<"$err")"
check "missing archive names grub with epoch" 1 "$(grep -cx 'grub 2:2.16-1' <<<"$err")"
check "present archive not reported" 0 "$(grep -c '^linux ' <<<"$err")"
check "missing archive leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# split family: 13 linux-firmware members, one missing
new_env
for m in "" -amd -intel -nvidia -radeon -atheros -broadcom -cirrus -mediatek -other -realtek -whence -marvell; do
    echo "linux-firmware$m 20260916-1" >> "$FAKE_PACMAN_DB"
done
check "family test db: 13 members" 13 "$(protected_installed | grep -c '^linux-firmware')"
mkcache
rm "$PKG_CACHE_DIR/linux-firmware-realtek-20260916-1-x86_64.pkg.tar.zst"
target="$PKG_RECOVERY_DIR/known-good"
err=$(checkpoint_build "$target" 2>&1 >/dev/null); rc=$?
check "family member missing exits 1" 1 "$rc"
check "family member named" 1 "$(grep -cx 'linux-firmware-realtek 20260916-1' <<<"$err")"
check "family: only the missing member listed" 1 "$(grep -c '^linux-firmware' <<<"$err")"
check "family: no partial checkpoint" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# pacman failure: no checkpoint, no directory
new_env
mkcache
FAKE_PACMAN_EXIT=1 checkpoint_build "$PKG_RECOVERY_DIR/cp-test" >/dev/null 2>&1; check "checkpoint_build fails when pacman fails" 1 "$?"
check "pacman failure leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# no protected package installed: refuse rather than write an empty checkpoint
new_env
printf 'firefox 130-1\n' > "$FAKE_PACMAN_DB"
checkpoint_build "$PKG_RECOVERY_DIR/cp-test" >/dev/null 2>&1; check "checkpoint_build refuses empty protected set" 1 "$?"
check "empty protected set leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# cache on a different filesystem: clear message, nothing created
if [ -d /dev/shm ] && [ "$(stat -c %d /dev/shm)" != "$(stat -c %d "$tmp")" ]; then
    new_env
    shm=$(mktemp -d -p /dev/shm)
    PKG_CACHE_DIR="$shm"; mkcache
    err=$(checkpoint_build "$PKG_RECOVERY_DIR/cp-test" 2>&1 >/dev/null); rc=$?
    check "different filesystem exits 1" 1 "$rc"
    check "different filesystem message" 1 "$(grep -c 'different filesystem' <<<"$err")"
    check "different filesystem leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"
    rm -rf "$shm"
else
    echo "SKIP checkpoint_build different filesystem"
fi

# interruption (TERM) mid-build leaves no directory and no tmp dir
new_env
mkcache
fakebin="$env_dir/bin"; mkdir -p "$fakebin"
printf '#!/bin/sh\ntouch "%s/started"\nsleep 1\nexec /usr/bin/sha256sum "$@"\n' "$env_dir" > "$fakebin/sha256sum"
chmod +x "$fakebin/sha256sum"
PATH="$fakebin:$PATH" bash -c "source '$HERE/../lib.sh'; source '$HERE/../scripts/pkg-lib.sh'; checkpoint_build '$PKG_RECOVERY_DIR/cp-test'" >/dev/null 2>&1 &
bgpid=$!
for _ in $(seq 50); do [ -e "$env_dir/started" ] && break; sleep 0.1; done
check "interrupt test: build started" 1 "$([ -e "$env_dir/started" ] && echo 1 || echo 0)"
kill -TERM "$bgpid"; wait "$bgpid"; rc=$?
check "TERM during build exits non-zero" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "TERM during build leaves nothing" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# --- checkpoint_build hardening (review round 1)
# a failing jq must not produce an empty manifest reported as success
for mode in "exit 1" "exit 0"; do
    new_env
    mkcache
    fakebin="$env_dir/bin"; mkdir -p "$fakebin"
    # fails (or prints nothing) only for the manifest-filling call (it has --arg map)
    printf '#!/bin/sh\ncase " $* " in *" map "*) %s ;; esac\nexec /usr/bin/jq "$@"\n' "$mode" > "$fakebin/jq"
    chmod +x "$fakebin/jq"
    PATH="$fakebin:$PATH" checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; rc=$?
    check "jq filling manifest ($mode) exits 1" 1 "$rc"
    check "jq filling manifest ($mode) leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"
done
# ... and an existing checkpoint survives that failure
new_env
mkcache
checkpoint_build "$PKG_RECOVERY_DIR/known-good" || echo "FAIL setup checkpoint"
before=$(cd "$PKG_RECOVERY_DIR/known-good" && find . -printf '%p %i %s\n' | LC_ALL=C sort)
fakebin="$env_dir/bin"; mkdir -p "$fakebin"
printf '#!/bin/sh\ncase " $* " in *" map "*) exit 1 ;; esac\nexec /usr/bin/jq "$@"\n' > "$fakebin/jq"; chmod +x "$fakebin/jq"
PATH="$fakebin:$PATH" checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1
check "failed rebuild after tmp created: existing intact" "$before" "$(cd "$PKG_RECOVERY_DIR/known-good" && find . -printf '%p %i %s\n' | LC_ALL=C sort)"
check "failed rebuild after tmp created: nothing else left" "known-good" "$(ls "$PKG_RECOVERY_DIR")"

# a failed rebuild (missing archive) leaves an existing TARGET_DIR fully intact
new_env
mkcache
checkpoint_build "$PKG_RECOVERY_DIR/known-good" || echo "FAIL setup checkpoint"
before=$(cd "$PKG_RECOVERY_DIR/known-good" && find . -printf '%p %i %s\n' | LC_ALL=C sort)
inode=$(stat -c %i "$PKG_RECOVERY_DIR/known-good/archives/grub-2:2.16-1-x86_64.pkg.tar.zst")
rm "$PKG_CACHE_DIR/mesa-25.0-1-x86_64.pkg.tar.zst" 2>/dev/null
echo "mesa 25.0-1" >> "$FAKE_PACMAN_DB"   # newly installed protected package without an archive
checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; check "failed rebuild exits 1" 1 "$?"
check "failed rebuild: same files and inodes" "$before" "$(cd "$PKG_RECOVERY_DIR/known-good" && find . -printf '%p %i %s\n' | LC_ALL=C sort)"
check "failed rebuild: archive inode unchanged" "$inode" "$(stat -c %i "$PKG_RECOVERY_DIR/known-good/archives/grub-2:2.16-1-x86_64.pkg.tar.zst")"
check "failed rebuild: nothing else left" "known-good" "$(ls "$PKG_RECOVERY_DIR")"

# missing cache directory has its own message
new_env
rm -rf "$PKG_CACHE_DIR"
err=$(checkpoint_build "$PKG_RECOVERY_DIR/cp-test" 2>&1 >/dev/null); rc=$?
check "missing cache dir exits 1" 1 "$rc"
check "missing cache dir message" 1 "$(grep -c 'cache dir not found' <<<"$err")"
check "missing cache dir is not a filesystem error" 0 "$(grep -c 'different filesystem' <<<"$err")"
check "missing cache dir leaves no directory" "" "$(ls -A "$PKG_RECOVERY_DIR")"

# restrictive umask: directories 755, manifest 644
new_env
mkcache
( umask 077; checkpoint_build "$PKG_RECOVERY_DIR/cp-test" ) || echo "FAIL umask build"
check "umask 077: target dir mode" 755 "$(stat -c %a "$PKG_RECOVERY_DIR/cp-test")"
check "umask 077: archives dir mode" 755 "$(stat -c %a "$PKG_RECOVERY_DIR/cp-test/archives")"
check "umask 077: manifest mode" 644 "$(stat -c %a "$PKG_RECOVERY_DIR/cp-test/manifest.json")"

# a caller's own TERM/INT trap still runs after the build cleaned up, and its trap is restored on success
for sig in TERM; do   # INT is ignored by async children of a non-interactive shell, so only TERM can be sent here
    new_env
    mkcache
    fakebin="$env_dir/bin"; mkdir -p "$fakebin"
    printf '#!/bin/sh\ntouch "%s/started"\nsleep 1\nexec /usr/bin/sha256sum "$@"\n' "$env_dir" > "$fakebin/sha256sum"
    chmod +x "$fakebin/sha256sum"
    PATH="$fakebin:$PATH" bash -c "source '$HERE/../lib.sh'; source '$HERE/../scripts/pkg-lib.sh'
        trap 'echo caller-$sig > \"$env_dir/caller\"; exit 7' $sig
        checkpoint_build '$PKG_RECOVERY_DIR/cp-test'" >/dev/null 2>&1 &
    bgpid=$!
    for _ in $(seq 50); do [ -e "$env_dir/started" ] && break; sleep 0.1; done
    kill -s "$sig" "$bgpid"; wait "$bgpid"; rc=$?
    check "caller $sig trap ran" "caller-$sig" "$(cat "$env_dir/caller" 2>/dev/null)"
    check "caller $sig trap decides the exit status" 7 "$rc"
    check "caller $sig trap: build cleaned up first" "" "$(ls -A "$PKG_RECOVERY_DIR")"
done
new_env
mkcache
out=$(trap 'echo mine' TERM; checkpoint_build "$PKG_RECOVERY_DIR/cp-test" >/dev/null 2>&1; trap -p TERM)
check "caller trap restored after a successful build" "trap -- 'echo mine' SIGTERM" "$out"
out=$(checkpoint_build "$PKG_RECOVERY_DIR/cp-test2" >/dev/null 2>&1; trap -p TERM)
check "no caller trap: none left behind" "" "$out"

# pkg-update.sh checkpoint (internal subcommand)
new_env
mkcache
"$PKG_UPDATE" checkpoint "$PKG_RECOVERY_DIR/cp-test" >/dev/null 2>&1; check "checkpoint subcommand exits 0" 0 "$?"
check "checkpoint subcommand builds manifest" 4 "$(jq '.packages|length' "$PKG_RECOVERY_DIR/cp-test/manifest.json")"
"$PKG_UPDATE" checkpoint >/dev/null 2>&1; check "checkpoint subcommand needs a directory" 2 "$?"
rm "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst"
rm -rf "$PKG_RECOVERY_DIR/cp-test"
"$PKG_UPDATE" checkpoint "$PKG_RECOVERY_DIR/cp-test" >/dev/null 2>&1; check "checkpoint subcommand propagates failure" 1 "$?"

# --- pacman_conf_without_ignores
new_env
cat > "$env_dir/src.conf" <<'CONF'
[options]
HoldPkg     = pacman glibc
#IgnorePkg  = commented
IgnorePkg   = linux linux-headers
  IgnorePkg=nvidia
	IgnoreGroup = nvidia-utils
DBPath      = /var/lib/pacman/
IgnorePkgFoo = kept
Include = /etc/pacman.d/mirrorlist
CONF
src_sum=$(sha256sum < "$env_dir/src.conf")
pacman_conf_without_ignores "$env_dir/src.conf" "$env_dir/out.conf"; check "conf strip exits 0" 0 "$?"
check "conf strip drops Ignore lines only" "[options]
HoldPkg     = pacman glibc
#IgnorePkg  = commented
DBPath      = /var/lib/pacman/
IgnorePkgFoo = kept
Include = /etc/pacman.d/mirrorlist" "$(cat "$env_dir/out.conf")"
check "conf strip leaves SRC alone" "$src_sum" "$(sha256sum < "$env_dir/src.conf")"
printf 'DBPath = /x\nIgnorePkg = a\nHoldPkg = b' > "$env_dir/nonl.conf"
pacman_conf_without_ignores "$env_dir/nonl.conf" "$env_dir/nonl.out"
printf 'DBPath = /x\nHoldPkg = b' | cmp -s - "$env_dir/nonl.out"
check "conf strip: byte-identical otherwise (no trailing newline kept)" 0 "$?"
pacman_conf_without_ignores "$env_dir/missing.conf" "$env_dir/out2.conf" 2>/dev/null; check "conf strip: missing SRC fails" 1 "$?"
check "conf strip: no DEST left for missing SRC" no "$([ -e "$env_dir/out2.conf" ] && echo yes || echo no)"

# --- check_updates (update check against a temp DB; never the real one)
# new_check_env: new_env plus a fake "real" pacman db and a private runtime dir.
new_check_env() {
    new_env
    export XDG_RUNTIME_DIR="$env_dir/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    export PKG_DBPATH="$env_dir/realdb"
    mkdir -p "$PKG_DBPATH/local" "$PKG_DBPATH/sync"
    echo core > "$PKG_DBPATH/sync/core.db"
    export FAKE_PACMAN_UPDATES="$env_dir/updates"
    unset FAKE_PACMAN_SY_EXIT FAKE_PACMAN_QU_EXIT FAKE_PACMAN_QU_ERR
    printf '[options]\nIgnorePkg = linux nvidia\n' > "$PKG_PACMAN_CONF"
    cat > "$FAKE_PACMAN_UPDATES" <<'UPD'
firefox 130-1 -> 131-1
grub 2:2.15-1 -> 2:2.16-1
linux 6.15.3.arch1-1 -> 7.2.6.arch2-1 ignored
UPD
    checkdb="$XDG_RUNTIME_DIR/shroomery/pkg-check-db"
}
real_before() { find "$PKG_DBPATH" -printf '%p %T@ %s\n' | sort; }

new_check_env
before=$(real_before)
out=$(check_updates 2>"$env_dir/err"); check "check exits 0" 0 "$?"
check "check: JSON shape" '["count","held_count","refreshed","updates"]' "$(jq -c 'keys' <<<"$out")"
check "check: update fields" '["held","name","new","old"]' "$(jq -c '.updates[0]|keys' <<<"$out")"
check "check: count is non-held only" 2 "$(jq .count <<<"$out")"
check "check: held_count" 1 "$(jq .held_count <<<"$out")"
check "check: refreshed false" false "$(jq .refreshed <<<"$out")"
check "check: all updates listed, held flagged" "firefox 130-1 131-1 false
grub 2:2.15-1 2:2.16-1 false
linux 6.15.3.arch1-1 7.2.6.arch2-1 true" "$(jq -r '.updates[]|"\(.name) \(.old) \(.new) \(.held)"' <<<"$out")"
check "check: no stderr on success" "" "$(cat "$env_dir/err")"
check "check: -Sy only on the temp DB" "-Sy config=$PKG_PACMAN_CONF dbpath=$checkdb" "$(grep '^-Sy' "$FAKE_PACMAN_LOG")"
check "check: every pacman call uses the temp DB" "" "$(grep -v "dbpath=$checkdb\$" "$FAKE_PACMAN_LOG")"
check "check: normal run uses the real config" 1 "$(grep -c "^-Qu config=$PKG_PACMAN_CONF dbpath=" "$FAKE_PACMAN_LOG")"
check "check: temp DB mode" 700 "$(stat -c %a "$XDG_RUNTIME_DIR/shroomery")"
check "check: temp DB local links to the real local" "$PKG_DBPATH/local" "$(readlink "$checkdb/local")"
check "check: sync dbs seeded from the real ones" core "$(cat "$checkdb/sync/core.db" 2>/dev/null)"
check "check: real DB untouched" "$before" "$(real_before)"
check "check: no temp config left behind" "pkg-check-db pkg-check.lock" "$(ls "$XDG_RUNTIME_DIR/shroomery" | paste -sd' ')"

# a normal run reuses the temp DB (the sentinel survives)
touch "$checkdb/sentinel"
out=$(check_updates 2>/dev/null)
check "check: normal run reuses the temp DB" yes "$([ -e "$checkdb/sentinel" ] && echo yes || echo no)"
# --refresh deletes the temp DB first
out=$(check_updates --refresh 2>/dev/null); check "check --refresh exits 0" 0 "$?"
check "check --refresh removes the old temp DB" no "$([ -e "$checkdb/sentinel" ] && echo yes || echo no)"
check "check --refresh: refreshed true" true "$(jq .refreshed <<<"$out")"
check "check --refresh: forced full download (no seeded sync dbs)" no "$([ -e "$checkdb/sync/core.db" ] && echo yes || echo no)"
check "check --refresh: local link recreated" "$PKG_DBPATH/local" "$(readlink "$checkdb/local")"
check "check --refresh: results unchanged" 2 "$(jq .count <<<"$out")"

# --system: stripped config, nothing held
new_check_env
out=$(check_updates --system 2>/dev/null); check "check --system exits 0" 0 "$?"
check "check --system: count" 3 "$(jq .count <<<"$out")"
check "check --system: held_count" 0 "$(jq .held_count <<<"$out")"
check "check --system: nothing held" false "$(jq 'any(.updates[]; .held)' <<<"$out")"
check "check --system: only the stripped config is used" 0 "$(grep -c "^-Qu config=$PKG_PACMAN_CONF " "$FAKE_PACMAN_LOG")"
check "check --system: one -Qu" 1 "$(grep -c '^-Qu' "$FAKE_PACMAN_LOG")"
check "check --system: the real config file is untouched" "[options]
IgnorePkg = linux nvidia" "$(cat "$PKG_PACMAN_CONF")"
out=$(check_updates --system --refresh 2>/dev/null)
check "check --system --refresh (flag order free)" "true 3" "$(jq -r '"\(.refreshed) \(.count)"' <<<"$out")"

# no updates: pacman -Qu exits 1 with no output
new_check_env
rm "$FAKE_PACMAN_UPDATES"
out=$(check_updates 2>"$env_dir/err"); check "check: no updates is success" 0 "$?"
check "check: no updates JSON" '{"updates":[],"count":0,"held_count":0,"refreshed":false}' "$(jq -c . <<<"$out")"
check "check: no updates, no stderr" "" "$(cat "$env_dir/err")"
# only held updates
printf 'linux 6.15.3.arch1-1 -> 7.2.6.arch2-1 ignored\n' > "$FAKE_PACMAN_UPDATES"
out=$(check_updates 2>/dev/null)
check "check: only held" "0 1" "$(jq -r '"\(.count) \(.held_count)"' <<<"$out")"

# failures must never look like "no updates"
new_check_env
export FAKE_PACMAN_SY_EXIT=1
out=$(check_updates 2>"$env_dir/err"); rc=$?
check "check: -Sy failure exits non-zero" 1 "$rc"
check "check: -Sy failure prints no JSON" "" "$out"
case "$(cat "$env_dir/err")" in *"unable to lock database"*) r=ok ;; *) r="$(cat "$env_dir/err")" ;; esac
check "check: -Sy failure explains on stderr (with pacman's message)" ok "$r"
unset FAKE_PACMAN_SY_EXIT
export FAKE_PACMAN_QU_EXIT=2
out=$(check_updates 2>"$env_dir/err"); rc=$?
check "check: -Qu failure (status 2) exits non-zero" 1 "$rc"
check "check: -Qu failure prints no JSON" "" "$out"
check "check: -Qu failure explains on stderr" 1 "$(grep -c . "$env_dir/err")"
unset FAKE_PACMAN_QU_EXIT
rm "$FAKE_PACMAN_UPDATES"
export FAKE_PACMAN_QU_ERR="error: failed to initialize alpm library"
out=$(check_updates 2>"$env_dir/err"); rc=$?
check "check: -Qu status 1 with an error message is a failure" 1 "$rc"
check "check: ... and prints no JSON" "" "$out"
unset FAKE_PACMAN_QU_ERR
printf 'garbage line\n' > "$FAKE_PACMAN_UPDATES"
out=$(check_updates 2>/dev/null); rc=$?
check "check: unparsable -Qu output is a failure" 1 "$rc"
check "check: ... and prints no JSON (unparsable)" "" "$out"

# the check must not follow a planted symlink or use someone else's directory
new_check_env
mkdir "$env_dir/elsewhere"
ln -s "$env_dir/elsewhere" "$XDG_RUNTIME_DIR/shroomery"
out=$(check_updates 2>/dev/null); rc=$?
check "check: refuses a symlinked runtime dir" 1 "$rc"
check "check: ... and writes nothing through it" "" "$(ls -A "$env_dir/elsewhere")"

# the CLI
new_check_env
out=$("$PKG_UPDATE" check 2>/dev/null); check "pkg-update.sh check exits 0" 0 "$?"
check "pkg-update.sh check: count" 2 "$(jq .count <<<"$out")"
out=$("$PKG_UPDATE" check --system --refresh 2>/dev/null)
check "pkg-update.sh check --system --refresh" "3 true" "$(jq -r '"\(.count) \(.refreshed)"' <<<"$out")"
"$PKG_UPDATE" check --bogus >/dev/null 2>&1; check "pkg-update.sh check: unknown flag" 2 "$?"

# --- archive_url / missing_archives / fetch_missing (offline: file:// "archive", no network)
check "archive_url epoch" "https://archive.archlinux.org/packages/g/grub/grub-2%3A2.16-1-x86_64.pkg.tar.zst" \
    "$(unset PKG_ARCHIVE_URL; archive_url grub 2:2.16-1 x86_64)"
check "archive_url plain, any, letter dir" "http://x/l/linux-firmware-amd/linux-firmware-amd-20260916-1-any.pkg.tar.zst" \
    "$(PKG_ARCHIVE_URL=http://x archive_url linux-firmware-amd 20260916-1 any)"

# new_fetch_env: new_env + a local archive tree ($env_dir/archive/<l>/<name>/) and stub verify.
new_fetch_env() {
    new_env
    export PKG_ARCHIVE_URL="file://$env_dir/archive"
    export PKG_VERIFY=true
    unset PKG_FREE_BYTES FAKE_PACMAN_ARCHS
    printf 'grub\nlinux\n' > "$PKG_PROTECTED_FILE"
}
# archive_pkg NAME VERSION PKGINFO_NAME PKGINFO_VER [ARCH]: a tiny real package + .sig on the archive.
archive_pkg() {
    local name=$1 ver=$2 iname=$3 iver=$4 arch=${5:-x86_64} d w
    d="$env_dir/archive/${name:0:1}/$name"; w=$(mktemp -d -p "$tmp")
    mkdir -p "$d"
    printf 'pkgname = %s\npkgver = %s\narch = %s\n' "$iname" "$iver" "$arch" > "$w/.PKGINFO"
    bsdtar --zstd -cf "$d/$name-$ver-$arch.pkg.tar.zst" -C "$w" .PKGINFO
    printf 'fake signature\n' > "$d/$name-$ver-$arch.pkg.tar.zst.sig"
}
good_archive() { archive_pkg grub 2:2.16-1 grub 2:2.16-1; archive_pkg linux 6.15.3.arch1-1 linux 6.15.3.arch1-1; }
cache_ls() { ls -A "$PKG_CACHE_DIR" | paste -sd' '; }

new_fetch_env
check "missing_archives: everything protected when cache is empty" "grub 2:2.16-1
linux 6.15.3.arch1-1" "$(missing_archives)"
touch "$PKG_CACHE_DIR/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst"
check "missing_archives: cached one is not missing" "grub 2:2.16-1" "$(missing_archives)"
FAKE_PACMAN_EXIT=1 missing_archives >"$env_dir/out" 2>/dev/null; rc=$?
check "missing_archives: pacman failure propagates" 1 "$rc"
check "missing_archives: pacman failure prints nothing" "" "$(cat "$env_dir/out")"

# success: file lands in the cache with pacman's literal-colon name, plus the sig
new_fetch_env; good_archive
out=$(fetch_missing --yes 2>"$env_dir/err" </dev/null); rc=$?
check "fetch: success exits 0" 0 "$rc"
check "fetch: cache has the packages and sigs, no .part" \
    "grub-2:2.16-1-x86_64.pkg.tar.zst grub-2:2.16-1-x86_64.pkg.tar.zst.sig linux-6.15.3.arch1-1-x86_64.pkg.tar.zst linux-6.15.3.arch1-1-x86_64.pkg.tar.zst.sig" "$(cache_ls)"
check "fetch: nothing missing afterwards" "" "$(missing_archives)"
check "fetch: cached file is the archive file" same "$(cmp -s "$env_dir/archive/g/grub/grub-2:2.16-1-x86_64.pkg.tar.zst" "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst" && echo same)"
check "fetch: cached files are world-readable" 644 "$(stat -c %a "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst")"
out=$(fetch_missing --yes 2>&1 </dev/null); rc=$?
check "fetch: a second run has nothing to do" 0 "$rc"
check "fetch: ... and says so" 1 "$(grep -c 'nothing missing' <<<"$out")"

# verify is called as: PKG_VERIFY SIGFILE PKGFILE, both present
new_fetch_env; good_archive
cat > "$env_dir/verify-stub" <<STUB
#!/usr/bin/env bash
echo "\$1 \$2 \$([ -s "\$1" ] && echo sig-ok) \$([ -s "\$2" ] && echo pkg-ok)" >> "$env_dir/verify.log"
STUB
chmod +x "$env_dir/verify-stub"; PKG_VERIFY="$env_dir/verify-stub" fetch_missing --yes >/dev/null 2>&1 </dev/null
check "verify args: sig first, pkg second, files present" "$PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst.sig.part $PKG_CACHE_DIR/grub-2:2.16-1-x86_64.pkg.tar.zst.part sig-ok pkg-ok" "$(grep grub "$env_dir/verify.log")"

# wrong .PKGINFO pkgver / pkgname: deleted and reported
new_fetch_env; archive_pkg grub 2:2.16-1 grub 2:2.15-1; archive_pkg linux 6.15.3.arch1-1 linux 6.15.3.arch1-1
out=$(fetch_missing --yes 2>"$env_dir/err" </dev/null); rc=$?
check "fetch: wrong pkgver exits 1" 1 "$rc"
check "fetch: wrong pkgver is not cached" "linux-6.15.3.arch1-1-x86_64.pkg.tar.zst linux-6.15.3.arch1-1-x86_64.pkg.tar.zst.sig" "$(cache_ls)"
check "fetch: wrong pkgver is reported by name and version" 1 "$(grep -c '^.*grub 2:2.16-1: ' "$env_dir/err")"
new_fetch_env; archive_pkg grub 2:2.16-1 grub-evil 2:2.16-1; archive_pkg linux 6.15.3.arch1-1 linux 6.15.3.arch1-1
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: wrong pkgname exits 1" 1 "$rc"
check "fetch: wrong pkgname is not cached" 0 "$(cache_ls | grep -c grub)"
check "fetch: wrong pkgname is reported" 1 "$(grep -c '^.*grub 2:2.16-1: ' "$env_dir/err")"

# not a package at all
new_fetch_env; good_archive; echo garbage > "$env_dir/archive/g/grub/grub-2:2.16-1-x86_64.pkg.tar.zst"
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: garbage file exits 1" 1 "$rc"
check "fetch: garbage file is not cached, others are" "linux-6.15.3.arch1-1-x86_64.pkg.tar.zst linux-6.15.3.arch1-1-x86_64.pkg.tar.zst.sig" "$(cache_ls)"

# remote file missing (HEAD fails) -> reported, no .part, the rest continues
new_fetch_env; archive_pkg linux 6.15.3.arch1-1 linux 6.15.3.arch1-1
out=$(fetch_missing --yes 2>"$env_dir/err" </dev/null); rc=$?
check "fetch: missing remote exits 1" 1 "$rc"
check "fetch: missing remote reported by name and version" 1 "$(grep -c '^.*grub 2:2.16-1: ' "$env_dir/err")"
check "fetch: missing remote leaves no .part, rest is fetched" "linux-6.15.3.arch1-1-x86_64.pkg.tar.zst linux-6.15.3.arch1-1-x86_64.pkg.tar.zst.sig" "$(cache_ls)"
# only the .sig missing: the package must not stay in the cache
new_fetch_env; good_archive; rm "$env_dir/archive/g/grub/grub-2:2.16-1-x86_64.pkg.tar.zst.sig"
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: missing .sig exits 1" 1 "$rc"
check "fetch: missing .sig: package not cached" 0 "$(cache_ls | grep -c grub)"
# everything missing on the remote
new_fetch_env
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: all missing remotely exits 1" 1 "$rc"
check "fetch: all missing: cache empty" "" "$(cache_ls)"

# failing signature
new_fetch_env; good_archive
PKG_VERIFY=false fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: bad signature exits 1" 1 "$rc"
check "fetch: bad signature: cache empty" "" "$(cache_ls)"
check "fetch: bad signature: reported" 1 "$(grep -c '^.*grub 2:2.16-1: ' "$env_dir/err")"
check "fetch: bad signature: says signature" 1 "$(grep -ci 'signature' "$env_dir/err" | sed 's/^[2-9]/1/')"

# one good, one bad -> good cached, bad reported, non-zero
new_fetch_env; archive_pkg grub 2:2.16-1 grub 9:9-9; archive_pkg linux 6.15.3.arch1-1 linux 6.15.3.arch1-1
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: one bad exits non-zero" 1 "$rc"
check "fetch: good one cached, bad one not" "linux-6.15.3.arch1-1-x86_64.pkg.tar.zst linux-6.15.3.arch1-1-x86_64.pkg.tar.zst.sig" "$(cache_ls)"
check "fetch: only the bad one is reported" "1 0" "$(grep -c '^.*grub 2:2.16-1: ' "$env_dir/err") $(grep -c 'linux 6.15.3' "$env_dir/err")"
check "fetch: the rest still missing" "grub 2:2.16-1" "$(missing_archives)"

# architecture comes from the installed package (-Qi); any is handled
new_fetch_env; printf 'grub\nlinux-firmware-amd\n' > "$PKG_PROTECTED_FILE"
archive_pkg grub 2:2.16-1 grub 2:2.16-1; archive_pkg linux-firmware-amd 20260916-1 linux-firmware-amd 20260916-1 any
printf 'linux-firmware-amd any\n' > "$env_dir/archs"; export FAKE_PACMAN_ARCHS="$env_dir/archs"
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: arch any exits 0" 0 "$rc"
check "fetch: arch any cached as -any, others x86_64" "grub-2:2.16-1-x86_64.pkg.tar.zst grub-2:2.16-1-x86_64.pkg.tar.zst.sig linux-firmware-amd-20260916-1-any.pkg.tar.zst linux-firmware-amd-20260916-1-any.pkg.tar.zst.sig" "$(cache_ls)"

# confirmation
new_fetch_env; good_archive
out=$(echo n | fetch_missing 2>"$env_dir/err"); rc=$?
check "fetch: declined exits 0" 0 "$rc"
check "fetch: declined says nothing downloaded" 1 "$(grep -c 'nothing downloaded' <<<"$out$(cat "$env_dir/err")")"
check "fetch: declined lists the packages" 2 "$(grep -Ec '(grub 2:2.16-1|linux 6.15.3.arch1-1)' <<<"$out")"
check "fetch: declined downloads nothing" "" "$(cache_ls)"
out=$(fetch_missing </dev/null 2>&1); rc=$?
check "fetch: closed stdin counts as no" "0 " "$rc $(cache_ls)"
out=$(echo "" | fetch_missing 2>&1); check "fetch: empty answer counts as no" "" "$(cache_ls)"
out=$(echo y | fetch_missing 2>/dev/null); rc=$?
check "fetch: y downloads" "0 4" "$rc $(cache_ls | wc -w)"

# free space: refuses before any download, listing needed vs available
new_fetch_env; good_archive
total=$(( $(stat -c %s "$env_dir/archive/g/grub/grub-2:2.16-1-x86_64.pkg.tar.zst") + $(stat -c %s "$env_dir/archive/l/linux/linux-6.15.3.arch1-1-x86_64.pkg.tar.zst") ))
need=$(( total + (total + 9) / 10 ))
cat > "$env_dir/verify-stub" <<STUB
#!/usr/bin/env bash
echo called >> "$env_dir/verify.log"
STUB
PKG_FREE_BYTES=$((need - 1)) PKG_VERIFY="$env_dir/verify-stub" fetch_missing --yes >"$env_dir/out" 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: too little space exits 1" 1 "$rc"
check "fetch: too little space downloads nothing" "" "$(cache_ls)"
check "fetch: too little space never verified" no "$([ -e "$env_dir/verify.log" ] && echo yes || echo no)"
check "fetch: too little space lists needed and available" "1 1" "$(grep -ci 'need' "$env_dir/err" | sed 's/^[2-9]/1/') $(grep -c "$((need - 1))" "$env_dir/err")"
PKG_FREE_BYTES=$need fetch_missing --yes >/dev/null 2>&1 </dev/null; rc=$?
check "fetch: exactly sum + 10% is enough" "0 4" "$rc $(cache_ls | wc -w)"
check "pkg_free_bytes default is a number" 1 "$(unset PKG_FREE_BYTES; pkg_free_bytes "$PKG_CACHE_DIR" | grep -Ec '^[0-9]+$')"
check "pkg_free_bytes override" 1234 "$(PKG_FREE_BYTES=1234 pkg_free_bytes "$PKG_CACHE_DIR")"

# unsafe names/versions never reach the filesystem: a version "1/../../x" would download
# to a path outside the cache if the guard let it through (the dir below makes it resolvable)
new_fetch_env; printf 'evil 1/../../x\n' >> "$FAKE_PACMAN_DB"; printf 'evil\n' > "$PKG_PROTECTED_FILE"
mkdir "$PKG_CACHE_DIR/evil-1"
mkdir -p "$env_dir/archive/e"; w=$(mktemp -d -p "$tmp")
printf 'pkgname = evil\npkgver = 1/../../x\n' > "$w/.PKGINFO"
bsdtar --zstd -cf "$env_dir/archive/e/x-x86_64.pkg.tar.zst" -C "$w" .PKGINFO
printf 'sig\n' > "$env_dir/archive/e/x-x86_64.pkg.tar.zst.sig"
fetch_missing --yes >/dev/null 2>"$env_dir/err" </dev/null; rc=$?
check "fetch: unsafe version exits 1" 1 "$rc"
check "fetch: unsafe version is refused as unsafe" 1 "$(grep -c 'evil 1/../../x: unsafe' "$env_dir/err")"
check "fetch: unsafe version writes nothing outside the cache" "" "$(ls -A "$env_dir" | grep '^x-x86_64' | paste -sd' ')"
check "fetch: unsafe version leaves nothing in the cache" "evil-1" "$(cache_ls)"

# every pacman call runs with LC_ALL=C (parsed output must not be translated)
new_fetch_env; export FAKE_PACMAN_ENVLOG="$env_dir/envlog"
LC_ALL=C.UTF-8 pkg_installed >/dev/null; LC_ALL=C.UTF-8 pkg_pacman -Qi grub >/dev/null
check "pacman wrapper: LC_ALL=C for -Q and -Qi" "-Q LC_ALL=C
-Qi grub LC_ALL=C" "$(cat "$FAKE_PACMAN_ENVLOG")"
new_check_env; export FAKE_PACMAN_ENVLOG="$env_dir/envlog"
LC_ALL=C.UTF-8 check_updates >/dev/null 2>&1
check "check_updates: every pacman call incl. -Sy runs with LC_ALL=C" "3 0" "$(grep -c 'LC_ALL=C$' "$FAKE_PACMAN_ENVLOG") $(grep -vc 'LC_ALL=C$' "$FAKE_PACMAN_ENVLOG")"
check "check_updates: the -Sy call is among them" 1 "$(grep -- ' -Sy ' "$FAKE_PACMAN_ENVLOG" | grep -c 'LC_ALL=C$')"
unset FAKE_PACMAN_ENVLOG

# curl: file:// only for a file:// base; -q first
check "curl proto: default base is https only" "=https" "$(unset PKG_ARCHIVE_URL; _pkg_curl_proto)"
check "curl proto: http base is https only" "=https" "$(PKG_ARCHIVE_URL=http://x/p _pkg_curl_proto)"
check "curl proto: https base" "=https" "$(PKG_ARCHIVE_URL=https://x/p _pkg_curl_proto)"
check "curl proto: file base allows file" "=https,file" "$(PKG_ARCHIVE_URL=file:///x _pkg_curl_proto)"
new_fetch_env; good_archive
printf 'x\n' > "$env_dir/f"
PKG_ARCHIVE_URL=https://example.invalid/p _pkg_curl -o "$env_dir/o" "file://$env_dir/f" 2>/dev/null; rc=$?
check "curl: a file:// URL is refused with an https base" "1 0" "$((rc != 0)) $([ -e "$env_dir/o" ] && echo 1 || echo 0)"
_pkg_curl -o "$env_dir/o" "file://$env_dir/f" 2>/dev/null; check "curl: ... and allowed with a file:// base" 0 "$?"
printf 'output = "%s/hijack"\n' "$env_dir" > "$env_dir/.curlrc"
CURL_HOME="$env_dir" HOME="$env_dir" _pkg_curl "file://$env_dir/f" >/dev/null
check "curl: ~/.curlrc is ignored" "no" "$([ -e "$env_dir/hijack" ] && echo yes || echo no)"

# interrupted: no .part files and nothing half-installed
new_fetch_env; good_archive
cat > "$env_dir/slow-verify" <<STUB
#!/usr/bin/env bash
touch "$env_dir/in-verify"; sleep 2
STUB
chmod +x "$env_dir/slow-verify"
PKG_VERIFY="$env_dir/slow-verify" "$PKG_UPDATE" fetch-missing --yes >/dev/null 2>&1 </dev/null &
pid=$!
for _ in $(seq 100); do [ -e "$env_dir/in-verify" ] && break; sleep 0.05; done
kill -TERM "$pid"; wait "$pid"; rc=$?
check "fetch: SIGTERM exits 143" 143 "$rc"
check "fetch: SIGTERM leaves no .part or partial package" "" "$(cache_ls)"

# the CLI
new_fetch_env; good_archive
"$PKG_UPDATE" fetch-missing --bogus >/dev/null 2>&1; check "pkg-update.sh fetch-missing: unknown flag" 2 "$?"
"$PKG_UPDATE" fetch-missing --yes >/dev/null 2>&1 </dev/null; check "pkg-update.sh fetch-missing --yes exits 0" 0 "$?"
check "pkg-update.sh fetch-missing --yes fills the cache" 4 "$(cache_ls | wc -w)"
echo n | "$PKG_UPDATE" fetch-missing >/dev/null 2>&1; check "pkg-update.sh fetch-missing: nothing missing exits 0" 0 "$?"

# default verifier: gpg against a keyring (PKG_GPG_DIR stands in for the pacman keyring)
if command -v gpg >/dev/null 2>&1; then
    new_env
    gtrust="$env_dir/gpg-trusted"; guntrust="$env_dir/gpg-untrusted"
    mkdir -m 700 "$gtrust" "$guntrust"
    gpg --homedir "$gtrust" --batch --quiet --pinentry-mode loopback --passphrase '' \
        --quick-generate-key 'Test Packager <t@example.invalid>' ed25519 sign never 2>/dev/null
    printf 'package bytes\n' > "$env_dir/p.pkg.tar.zst"
    gpg --homedir "$gtrust" --batch --quiet --detach-sign -o "$env_dir/p.sig" "$env_dir/p.pkg.tar.zst" 2>/dev/null
    gpg --homedir "$gtrust" --batch --quiet --export > "$env_dir/pub.gpg"
    gpg --homedir "$guntrust" --batch --quiet --import "$env_dir/pub.gpg" 2>/dev/null
    PKG_GPG_DIR=$gtrust pkg_verify_signature "$env_dir/p.sig" "$env_dir/p.pkg.tar.zst" 2>/dev/null; check "verify default: good signature, trusted key" 0 "$?"
    printf 'tampered\n' > "$env_dir/q.pkg.tar.zst"
    PKG_GPG_DIR=$gtrust pkg_verify_signature "$env_dir/p.sig" "$env_dir/q.pkg.tar.zst" 2>/dev/null; check "verify default: tampered package fails" 1 "$?"
    PKG_GPG_DIR=$guntrust pkg_verify_signature "$env_dir/p.sig" "$env_dir/p.pkg.tar.zst" 2>/dev/null; check "verify default: untrusted key fails" 1 "$?"
    PKG_GPG_DIR=$gtrust pkg_verify_signature "$env_dir/nope.sig" "$env_dir/p.pkg.tar.zst" 2>/dev/null; check "verify default: missing signature fails" 1 "$?"
    echo junk > "$env_dir/junk.sig"
    PKG_GPG_DIR=$gtrust pkg_verify_signature "$env_dir/junk.sig" "$env_dir/p.pkg.tar.zst" 2>/dev/null; check "verify default: garbage signature fails" 1 "$?"
else
    echo "SKIP default verifier tests: gpg not installed"
fi

# --- settings: the environment first (root has no $HOME), files second
new_env
check "cache_keep default" 3 "$(settings_cache_keep)"
echo 7 > "$PKG_CACHE_KEEP_FILE"
check "cache_keep from file" 7 "$(settings_cache_keep)"
check "cache_keep env beats file" 5 "$(PKG_CACHE_KEEP=5 settings_cache_keep)"
for v in 0 21 abc -2 3.5 ""; do
    check "cache_keep env '$v' falls back to 3" 3 "$(PKG_CACHE_KEEP=$v PKG_CACHE_KEEP_FILE=/nonexistent settings_cache_keep)"
done
check "cache_keep env bounds 1 and 20" "1 20" "$(PKG_CACHE_KEEP=1 settings_cache_keep) $(PKG_CACHE_KEEP=20 settings_cache_keep)"
echo 99 > "$PKG_CACHE_KEEP_FILE"
check "cache_keep file out of range falls back to 3" 3 "$(settings_cache_keep)"
echo abc > "$PKG_CACHE_KEEP_FILE"
check "cache_keep junk file falls back to 3" 3 "$(settings_cache_keep)"
check "cache_keep default file is under SHROOMERY_SETTINGS" "$HOME/.config/shroomery/settings/cache-keep" "$(unset PKG_CACHE_KEEP_FILE; pkg_cache_keep_file)"

new_env
printf 'filepat\n' > "$PKG_PROTECTED_FILE"
check "settings_protected from file" filepat "$(settings_protected)"
check "protected_patterns from file" filepat "$(protected_patterns)"
export PKG_PROTECTED_PATTERNS=$'envpat*\n\n  spaced name  \n# comment\nlinux'
check "settings_protected env beats file (trimmed, blanks and comments skipped)" "envpat*|spaced name|linux" "$(settings_protected | paste -sd'|')"
check "protected_patterns returns the env patterns" "envpat*|spaced name|linux" "$(protected_patterns | paste -sd'|')"
rm "$PKG_PROTECTED_FILE"
check "protected_patterns env, no file" "envpat*|spaced name|linux" "$(protected_patterns | paste -sd'|')"
check "protected_installed uses the env patterns" "linux 6.15.3.arch1-1" "$(protected_installed)"
check "manifest copies the env patterns" "envpat*|spaced name|linux" "$(manifest_json known-good | jq -r '.patterns|join("|")')"
# root path: HOME does not exist and holds no settings; the env alone decides
out=$(HOME=/nonexistent/home PKG_PROTECTED_FILE= "$PKG_UPDATE" status 2>&1); rc=$?
check "status with HOME nonexistent and env patterns" 0 "$rc"
mkdir -p "$env_dir/home/.config/shroomery/settings"
printf 'firefox\n' > "$env_dir/home/.config/shroomery/settings/recovery-protected"
echo 9 > "$env_dir/home/.config/shroomery/settings/cache-keep"
check "root code path ignores the user's settings files in HOME" "linux 6.15.3.arch1-1|3 5" \
    "$(HOME=$env_dir/home bash -c "unset PKG_PROTECTED_FILE PKG_CACHE_KEEP_FILE; source '$HERE/../lib.sh'; source '$HERE/../scripts/pkg-lib.sh'; PKG_CACHE_KEEP=5 PKG_PROTECTED_PATTERNS=linux; echo \"\$(PKG_PACMAN='$HERE/fakes/pacman' protected_installed | paste -sd'|')|\$(PKG_CACHE_KEEP=bad settings_cache_keep) \$(PKG_CACHE_KEEP=5 settings_cache_keep)\"")"
unset PKG_PROTECTED_PATTERNS

# --- elevate: pkexec re-exec of the dispatcher with an explicit environment
# The stub stands in for pkexec (clears the environment, like the real one, then runs the
# command) and records its argv, NUL separated.
make_pkexec_stub() {  # make_pkexec_stub DIR -> DIR/pkexec, DIR/target (the "script"), DIR/argv, DIR/target.env
    cat > "$1/pkexec" <<STUB
#!/usr/bin/env bash
printf '%s\0' "\$@" > "$1/argv"
exec env -i "\$@"
STUB
    cat > "$1/target" <<STUB
#!/usr/bin/env bash
env > "$1/target.env"
printf '%s\0' "\$@" > "$1/target.argv"
STUB
    chmod +x "$1/pkexec" "$1/target"
}
read_argv() { mapfile -d '' -t ARGV < "$1"; }

new_env
make_pkexec_stub "$env_dir"
printf 'linux\nweird name*\n' > "$PKG_PROTECTED_FILE"
echo 4 > "$PKG_CACHE_KEEP_FILE"
(   unset PKG_NO_ELEVATE
    export PKG_PKEXEC="$env_dir/pkexec" WAYLAND_DISPLAY=wl-1 XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:7 HOME=/home/someone
    export PKG_PACMAN=evil-pacman PKG_ARCHIVE_URL=evil PKG_VERIFY=evil PKG_PROTECTED_FILE="$PKG_PROTECTED_FILE" PKG_FREE_BYTES=1 PKG_GPG_DIR=/evil
    elevate "$env_dir/target" fetch-missing "two words" --yes ''
); check "elevate exec'd pkexec" 0 "$(test -f "$env_dir/argv"; echo $?)"
read_argv "$env_dir/argv"
check "elevate argv (env, listed variables only, script, args)" \
    "env|WAYLAND_DISPLAY=wl-1|XDG_RUNTIME_DIR=/run/user/1000|DISPLAY=:7|PKG_CACHE_KEEP=4|PKG_PROTECTED_PATTERNS=linux
weird name*|PKG_USER_HOME=/home/someone|$env_dir/target|fetch-missing|two words|--yes|" "$(IFS='|'; echo "${ARGV[*]}")"
check "elevate forwards exactly the PKG_ names CACHE_KEEP PROTECTED_PATTERNS USER_HOME" \
    "PKG_CACHE_KEEP PKG_PROTECTED_PATTERNS PKG_USER_HOME" "$(printf '%s\n' "${ARGV[@]}" | sed -n 's/^\(PKG_[A-Z_]*\)=.*/\1/p' | paste -sd' ')"
# end to end through env -i: what the root process really sees
check "root env: only the forwarded variables carry PKG_" "PKG_CACHE_KEEP PKG_PROTECTED_PATTERNS PKG_USER_HOME" \
    "$(grep -a -o '^PKG_[A-Z_]*' "$env_dir/target.env" | sort | paste -sd' ')"
check "root env: display variables" "DISPLAY=:7 WAYLAND_DISPLAY=wl-1 XDG_RUNTIME_DIR=/run/user/1000" "$(grep -aE '^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=' "$env_dir/target.env" | sort | paste -sd' ')"
check "root env: multi-line patterns survive" "linux|weird name*" "$(PKG_PROTECTED_PATTERNS=$(sed -n '/^PKG_PROTECTED_PATTERNS=/,$p' "$env_dir/target.env" | sed '1s/^[^=]*=//' | sed -n '1,2p'); printf '%s\n' "$PKG_PROTECTED_PATTERNS" | paste -sd'|')"
read_argv "$env_dir/target.argv"
check "root args survive (spaces, empty)" "fetch-missing|two words|--yes|" "$(IFS='|'; echo "${ARGV[*]}")"

# keep: the user's own PKG_CACHE_KEEP / PKG_PROTECTED_PATTERNS env are validated/normalised, not copied blindly
rm -f "$env_dir/argv"
(   unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec" PKG_CACHE_KEEP=999 PKG_PROTECTED_PATTERNS=$'a b\nc'
    elevate "$env_dir/target" x )
read_argv "$env_dir/argv"
check "elevate re-resolves cache-keep (999 -> 3)" "PKG_CACHE_KEEP=3" "$(printf '%s\n' "${ARGV[@]}" | grep '^PKG_CACHE_KEEP=')"
check "elevate forwards env patterns as the resolved list" "PKG_PROTECTED_PATTERNS=a b
c" "$(printf '%s\n' "${ARGV[@]}" | sed -n '/^PKG_PROTECTED_PATTERNS=/{N;p}')"

# no elevation: root, or PKG_NO_ELEVATE
rm -f "$env_dir/argv"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec" PKG_TEST_EUID=0; elevate "$env_dir/target" x ); check "elevate as root returns 0" 0 "$?"
( export PKG_PKEXEC="$env_dir/pkexec"; elevate "$env_dir/target" x ); check "elevate with PKG_NO_ELEVATE returns 0" 0 "$?"
check "elevate as root / PKG_NO_ELEVATE: pkexec not called" no "$([ -e "$env_dir/argv" ] && echo yes || echo no)"
# pkexec missing: a clear error, never an unprivileged run
err=$( ( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/nope"; elevate "$env_dir/target" x; echo "continued" ) 2>&1 ); rc=$?
check "elevate without pkexec exits 1" 1 "$rc"
check "elevate without pkexec says so" 1 "$(grep -c 'pkexec' <<<"$err")"
check "elevate without pkexec does not continue" 0 "$(grep -c continued <<<"$err")"

# the dispatcher: fetch-missing elevates first, with its real path (also when called through a symlink)
new_env
make_pkexec_stub "$env_dir"
printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" > "%s/argv"\n' "$env_dir" > "$env_dir/pkexec"   # record only: the real dispatcher would elevate again
ln -s "$PKG_UPDATE" "$env_dir/link-to-update"
(   unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
    "$env_dir/link-to-update" fetch-missing --yes </dev/null >/dev/null 2>&1 )
read_argv "$env_dir/argv"
check "dispatcher elevates fetch-missing via the real script path" "$(readlink -f "$PKG_UPDATE")|fetch-missing|--yes" "$(IFS='|'; echo "${ARGV[*]: -3}")"
check "dispatcher: pkexec runs env first" env "${ARGV[0]}"
rm -f "$env_dir/argv"
(   unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
    "$PKG_UPDATE" status >/dev/null 2>&1; "$PKG_UPDATE" check --bogus >/dev/null 2>&1; "$PKG_UPDATE" bogus >/dev/null 2>&1 )
check "dispatcher: status/check/unknown never elevate" no "$([ -e "$env_dir/argv" ] && echo yes || echo no)"

# --- log_start: tee into logs/, flushed before the script exits
LOGSH="source '$HERE/../lib.sh'; source '$HERE/../scripts/pkg-lib.sh'"
new_env
out=$(bash -c "$LOGSH; log_start unit; echo later; echo oops >&2; echo done" 2>"$env_dir/err"); rc=$?
logfile=$(head -n 1 <<<"$out" | sed -n 's/^LOG=//p')
check "log_start exits 0" 0 "$rc"
check "log_start: LOG= is the first stdout line" 1 "$(head -n 1 <<<"$out" | grep -c '^LOG=')"
check "log_start: log path under logs/ named <UTC>-NAME.log" 1 "$(grep -Ec "^$PKG_RECOVERY_DIR/logs/[0-9]{8}T[0-9]{6}Z-unit\.log\$" <<<"$logfile")"
check "log_start: stdout still reaches the caller" "later|done" "$(tail -n +2 <<<"$out" | paste -sd'|')"
check "log_start: stderr stays on stderr" oops "$(cat "$env_dir/err")"
check "log contains stdout and stderr lines" "done|later|oops" "$(sort "$logfile" | paste -sd'|')"
check "log_start: logs dir mode 755, file mode 644" "755 644" "$(stat -c %a "$PKG_RECOVERY_DIR/logs") $(stat -c %a "$logfile")"
out=$(umask 077; bash -c "umask 077; $LOGSH; log_start modes; true" 2>&1)
lf=$(sed -n 's/^LOG=//p' <<<"$out")
check "log_start: file mode 644 whatever the umask" 644 "$(stat -c %a "$lf")"
# fully flushed at exit, large output, nothing lost
out=$(bash -c "$LOGSH; log_start big; seq 1 30000; seq 1 30000 >&2" 2>/dev/null)
lf=$(head -n 1 <<<"$out" | sed 's/^LOG=//')
check "log fully flushed at exit (60000 lines)" 60000 "$(wc -l < "$lf")"
# exit status kept, caller's EXIT trap output still logged
out=$(bash -c "trap 'echo caller-exit-trap' EXIT; $LOGSH; log_start trapped; echo hi; exit 5" 2>&1); rc=$?
lf=$(head -n 1 <<<"$out" | sed 's/^LOG=//')
check "log_start keeps the exit status" 5 "$rc"
check "caller EXIT trap still runs and is logged" 1 "$(grep -c '^caller-exit-trap$' "$lf")"
# logs/ is created, name is sanitised, two logs in one second do not collide
new_env
rm -rf "$PKG_RECOVERY_DIR"
out=$(bash -c "$LOGSH; log_start 'a/b c'; log_finish" 2>&1); lf=$(head -n 1 <<<"$out" | sed 's/^LOG=//')
check "log_start creates the recovery dir and logs/" 1 "$([ -f "$lf" ] && echo 1 || echo 0)"
check "log_start sanitises NAME (no slash or space in the file name)" 1 "$(basename "$lf" | grep -Ec '^[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9._-]+\.log$')"
bash -c "$LOGSH; log_start same; log_finish" >/dev/null 2>&1; bash -c "$LOGSH; log_start same; log_finish" >/dev/null 2>&1
check "two logs of the same name are two files" 2 "$(ls "$PKG_RECOVERY_DIR/logs" | grep -c -- '-same')"
# TERM: the log keeps what was written before
new_env
bash -c "$LOGSH; log_start term; echo before-term; touch '$env_dir/ready'; sleep 5" >"$env_dir/out" 2>&1 &
bgpid=$!
for _ in $(seq 50); do [ -e "$env_dir/ready" ] && break; sleep 0.1; done
sleep 0.2; kill -TERM "$bgpid"; wait "$bgpid"
check "TERM: log has the lines written before" 1 "$(cat "$PKG_RECOVERY_DIR"/logs/*-term.log | grep -c '^before-term$')"
# missing logs dir that cannot be created
new_env
touch "$env_dir/file"; export PKG_RECOVERY_DIR="$env_dir/file/sub"
bash -c "$LOGSH; log_start x" >/dev/null 2>&1; check "log_start fails when logs/ cannot be created" 1 "$?"

# --- acquire_lock: flock on <recovery>/lock, exit 3 when held or pacman's db.lck exists
# Each competitor is its own process (bash -c): a subshell would inherit the held lock.
new_env
LOCKSH="$LOGSH; acquire_lock"
trylock() { bash -c "$LOCKSH" 2>"$env_dir/err" >/dev/null; }
trylock; check "acquire_lock free: succeeds" 0 "$?"
check "lock file is in the recovery dir" 1 "$([ -f "$PKG_RECOVERY_DIR/lock" ] && echo 1 || echo 0)"
rc=$( ( acquire_lock; trylock; echo $? ) ); check "acquire_lock held: exits 3" 3 "$rc"
check "acquire_lock held: says so" 1 "$(grep -c -i 'another update' "$env_dir/err")"
( acquire_lock; ( acquire_lock ); echo "again-$?" ) >"$env_dir/out" 2>&1
check "acquire_lock twice in one process is a no-op" again-0 "$(cat "$env_dir/out")"
trylock; check "lock released when the holder exits" 0 "$?"
touch "$env_dir/fake.lck"
PKG_PACMAN_DBLOCK="$env_dir/fake.lck" trylock; rc=$?
check "db.lck present: exits 3" 3 "$rc"
check "db.lck present: names the file" 1 "$(grep -c "$env_dir/fake.lck" "$env_dir/err")"
trylock; check "db.lck refusal does not leave our lock held" 0 "$?"
check "default db.lck path" /var/lib/pacman/db.lck "$(unset PKG_PACMAN_DBLOCK; pkg_dblock)"
# not inherited by a long-lived background child started through pkg_pacman (e.g. a pacman hook daemon)
cat > "$env_dir/daemon-pacman" <<STUB
#!/usr/bin/env bash
sleep 30 >/dev/null 2>&1 &
echo \$! > "$env_dir/daemon.pid"
STUB
chmod +x "$env_dir/daemon-pacman"
( PKG_PACMAN="$env_dir/daemon-pacman"; acquire_lock; pkg_pacman -Syu >/dev/null 2>&1 )
trylock; check "lock not kept alive by a background child of pacman" 0 "$?"
kill "$(cat "$env_dir/daemon.pid")" 2>/dev/null
# ... and the control: a plain background child does keep it (so the test above means something)
( acquire_lock; sleep 30 >/dev/null 2>&1 & echo $! > "$env_dir/ctl.pid" )
trylock; check "control: a child that inherited fd 200 holds the lock" 3 "$?"
kill "$(cat "$env_dir/ctl.pid")" 2>/dev/null; sleep 0.1
# not inherited by the log's tee either
bash -c "$LOCKSH; log_start lk" >/dev/null 2>&1
trylock; check "lock free after log_start + exit" 0 "$?"
# a killed holder releases it
bash -c "$LOCKSH; exec sleep 5" >/dev/null 2>&1 &
holder=$!; sleep 0.3
trylock; check "lock held by a running process" 3 "$?"
kill "$holder"; wait "$holder" 2>/dev/null
trylock; check "lock free after the holder was killed" 0 "$?"

# dispatcher: fetch-missing logs and locks (offline: file:// archive, stub verify)
new_fetch_env; good_archive
out=$("$PKG_UPDATE" fetch-missing --yes 2>/dev/null </dev/null); rc=$?
check "fetch-missing (no elevation): exits 0" 0 "$rc"
check "fetch-missing prints LOG= first" 1 "$(head -n 1 <<<"$out" | grep -c '^LOG=')"
lf=$(head -n 1 <<<"$out" | sed 's/^LOG=//')
check "fetch-missing log has the output" 1 "$(grep -c 'Fetched 2 archive' "$lf")"
( acquire_lock; "$PKG_UPDATE" fetch-missing --yes >/dev/null 2>&1 </dev/null ); check "fetch-missing refuses while the lock is held" 3 "$?"
touch "$env_dir/dblck"; PKG_PACMAN_DBLOCK="$env_dir/dblck" "$PKG_UPDATE" fetch-missing --yes >/dev/null 2>&1 </dev/null; check "fetch-missing refuses while pacman runs" 3 "$?"
# the root path with no HOME: env settings only
new_fetch_env; good_archive
HOME=/nonexistent/home PKG_PROTECTED_PATTERNS=$'grub\nlinux' PKG_PROTECTED_FILE= "$PKG_UPDATE" fetch-missing --yes >/dev/null 2>&1 </dev/null
check "fetch-missing with HOME nonexistent and env patterns" 4 "$(cache_ls | wc -w)"

# --- apply / discard ---------------------------------------------------------------------
# new_apply_env: new_env + a cache holding an archive of every protected package, stubs for
# paccache and qs that log their arguments, a pacman.conf with Ignore lines and an "after" package
# database (the versions the fake -Syu moves to). The recovery dir holds a known-good that
# matches the installed set.
new_apply_env() {
    new_env
    unset FAKE_PACMAN_SYUW_EXIT FAKE_PACMAN_SYU_EXIT FAKE_PACMAN_SLEEP FAKE_PACMAN_STARTED FAKE_PACMAN_Q_FAIL_AFTER_UPDATE \
        FAKE_PACMAN_ARCHS
    export PKG_ARCHIVE_URL="file://$env_dir/archive" PKG_VERIFY=true   # never the network; the tree below is empty unless a test fills it
    mkdir -p "$env_dir/xdg" "$env_dir/tmpdir" "$env_dir/home"
    export XDG_RUNTIME_DIR="$env_dir/xdg" TMPDIR="$env_dir/tmpdir" PKG_USER_HOME="$env_dir/home"
    export PKG_FREE_BYTES=100000000000
    export FAKE_PACMAN_ENVLOG="$env_dir/pacman.env"
    export FAKE_PACMAN_CONF_COPY="$env_dir/conf-seen"
    export FAKE_PACMAN_AFTER="$env_dir/after-db"
    export FAKE_PACMAN_WATCH="$PKG_RECOVERY_DIR/pending/manifest.json" FAKE_PACMAN_WATCH_OUT="$env_dir/watch"
    export PKG_PACCACHE="$env_dir/paccache" PKG_QS="$env_dir/qs"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/paccache.log"\nexit "${STUB_PACCACHE_EXIT:-0}"\n' "$env_dir" > "$env_dir/paccache"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/qs.log"\nexit "${STUB_QS_EXIT:-0}"\n' "$env_dir" > "$env_dir/qs"
    chmod +x "$env_dir/paccache" "$env_dir/qs"
    unset STUB_PACCACHE_EXIT STUB_QS_EXIT PKG_QS_TIMEOUT
    cat > "$PKG_PACMAN_CONF" <<'CONF'
[options]
HoldPkg     = pacman glibc
IgnorePkg   = linux linux-headers nvidia nvidia-open
  IgnoreGroup = nvidia-utils
DBPath      = /var/lib/pacman/
Include = /etc/pacman.d/mirrorlist
CONF
    cat >> "$FAKE_PACMAN_DB" <<'DB'
oldpkg 1-1
DB
    cat > "$FAKE_PACMAN_AFTER" <<'DB'
linux 6.16.0.arch1-1
nvidia-open 580.1-1
linux-firmware-amd 20260916-1
firefox 131-1
grub 2:2.17-1
newpkg 3:1-1
DB
    local n v
    while read -r n v; do : > "$PKG_CACHE_DIR/$n-$v-x86_64.pkg.tar.zst"; done < <(protected_installed)
    known_good_from_installed
    rm -f "$FAKE_PACMAN_ENVLOG" "$FAKE_PACMAN_LOG"   # the setup's own pacman calls
}
# apply_ok_state: the pending manifest's state and the pacman calls (-Syuw / -Syu lines only)
pending_state() { jq -r .state "$PKG_RECOVERY_DIR/pending/manifest.json" 2>/dev/null; }
pacman_calls() { grep -E -- '-Syuw?( |$)' "$FAKE_PACMAN_LOG" 2>/dev/null | sed -E 's/--config [^ ]+/--config CONF/'; }
kg_fingerprint() {   # inode, mtime and the content listing of known-good
    stat -c '%i %Y' "$PKG_RECOVERY_DIR/known-good"
    find "$PKG_RECOVERY_DIR/known-good" -printf '%p %i %s %T@\n' | sort
    sha256sum < "$PKG_RECOVERY_DIR/known-good/manifest.json"
}
leftovers() { find "$PKG_RECOVERY_DIR" \( -name '*.tmp*' -o -name '*.old.*' -o -name '*.new.*' -o -name '*.discard.*' \) | paste -sd' '; }

# usage: a bad flag is exit 2 and never reaches pkexec
new_apply_env
make_pkexec_stub "$env_dir"
printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" > "%s/argv"\n' "$env_dir" > "$env_dir/pkexec"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
  "$PKG_UPDATE" apply --bogus >/dev/null 2>&1; echo "apply-$?" > "$env_dir/rc"
  "$PKG_UPDATE" discard now >/dev/null 2>&1; echo "discard-$?" >> "$env_dir/rc" )
check "apply --bogus and discard with an argument exit 2" "apply-2 discard-2" "$(paste -sd' ' "$env_dir/rc")"
check "usage errors do not elevate" no "$([ -e "$env_dir/argv" ] && echo yes || echo no)"
# apply and discard elevate first, with the real script path
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" apply --system --force --yes </dev/null >/dev/null 2>&1 )
read_argv "$env_dir/argv"
check "apply elevates through pkexec" "$(readlink -f "$PKG_UPDATE")|apply|--system|--force|--yes" "$(IFS='|'; echo "${ARGV[*]: -5}")"
rm -f "$env_dir/argv"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" discard </dev/null >/dev/null 2>&1 )
read_argv "$env_dir/argv"
check "discard elevates through pkexec" "$(readlink -f "$PKG_UPDATE")|discard" "$(IFS='|'; echo "${ARGV[*]: -2}")"

# happy path (normal update)
new_apply_env
kg_before=$(kg_fingerprint)
out=$("$PKG_UPDATE" apply </dev/null 2>"$env_dir/err"); rc=$?
check "apply: exits 0" 0 "$rc"
check "apply: LOG= is the first line" 1 "$(head -n 1 <<<"$out" | grep -c '^LOG=')"
check "apply: known-good untouched (inode, mtime, files)" "$kg_before" "$(kg_fingerprint)"
check "apply: state awaiting-verification" awaiting-verification "$(pending_state)"
check "apply: mode, pacman_exit" "normal 0" "$(jq -r '"\(.mode) \(.pacman_exit)"' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "apply: started and finished are ISO times" 2 "$(jq -r '[.started, .finished] | map(select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))) | length' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "apply: from/to of every changed package (changed, added, removed, epoch kept), sorted" \
"firefox 130-1 131-1
grub 2:2.16-1 2:2.17-1
linux 6.15.3.arch1-1 6.16.0.arch1-1
newpkg null 3:1-1
nvidia-open 575.64-2 580.1-1
oldpkg 1-1 null" \
    "$(jq -r '.packages[] | "\(.name) \(.from) \(.to)"' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "apply: unchanged packages are not recorded" 0 "$(jq '[.packages[] | select(.name == "linux-firmware-amd")] | length' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "apply: pacman -Syuw then -Syu, real config, no prompts" \
    "--config CONF --noconfirm -Syuw
--config CONF --noconfirm -Syu" "$(pacman_calls)"
check "apply: the real config is passed as is" 2 "$(grep -c -- "--config $PKG_PACMAN_CONF " "$FAKE_PACMAN_LOG")"
check "apply: -Syuw and -Syu run with LC_ALL=C" 2 "$(grep -E -- '-Syuw? ' "$FAKE_PACMAN_ENVLOG" | grep -c 'LC_ALL=C$')"
check "apply: paccache -rk3 -c CACHE after success" "-rk3 -c $PKG_CACHE_DIR" "$(cat "$env_dir/paccache.log")"
check "apply: statusbar refresh" "ipc call updates refresh" "$(cat "$env_dir/qs.log")"
check "apply: manifest is world-readable" "644 755" "$(stat -c %a "$PKG_RECOVERY_DIR/pending/manifest.json") $(stat -c %a "$PKG_RECOVERY_DIR/pending")"
check "apply: no temp leftovers" "" "$(leftovers)"
check "apply: the pending record was visible as running while pacman updated" "running null" \
    "$(jq -r '"\(.state) \(.pacman_exit)"' "$FAKE_PACMAN_WATCH_OUT.Syuw")"
check "apply: and still running at -Syu" running "$(jq -r .state "$FAKE_PACMAN_WATCH_OUT.Syu")"
check "apply: pending is in the log" 1 "$(grep -c 'awaiting' <<<"$out")"
lf=$(head -n 1 <<<"$out" | sed 's/^LOG=//'); check "apply: log file exists" 1 "$([ -s "$lf" ] && echo 1 || echo 0)"
check "apply: root made nothing under XDG_RUNTIME_DIR or the user's home" "" "$(find "$XDG_RUNTIME_DIR" "$PKG_USER_HOME" -mindepth 1 | paste -sd' ')"
check "apply: nothing left in TMPDIR" "" "$(find "$TMPDIR" -mindepth 1 | paste -sd' ')"

# cache-keep: env, then the settings file
new_apply_env
PKG_CACHE_KEEP=5 "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "apply: paccache keeps PKG_CACHE_KEEP" "-rk5 -c $PKG_CACHE_DIR" "$(cat "$env_dir/paccache.log")"
new_apply_env; echo 7 > "$PKG_CACHE_KEEP_FILE"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "apply: paccache keeps the cache-keep file value" "-rk7 -c $PKG_CACHE_DIR" "$(cat "$env_dir/paccache.log")"

# --yes: no pacman prompts and no questions (here also the default for no terminal)
new_apply_env
"$PKG_UPDATE" apply --yes </dev/null >/dev/null 2>&1; check "apply --yes: exits 0" 0 "$?"
check "apply --yes: pacman gets --noconfirm" 2 "$(grep -c -- '--noconfirm' "$FAKE_PACMAN_LOG")"

# --system: a temp config without any Ignore line, in the root's own place; the real config untouched
new_apply_env
conf_sum=$(sha256sum < "$PKG_PACMAN_CONF")
"$PKG_UPDATE" apply --system </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "apply --system: exits 0" 0 "$rc"
check "apply --system: mode recorded" system "$(jq -r .mode "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "apply --system: -Syuw and -Syu both get the temp config" 2 "$(grep -c -E -- "--config $PKG_RECOVERY_DIR/tmp/[^ ]+/pacman.conf " "$FAKE_PACMAN_LOG")"
check "apply --system: the temp config has no IgnorePkg/IgnoreGroup" 0 "$(cat "$FAKE_PACMAN_CONF_COPY".Syuw "$FAKE_PACMAN_CONF_COPY".Syu | grep -c -E '^[[:space:]]*Ignore(Pkg|Group)')"
check "apply --system: other lines are kept" "[options] HoldPkg DBPath Include" \
    "$(grep -E '^(\[options\]|HoldPkg|DBPath|Include)' "$FAKE_PACMAN_CONF_COPY".Syu | sed -E 's/[[:space:]]*=.*//' | paste -sd' ')"
check "apply --system: the temp config is gone afterwards" "" "$(find "$PKG_RECOVERY_DIR/tmp" -mindepth 1 2>/dev/null | paste -sd' ')"
check "apply --system: the real config is unchanged" "$conf_sum" "$(sha256sum < "$PKG_PACMAN_CONF")"
check "apply --system: nothing in XDG_RUNTIME_DIR / TMPDIR / the user's home" "" "$(find "$XDG_RUNTIME_DIR" "$TMPDIR" "$PKG_USER_HOME" -mindepth 1 | paste -sd' ')"
# the temp config is also removed when the update fails
new_apply_env
FAKE_PACMAN_SYU_EXIT=1 "$PKG_UPDATE" apply --system </dev/null >/dev/null 2>&1
check "apply --system, failed update: temp config removed" "" "$(find "$PKG_RECOVERY_DIR/tmp" -mindepth 1 2>/dev/null | paste -sd' ')"

# the pending gate
new_apply_env
mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"awaiting-verification","started":"2026-10-01T00:00:00Z"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
pend_before=$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json"); kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "gate: unpromoted pending is exit 4" 4 "$rc"
check "gate: pacman was never called" no "$([ -e "$FAKE_PACMAN_LOG" ] || [ -e "$FAKE_PACMAN_ENVLOG" ] && echo yes || echo no)"
check "gate: the message names discard and promote" 2 "$(grep -c -i -E 'discard|promote' "$env_dir/err")"
check "gate: pending and known-good unchanged" "$pend_before $kg_before" "$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json") $(kg_fingerprint)"
check "gate: no paccache, no refresh" no "$([ -e "$env_dir/paccache.log" ] || [ -e "$env_dir/qs.log" ] && echo yes || echo no)"
# a failed pending gates as well
echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "gate: a failed pending gates too" 4 "$?"
# an empty pending directory gates
rm "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" apply --system </dev/null >/dev/null 2>&1; check "gate: an empty pending directory gates" 4 "$?"
echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"

# --force bypasses only the gate; known-good is never rewritten, even when it no longer matches
sed -i 's/^linux 6.15.3.arch1-1$/linux 6.14.0.arch1-1/' "$FAKE_PACMAN_DB"   # installed state moved away from known-good
sleep 1.1; kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply --force </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "force: proceeds, exit 0" 0 "$rc"
check "force: known-good directory untouched (inode, mtime, contents) although it no longer matches" "$kg_before" "$(kg_fingerprint)"
check "force: pending replaced by the new record" awaiting-verification "$(pending_state)"
check "force: the replaced pending is kept in the record" failed "$(jq -r '.replaced.state' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "force: pacman -Syuw and -Syu ran" 2 "$(pacman_calls | grep -c .)"
check "force: no leftovers" "" "$(leftovers)"
# --force over a pending that is a symlink into known-good: replaced, never written through
new_apply_env
ln -s known-good "$PKG_RECOVERY_DIR/pending"; kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply --force </dev/null >/dev/null 2>&1; rc=$?
check "force over a pending symlink: exit 0, known-good untouched, pending is a real directory" "0 $kg_before no" \
    "$rc $(kg_fingerprint) $([ -L "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
check "force over a pending symlink: the record is in pending/" awaiting-verification "$(pending_state)"
# --force with no known-good at all: nothing to roll back to, refuse
new_apply_env
rm -rf "$PKG_RECOVERY_DIR/known-good"; mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" apply --force </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "force without known-good: exit 1" 1 "$rc"
check "force without known-good: pacman not called, pending kept" "no failed" "$([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $(pending_state)"

# first checkpoint: no known-good yet, archives in the cache
new_apply_env
rm -rf "$PKG_RECOVERY_DIR/known-good"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "first checkpoint: exits 0" 0 "$rc"
check "first checkpoint: known-good has the 4 protected packages as hardlinks" "4 4" \
    "$(jq '.packages|length' "$PKG_RECOVERY_DIR/known-good/manifest.json") $(find "$PKG_RECOVERY_DIR/known-good/archives" -type f -links 2 | wc -l)"
check "first checkpoint: it describes the state BEFORE the update" "linux 6.15.3.arch1-1" \
    "$(jq -r '.packages[] | select(.name == "linux") | "\(.name) \(.version)"' "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "first checkpoint: pending written after it" awaiting-verification "$(pending_state)"
check "first checkpoint: no leftovers" "" "$(leftovers)"
# an outdated known-good (installed set moved on outside the tool, no pending) is replaced by the current state
new_apply_env
jq '(.packages[] | select(.name == "grub") | .version) = "2:2.15-1"' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m" && cp "$env_dir/m" "$PKG_RECOVERY_DIR/known-good/manifest.json"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "stale known-good: exits 0" 0 "$?"
check "stale known-good: replaced by the installed state" "2:2.16-1" "$(jq -r '.packages[] | select(.name == "grub") | .version' "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "stale known-good: no leftovers" "" "$(leftovers)"

# missing archive: fetch declined (no terminal), fails or is not in the Archive -> no update
new_apply_env
rm "$PKG_CACHE_DIR"/grub-*; jq '(.packages[] | select(.name == "grub") | .version) = "2:2.15-1"' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m" && cp "$env_dir/m" "$PKG_RECOVERY_DIR/known-good/manifest.json"
archive_pkg grub 2:2.16-1 grub 2:2.16-1
kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "missing archive, fetch declined: exit 1" 1 "$rc"
check "missing archive, fetch declined: names the package" 1 "$(grep -c 'grub 2:2.16-1' "$env_dir/err")"
check "missing archive, fetch declined: no pacman update call, no pending" "no no" "$([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
check "missing archive, fetch declined: known-good unchanged" "$kg_before" "$(kg_fingerprint)"
rm -rf "$env_dir/archive"
"$PKG_UPDATE" apply --yes </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "missing archive, not in the Archive: exit 1" 1 "$rc"
check "missing archive, not in the Archive: no update, known-good unchanged" "no $kg_before" "$([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $(kg_fingerprint)"
archive_pkg grub 2:2.16-1 grub 2:2.16-1
"$PKG_UPDATE" apply --yes </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "missing archive, --yes passes through to the fetch: exit 0" 0 "$rc"
check "missing archive, --yes: the archive was fetched and known-good rebuilt" "2:2.16-1" "$(jq -r '.packages[] | select(.name == "grub") | .version' "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "missing archive, --yes: updated afterwards" awaiting-verification "$(pending_state)"
# a split family with one member missing: refuse naming it, no partial checkpoint
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; rm "$PKG_CACHE_DIR"/linux-firmware-amd-*
"$PKG_UPDATE" apply --yes </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "missing family member: exit 1, named" "1 yes" "$rc $([ "$(grep -c 'linux-firmware-amd' "$env_dir/err")" -ge 1 ] && echo yes)"
check "missing family member: no known-good, no pending, no pacman call, no leftovers" "no no no " \
    "$([ -e "$PKG_RECOVERY_DIR/known-good" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $(leftovers)"

# download failure: -Syu never runs, pending failed, known-good untouched, no paccache
new_apply_env
kg_before=$(kg_fingerprint)
FAKE_PACMAN_SYUW_EXIT=1 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "-Syuw fails: exit 1" 1 "$rc"
check "-Syuw fails: -Syu never called" "--config CONF --noconfirm -Syuw" "$(pacman_calls)"
check "-Syuw fails: pending failed with the exit status" "failed 1" "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "-Syuw fails: finished is set, nothing changed" "true 0" "$(jq -r '"\(.finished != null) \(.packages | length)"' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "-Syuw fails: known-good unchanged" "$kg_before" "$(kg_fingerprint)"
check "-Syuw fails: no paccache" no "$([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
check "-Syuw fails: no leftovers" "" "$(leftovers)"
# the next apply is held by the failed pending
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "after a failed apply the next one is gated" 4 "$?"

# update failure after a partial change: the change is recorded
new_apply_env
FAKE_PACMAN_SYU_EXIT=2 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "-Syu fails: exit 1" 1 "$rc"
check "-Syu fails: pending failed with exit 2 and the partial changes" "failed 2 6" \
    "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json") $(jq '.packages|length' "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "-Syu fails: no paccache" no "$([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
# pacman -Q fails before anything: abort, nothing written
new_apply_env
FAKE_PACMAN_EXIT=1 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "pacman -Q fails at the start: exit 1, no update, no pending" "1 no no" "$rc $([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
# pacman -Q fails after a successful update: failed, never "awaiting-verification" built on nothing
new_apply_env
FAKE_PACMAN_Q_FAIL_AFTER_UPDATE=1 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "-Q fails after the update: exit 1, pending failed with an error, no paccache" "1 failed 1 no" \
    "$rc $(pending_state) $(jq '.error != null' "$PKG_RECOVERY_DIR/pending/manifest.json" | grep -c true) $([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"

# paccache and the statusbar refresh are best effort
new_apply_env
STUB_PACCACHE_EXIT=1 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "paccache failure: apply still succeeds" "0 awaiting-verification" "$rc $(pending_state)"
check "paccache failure: a warning" 1 "$(grep -c -i 'paccache' "$env_dir/err")"
new_apply_env; PKG_PACCACHE="$env_dir/no-such-paccache" "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "paccache missing: apply still succeeds" "0 awaiting-verification" "$? $(pending_state)"
new_apply_env
STUB_QS_EXIT=1 "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "qs failure is ignored" "0 awaiting-verification" "$? $(pending_state)"
check "qs failure: no complaint" 0 "$(grep -c -i -w 'qs' "$env_dir/err")"
new_apply_env; PKG_QS="$env_dir/no-such-qs" "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "qs missing: skipped silently" "0 0" "$? $(grep -c -i -w 'qs' "$env_dir/err")"
new_apply_env
printf '#!/usr/bin/env bash\nsleep 30\n' > "$env_dir/qs"
start=$SECONDS; PKG_QS_TIMEOUT=1 "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; rc=$?
check "qs hangs: apply returns after the timeout" "0 yes" "$rc $([ $((SECONDS - start)) -lt 15 ] && echo yes || echo no)"

# lock held / pacman running: exit 3 before any pacman call
new_apply_env
( acquire_lock; "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1 ); check "apply with the lock held: exit 3" 3 "$?"
touch "$env_dir/dblck"; PKG_PACMAN_DBLOCK="$env_dir/dblck" "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "apply while pacman runs: exit 3" 3 "$?"
check "locked: pacman never called, nothing written" "no no" "$([ -e "$FAKE_PACMAN_LOG" ] || [ -e "$FAKE_PACMAN_ENVLOG" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
# the lock is not inherited by pacman: a pacman child left running does not hold it
# storage checks
new_apply_env
PKG_FREE_BYTES=1000 "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "too little free space: exit 1, says so, nothing done" "1 1 no" "$rc $(grep -c -i 'free space' "$env_dir/err") $([ -e "$FAKE_PACMAN_ENVLOG" ] && echo yes || echo no)"
new_apply_env
dev_shm=/dev/shm
if [ -d "$dev_shm" ] && [ -w "$dev_shm" ] && [ "$(stat -c %d "$dev_shm")" != "$(stat -c %d "$tmp")" ]; then
    shm_cache=$(mktemp -d "$dev_shm/pkgtest.XXXXXX")
    PKG_CACHE_DIR="$shm_cache" "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
    rm -rf "$shm_cache"
    check "cache on another filesystem: exit 1, says so, nothing done" "1 1 no" "$rc $(grep -c -i 'filesystem' "$env_dir/err") $([ -e "$FAKE_PACMAN_ENVLOG" ] && echo yes || echo no)"
fi
new_apply_env
PKG_CACHE_DIR="$env_dir/no-cache" "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "no cache dir: exit 1" 1 "$?"
if [ "$(id -u)" != 0 ]; then
    new_apply_env; mkdir -p "$PKG_RECOVERY_DIR/logs"; : > "$PKG_RECOVERY_DIR/lock"; chmod 555 "$PKG_RECOVERY_DIR"
    "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
    chmod 755 "$PKG_RECOVERY_DIR"
    check "recovery dir not writable: exit 1, nothing done" "1 no" "$rc $([ -e "$FAKE_PACMAN_ENVLOG" ] && echo yes || echo no)"
fi

# the update lock is not inherited by a long-lived child of pacman (a daemon a hook started)
new_apply_env
cat > "$env_dir/daemon-pacman" <<STUB
#!/usr/bin/env bash
case "\$*" in *-Syu\ *|*-Syu) ( sleep 30 >/dev/null 2>&1 & echo \$! > "$env_dir/daemon.pid" ) ;; esac
exec "$HERE/fakes/pacman" "\$@"
STUB
chmod +x "$env_dir/daemon-pacman"
( PKG_PACMAN="$env_dir/daemon-pacman"; acquire_lock; pkg_apply >/dev/null 2>&1; echo "$?" > "$env_dir/rc" )
check "daemon test: apply succeeded" 0 "$(cat "$env_dir/rc")"
check "daemon test: the child is really running" alive "$(kill -0 "$(cat "$env_dir/daemon.pid")" 2>/dev/null && echo alive || echo gone)"
trylock; check "apply: the lock is not kept alive by a background child of pacman" 0 "$?"
kill "$(cat "$env_dir/daemon.pid")" 2>/dev/null

# pending record atomicity and the jq failure paths: a jq that fails on the pending record
shim_jq() {  # shim_jq FAILING_CALL: jq wrapper failing on the Nth call that builds a pending record (arg "mode")
    local real; real=$(command -v jq)
    mkdir -p "$env_dir/bin"
    cat > "$env_dir/bin/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
    if [ "\$a" = mode ]; then
        n=\$(cat "$env_dir/jq-count" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$env_dir/jq-count"
        [ "\$n" = "$1" ] && { echo "jq: injected failure" >&2; exit 5; }
    fi
done
exec "$real" "\$@"
STUB
    chmod +x "$env_dir/bin/jq"
}
new_apply_env; shim_jq 1; kg_before=$(kg_fingerprint)
PATH="$env_dir/bin:$PATH" "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "jq fails on the first record: exit 1, nothing updated, no pending" "1 no no" "$rc $([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
check "jq fails on the first record: known-good unchanged, no leftovers" "$kg_before " "$(kg_fingerprint) $(leftovers)"
new_apply_env; shim_jq 2
PATH="$env_dir/bin:$PATH" "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "jq fails on the final record: exit 1" 1 "$rc"
check "jq fails on the final record: pending is valid JSON saying failed" "failed" "$(jq -r .state "$PKG_RECOVERY_DIR/pending/manifest.json")"
check "jq fails on the final record: no leftovers" "" "$(leftovers)"
check "jq fails on the final record: paccache not run" no "$([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"

# interrupted. Policy: pacman soft-stops on INT/HUP but dies on TERM (leaving db.lck), so apply never sends TERM
# and never interrupts the -Syu transaction; during -Syuw (download only) it forwards INT.
interrupted_apply() {  # interrupted_apply syu|syuw SIGNAL [apply args...]: leaves INT_RC, INT_ELAPSED; env_dir/started(.pid)
    local phase=$1 sig=$2 pid; shift 2
    local -a fenv
    rm -f "$env_dir/started" "$env_dir/started.pid"
    if [ "$phase" = syuw ]; then
        fenv=(FAKE_PACMAN_SYUW_SLEEP=20 FAKE_PACMAN_SYUW_STARTED="$env_dir/started")
    else
        fenv=(FAKE_PACMAN_SLEEP=${INT_SYU_SLEEP:-3} FAKE_PACMAN_STARTED="$env_dir/started")
    fi
    env "${fenv[@]}" perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' "$PKG_UPDATE" apply "$@" </dev/null >"$env_dir/out" 2>"$env_dir/err" &
    INT_PID=$!
    for _ in $(seq 100); do [ -e "$env_dir/started" ] && break; sleep 0.05; done
    [ -z "${INT_KILL_TEE:-}" ] || { pkill -KILL -P "$INT_PID" -x tee; sleep 0.2; }
    start=$SECONDS
    kill -s "$sig" "$INT_PID"; { wait "$INT_PID"; } 2>/dev/null; INT_RC=$?
    INT_ELAPSED=$((SECONDS - start))
}
unset INT_KILL_TEE
sigcode() { case $1 in TERM) echo 143 ;; INT) echo 130 ;; HUP) echo 129 ;; esac; }
# during -Syu: the signal is remembered, pacman runs to its end, the record has the real outcome, then the signal is re-raised
for sig in TERM INT HUP; do
    new_apply_env; kg_before=$(kg_fingerprint)
    interrupted_apply syu $sig --system
    check "$sig during -Syu: apply dies by the signal afterwards ($(sigcode $sig))" "$(sigcode $sig)" "$INT_RC"
    check "$sig during -Syu: apply waited for pacman (did not stop it)" yes "$([ "$INT_ELAPSED" -ge 1 ] && echo yes || echo no)"
    check "$sig during -Syu: pacman finished, no db.lck left behind" "gone no" "$(kill -0 "$(cat "$env_dir/started.pid")" 2>/dev/null && echo alive || echo gone) $([ -e "$PKG_PACMAN_DBLOCK" ] && echo yes || echo no)"
    check "$sig during -Syu: the record has pacman's real outcome" "awaiting-verification 0 6" \
        "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json") $(jq '.packages | length' "$PKG_RECOVERY_DIR/pending/manifest.json" 2>/dev/null)"
    check "$sig during -Syu: known-good unchanged" "$kg_before" "$(kg_fingerprint)"
    check "$sig during -Syu: no temp leftovers, temp config removed" "" "$(leftovers)$(find "$PKG_RECOVERY_DIR/tmp" -mindepth 1 2>/dev/null | paste -sd' ')"
    check "$sig during -Syu: no paccache" no "$([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
done
# INT/HUP that reach pacman itself (a terminal's process group): pacman stops softly, the record says failed
for sig in INT HUP; do
    new_apply_env; kg_before=$(kg_fingerprint)
    rm -f "$env_dir/started" "$env_dir/started.pid"
    FAKE_PACMAN_SLEEP=20 FAKE_PACMAN_STARTED="$env_dir/started" perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err" &
    pid=$!; for _ in $(seq 100); do [ -e "$env_dir/started" ] && break; sleep 0.05; done
    kill -s "$sig" "$(cat "$env_dir/started.pid")"; wait "$pid"; rc=$?
    check "$sig to pacman during -Syu: apply exits 1 (not by a signal)" 1 "$rc"
    check "$sig to pacman during -Syu: failed, pacman_exit $(sigcode $sig), changes recorded, no db.lck" "failed $(sigcode $sig) 6 no" \
        "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json") $(jq '.packages | length' "$PKG_RECOVERY_DIR/pending/manifest.json") $([ -e "$PKG_PACMAN_DBLOCK" ] && echo yes || echo no)"
    check "$sig to pacman during -Syu: known-good unchanged, no paccache" "$kg_before no" "$(kg_fingerprint) $([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
done
# during -Syuw (download only): INT goes to pacman for every signal; the record is failed, known-good intact
for sig in TERM INT HUP; do
    new_apply_env; kg_before=$(kg_fingerprint)
    interrupted_apply syuw $sig --system
    check "$sig during -Syuw: apply dies by the signal ($(sigcode $sig))" "$(sigcode $sig)" "$INT_RC"
    check "$sig during -Syuw: prompt (pacman stopped softly)" yes "$([ "$INT_ELAPSED" -lt 10 ] && echo yes || echo no)"
    check "$sig during -Syuw: pacman gone, db.lck released (INT, not TERM, was sent)" "gone no" "$(kill -0 "$(cat "$env_dir/started.pid")" 2>/dev/null && echo alive || echo gone) $([ -e "$PKG_PACMAN_DBLOCK" ] && echo yes || echo no)"
    check "$sig during -Syuw: pending failed with pacman's exit 130, nothing changed" "failed 130 0" \
        "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json") $(jq '.packages | length' "$PKG_RECOVERY_DIR/pending/manifest.json" 2>/dev/null)"
    check "$sig during -Syuw: -Syu never started, known-good unchanged" "1 $kg_before" "$(pacman_calls | grep -c .) $(kg_fingerprint)"
    check "$sig during -Syuw: no leftovers, temp config removed, no paccache" "no" "$([ -n "$(leftovers)$(find "$PKG_RECOVERY_DIR/tmp" -mindepth 1 2>/dev/null)" ] && echo yes || echo no)$([ -e "$env_dir/paccache.log" ] && echo yes)"
done
# the log's tee dies (terminal closed): SIGPIPE must not kill apply before the record is written
for phase in syuw syu; do
    new_apply_env
    INT_KILL_TEE=1 interrupted_apply $phase TERM --system
    if [ "$phase" = syuw ]; then
        check "tee dead, TERM during -Syuw: record is failed (not running), apply dies by TERM, not SIGPIPE" "failed 143" "$(pending_state) $INT_RC"
    else
        check "tee dead, TERM during -Syu: record is the real outcome, apply dies by TERM, not SIGPIPE" "awaiting-verification 143" "$(pending_state) $INT_RC"
    fi
    check "tee dead, $phase: cleanup done (temp config removed)" "" "$(find "$PKG_RECOVERY_DIR/tmp" -mindepth 1 2>/dev/null | paste -sd' ')"
done
unset INT_KILL_TEE
# interrupted before the checkpoint finished (a slow fetch): known-good unchanged, no pending
new_apply_env; rm "$PKG_CACHE_DIR"/grub-*
jq '(.packages[] | select(.name == "grub") | .version) = "2:2.15-1"' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m" && cp "$env_dir/m" "$PKG_RECOVERY_DIR/known-good/manifest.json"
archive_pkg grub 2:2.16-1 grub 2:2.16-1
printf '#!/usr/bin/env bash\ntouch "%s/in-verify"; sleep 20\n' "$env_dir" > "$env_dir/slow-verify"; chmod +x "$env_dir/slow-verify"
kg_before=$(kg_fingerprint)
PKG_VERIFY="$env_dir/slow-verify" "$PKG_UPDATE" apply --yes </dev/null >/dev/null 2>&1 &
pid=$!; for _ in $(seq 100); do [ -e "$env_dir/in-verify" ] && break; sleep 0.05; done
kill -TERM "$pid"; wait "$pid"; rc=$?
check "TERM before the checkpoint: 143" 143 "$rc"
check "TERM before the checkpoint: known-good unchanged, no pending, no pacman update, no leftovers" "$kg_before no no " \
    "$(kg_fingerprint) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no) $(leftovers)"
# the library function keeps the caller's traps and restores them
new_apply_env
out=$( trap 'echo mine' TERM; trap 'echo mine-hup' HUP; pkg_apply >/dev/null 2>&1; trap -p TERM HUP )   # (INT may be ignored from the start when the suite runs as a background job)
check "pkg_apply restores the caller's TERM/HUP traps" "trap -- 'echo mine' SIGTERM
trap -- 'echo mine-hup' SIGHUP" "$out"
out=$( pkg_apply >/dev/null 2>&1; trap -p TERM HUP PIPE )
check "pkg_apply leaves no trap behind when the caller had none" "" "$out"
# a caller's trap gets the re-raised signal
new_apply_env
( trap 'echo caller-got-term > "'"$env_dir"'/caller"; exit 7' TERM
  FAKE_PACMAN_SYUW_SLEEP=20 FAKE_PACMAN_SYUW_STARTED="$env_dir/started" pkg_apply >/dev/null 2>&1 ) &
pid=$!; for _ in $(seq 100); do [ -e "$env_dir/started" ] && break; sleep 0.05; done
kill -TERM "$pid"; wait "$pid"; rc=$?
check "pkg_apply: the caller's TERM trap runs after the cleanup" "caller-got-term" "$(cat "$env_dir/caller" 2>/dev/null)"
check "pkg_apply: and the pending says failed" failed "$(pending_state)"

# discard
new_apply_env
mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"; : > "$PKG_RECOVERY_DIR/pending/extra"
kg_before=$(kg_fingerprint)
out=$("$PKG_UPDATE" discard </dev/null 2>"$env_dir/err"); rc=$?
check "discard: exit 0" 0 "$rc"
check "discard: pending gone, known-good untouched, no leftovers" "no $kg_before " "$([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $(kg_fingerprint) $(leftovers)"
check "discard: LOG= first, log exists" 1 "$(head -n 1 <<<"$out" | grep -c '^LOG=')"
out=$("$PKG_UPDATE" discard </dev/null 2>&1); rc=$?
check "discard with nothing pending: exit 0 and says so" "0 1" "$rc $(grep -c -i 'nothing' <<<"$out")"
check "discard: known-good still there" "$kg_before" "$(kg_fingerprint)"
# a pending that is a symlink into known-good: only the link goes
ln -s known-good "$PKG_RECOVERY_DIR/pending"
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1; rc=$?
check "discard: a pending symlink is removed, its target is not" "0 no $kg_before" "$rc $([ -L "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $(kg_fingerprint)"
mkdir "$PKG_RECOVERY_DIR/pending"
( acquire_lock; "$PKG_UPDATE" discard </dev/null >/dev/null 2>&1 ); check "discard with the lock held: exit 3" 3 "$?"
check "discard with the lock held: pending kept" yes "$([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
# after a discard apply goes ahead again
echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; g1=$?
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; g2=$?
check "apply is gated before discard and runs after" "4 0" "$g1 $g2"

# --- fix round 1 ---------------------------------------------------------------------------------
# known-good.prev: a mismatching known-good is superseded, never lost
real_known_good() { checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; }
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
old_created=$(jq -r .created "$PKG_RECOVERY_DIR/known-good/manifest.json")
old_manifest_sum=$(sha256sum < "$PKG_RECOVERY_DIR/known-good/manifest.json")
sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"; : > "$PKG_CACHE_DIR/grub-2:2.15-1-x86_64.pkg.tar.zst"
mkdir "$PKG_RECOVERY_DIR/known-good.prev"; : > "$PKG_RECOVERY_DIR/known-good.prev/older-generation"
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "prev: apply succeeds after a stale known-good" 0 "$rc"
check "prev: known-good is the installed state" "2:2.15-1" "$(jq -r '.packages[] | select(.name == "grub") | .version' "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "prev: known-good.prev holds the old manifest" "$old_manifest_sum" "$(sha256sum < "$PKG_RECOVERY_DIR/known-good.prev/manifest.json")"
check "prev: ... and the old archives, still hardlinks of the cache files (no extra space)" "4 4" \
    "$(ls "$PKG_RECOVERY_DIR/known-good.prev/archives" | wc -l) $(find "$PKG_RECOVERY_DIR/known-good.prev/archives" -type f -links +1 | wc -l)"
check "prev: only one generation (the older .prev is gone)" no "$([ -e "$PKG_RECOVERY_DIR/known-good.prev/older-generation" ] && echo yes || echo no)"
check "prev: loud warning names the old date and the differing package" "1 1" \
    "$(grep -c -F "created $old_created" "$env_dir/err") $(grep -c -F 'grub 2:2.16-1 -> 2:2.15-1' "$env_dir/err")"
check "prev: the old grub archive is still there" yes "$([ -e "$PKG_RECOVERY_DIR/known-good.prev/archives/grub-2:2.16-1-x86_64.pkg.tar.zst" ] && echo yes || echo no)"
check "prev: no leftovers" "" "$(leftovers)"
# a known-good that matches: .prev untouched, no warning
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
mkdir "$PKG_RECOVERY_DIR/known-good.prev"; : > "$PKG_RECOVERY_DIR/known-good.prev/keep-me"
fp=$(find "$PKG_RECOVERY_DIR/known-good.prev" -printf '%p %i %T@\n' | sort | sha256sum); kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "prev: a matching known-good leaves .prev and known-good alone, no warning" "$fp $kg_before 0" \
    "$(find "$PKG_RECOVERY_DIR/known-good.prev" -printf '%p %i %T@\n' | sort | sha256sum) $(kg_fingerprint) $(grep -c -i 'does not match' "$env_dir/err")"
# first run: nothing to keep
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "prev: first checkpoint creates no .prev and no warning" "no 0" "$([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no) $(grep -c -i 'does not match' "$env_dir/err")"
# a failed rebuild keeps the old known-good in place and creates / replaces no .prev
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"      # grub 2:2.15-1 has no archive anywhere
mkdir "$PKG_RECOVERY_DIR/known-good.prev"; : > "$PKG_RECOVERY_DIR/known-good.prev/keep-me"
kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply --yes </dev/null >/dev/null 2>&1; rc=$?
check "prev: a rebuild that fails (archive missing): exit 1" 1 "$rc"
check "prev: ... old known-good in place, old .prev untouched, nothing else" "$kg_before yes" "$(kg_fingerprint) $([ -e "$PKG_RECOVERY_DIR/known-good.prev/keep-me" ] && echo yes || echo no)"
# the rebuild itself failing after the archives were found (here: checkpoint_build is made to fail)
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"; : > "$PKG_CACHE_DIR/grub-2:2.15-1-x86_64.pkg.tar.zst"
kg_before=$(kg_fingerprint)
( checkpoint_build() { echo "forced failure" >&2; return 1; }; pkg_apply >/dev/null 2>&1 ); rc=$?
check "prev: checkpoint_build failing: exit 1, old known-good intact, no .prev, no leftovers, no pacman update" "1 $kg_before no  no" \
    "$rc $(kg_fingerprint) $([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no) $(leftovers) $([ -e "$FAKE_PACMAN_LOG" ] && echo yes || echo no)"
# the pending / --force paths never touch .prev
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
mkdir "$PKG_RECOVERY_DIR/known-good.prev"; : > "$PKG_RECOVERY_DIR/known-good.prev/keep-me"
mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"
fp=$(find "$PKG_RECOVERY_DIR/known-good.prev" -printf '%p %i %T@\n' | sort | sha256sum); kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; g=$?
"$PKG_UPDATE" apply --force </dev/null >/dev/null 2>&1; f=$?
check "prev: gate (4) and --force (0) leave .prev and known-good alone" "4 0 $fp $kg_before" \
    "$g $f $(find "$PKG_RECOVERY_DIR/known-good.prev" -printf '%p %i %T@\n' | sort | sha256sum) $(kg_fingerprint)"

# nothing changed: no empty record to verify
new_apply_env; unset FAKE_PACMAN_AFTER; kg_before=$(kg_fingerprint)
out=$("$PKG_UPDATE" apply </dev/null 2>"$env_dir/err"); rc=$?
check "no change: exit 0, says nothing to update" "0 1" "$rc $(grep -c 'nothing to update' <<<"$out")"
check "no change: no pending record, known-good untouched, no paccache, no leftovers" "no $kg_before no " \
    "$([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $(kg_fingerprint) $([ -e "$env_dir/paccache.log" ] && echo yes || echo no) $(leftovers)"
check "no change: both pacman steps ran, the statusbar was refreshed" "2 ipc call updates refresh" "$(pacman_calls | grep -c .) $(cat "$env_dir/qs.log")"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "no change: the next apply is not gated" 0 "$?"
# ... but a failing step keeps its failed record even when nothing changed
new_apply_env; unset FAKE_PACMAN_AFTER
FAKE_PACMAN_SYU_EXIT=2 "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "no change but -Syu failed: the failed record stays" "failed 2" "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json")"
# --force over an earlier unverified pending: that record must stay a gate, so it is kept (replaced field)
new_apply_env; unset FAKE_PACMAN_AFTER
mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"awaiting-verification","packages":[{"name":"linux","from":"1","to":"2"}]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" apply --force </dev/null >/dev/null 2>&1
check "no change, --force over a pending: the pending stays (awaiting-verification, old record under replaced)" "awaiting-verification linux" \
    "$(pending_state) $(jq -r '.replaced.packages[0].name' "$PKG_RECOVERY_DIR/pending/manifest.json")"

# stale temp dirs from a hard kill are swept
new_apply_env
mkdir -p "$PKG_RECOVERY_DIR/tmp/apply.OLD123" "$PKG_RECOVERY_DIR/known-good.prev.new.99" "$PKG_RECOVERY_DIR/known-good.prev.old.99"
: > "$PKG_RECOVERY_DIR/tmp/apply.OLD123/pacman.conf"; : > "$PKG_RECOVERY_DIR/tmp/unrelated"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; rc=$?
check "sweep: stale apply.* and prev temp dirs are removed, other files stay" "0 no no no yes" \
    "$rc $([ -e "$PKG_RECOVERY_DIR/tmp/apply.OLD123" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/known-good.prev.new.99" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/known-good.prev.old.99" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/tmp/unrelated" ] && echo yes || echo no)"

# the statusbar refresh runs as the invoking user when apply is root (pkexec: HOME=/root)
me=$(id -u); mygid=$(id -g)
setup_refresh_env() {
    new_apply_env
    printf '#!/usr/bin/env bash\necho "HOME=$HOME XDG=$XDG_RUNTIME_DIR UID=$(id -u) $*" >> "%s/qs2.log"\n' "$env_dir" > "$env_dir/qs"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/setpriv.log"\nwhile [[ $1 == --* ]]; do shift; done\nexec "$@"\n' "$env_dir" > "$env_dir/setpriv"
    chmod +x "$env_dir/qs" "$env_dir/setpriv"
    export PKG_SETPRIV="$env_dir/setpriv"
}
setup_refresh_env
PKG_TEST_EUID=0 PKEXEC_UID=$me HOME=/root "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; rc=$?
check "refresh as root: apply succeeds" 0 "$rc"
check "refresh as root: through setpriv with the invoking user's uid/gid and groups" "--reuid=$me --regid=$mygid --init-groups env HOME=$PKG_USER_HOME $env_dir/qs ipc call updates refresh" "$(cat "$env_dir/setpriv.log")"
check "refresh as root: qs sees the user's HOME and XDG_RUNTIME_DIR" "HOME=$PKG_USER_HOME XDG=$XDG_RUNTIME_DIR UID=$me ipc call updates refresh" "$(cat "$env_dir/qs2.log")"
setup_refresh_env
PKG_TEST_EUID=0 "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "refresh as root without PKEXEC_UID: skipped (qs is never run as root)" "no no 0" "$([ -e "$env_dir/qs2.log" ] && echo yes || echo no) $([ -e "$env_dir/setpriv.log" ] && echo yes || echo no) $?"
setup_refresh_env
PKG_TEST_EUID=0 PKEXEC_UID=0 "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "refresh as root with PKEXEC_UID=0: skipped" no "$([ -e "$env_dir/qs2.log" ] && echo yes || echo no)"
setup_refresh_env
PKG_TEST_EUID=0 PKEXEC_UID=$me PKG_USER_HOME= "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "refresh as root without PKG_USER_HOME: skipped" no "$([ -e "$env_dir/qs2.log" ] && echo yes || echo no)"
setup_refresh_env
PKG_SETPRIV="$env_dir/no-setpriv" PKG_TEST_EUID=0 PKEXEC_UID=$me "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "refresh as root without setpriv: skipped" "0 no" "$? $([ -e "$env_dir/qs2.log" ] && echo yes || echo no)"
setup_refresh_env
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "refresh not root: qs runs directly as the caller (no setpriv)" "no 1" "$([ -e "$env_dir/setpriv.log" ] && echo yes || echo no) $(grep -c "HOME=$HOME XDG=$XDG_RUNTIME_DIR UID=$me" "$env_dir/qs2.log")"
unset PKG_SETPRIV

# --- fix round 2 ---------------------------------------------------------------------------------
# sweep: rollback state is recovered, then the debris goes
mtime_age() { touch -d "$2 seconds ago" "$1"; }   # mtime_age DIR SECONDS
manifest_sum() { sha256sum < "$1/manifest.json" | cut -c1-16; }
# A cut-off checkpoint_build replace: no known-good, known-good.old.* (newest wins)
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
mv "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.old.222"
cp -al "$PKG_RECOVERY_DIR/known-good.old.222" "$PKG_RECOVERY_DIR/known-good.old.111"
jq '.created = "2000-01-01T00:00:00Z"' "$PKG_RECOVERY_DIR/known-good.old.111/manifest.json" > "$env_dir/m"; rm "$PKG_RECOVERY_DIR/known-good.old.111/manifest.json"; cp "$env_dir/m" "$PKG_RECOVERY_DIR/known-good.old.111/manifest.json"
mtime_age "$PKG_RECOVERY_DIR/known-good.old.111" 100; mtime_age "$PKG_RECOVERY_DIR/known-good.old.222" 10
mkdir "$PKG_RECOVERY_DIR/known-good.tmp.333"
want=$(manifest_sum "$PKG_RECOVERY_DIR/known-good.old.222")
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "sweep: known-good missing + known-good.old.*: apply succeeds" 0 "$rc"
check "sweep: the newest .old is put back as known-good (not rebuilt, not lost)" "$want" "$(manifest_sum "$PKG_RECOVERY_DIR/known-good")"
check "sweep: notice printed" 1 "$(grep -c 'recovered known-good from known-good.old.222' "$env_dir/err")"
check "sweep: the other .old and the tmp copy are gone" "" "$(find "$PKG_RECOVERY_DIR" -maxdepth 1 \( -name 'known-good.old.*' -o -name 'known-good.tmp.*' \) | paste -sd' ')"
# no known-good and no old copy: simply the normal checkpoint
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; check "sweep: no known-good and no old copy: normal checkpoint" "0 yes" "$? $([ -s "$PKG_RECOVERY_DIR/known-good/manifest.json" ] && echo yes)"
# known-good.prev missing, known-good.prev.old.* present (cut off between the two renames)
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
cp -al "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.prev.old.55"; want=$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev.old.55")
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "sweep: .prev missing + .prev.old.*: restored as .prev, notice, no debris" "$want 1 " "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev") $(grep -c 'recovered known-good.prev from known-good.prev.old.55' "$env_dir/err") $(find "$PKG_RECOVERY_DIR" -maxdepth 1 -name 'known-good.prev.old.*' | paste -sd' ')"
# cut off after checkpoint_build replaced known-good but before the swap: .prev.new.* is the superseded one
prev_crash_env() {   # known-good = state B (grub 2:2.15-1), $env_dir/old_dir = a complete copy of state A
    new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
    cp -al "$PKG_RECOVERY_DIR/known-good" "$env_dir/old_dir"
    sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"; : > "$PKG_CACHE_DIR/grub-2:2.15-1-x86_64.pkg.tar.zst"
    real_known_good
    A=$(manifest_sum "$env_dir/old_dir"); B=$(manifest_sum "$PKG_RECOVERY_DIR/known-good")
}
prev_crash_env; mv "$env_dir/old_dir" "$PKG_RECOVERY_DIR/known-good.prev.new.77"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "sweep: kill after the checkpoint, before the swap: the superseded copy becomes .prev" "$A $B 1 " \
    "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev") $(manifest_sum "$PKG_RECOVERY_DIR/known-good") $(grep -c 'recovered known-good.prev from known-good.prev.new.77' "$env_dir/err") $(find "$PKG_RECOVERY_DIR" -maxdepth 1 -name 'known-good.prev.*.*' | paste -sd' ')"
# cut off between the two renames: no .prev, .prev.old.* (older generation) and .prev.new.* (newer): the newer wins
prev_crash_env; mv "$env_dir/old_dir" "$PKG_RECOVERY_DIR/known-good.prev.new.77"
mkdir "$PKG_RECOVERY_DIR/known-good.prev.old.76"; echo '{"packages":[]}' > "$PKG_RECOVERY_DIR/known-good.prev.old.76/manifest.json"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "sweep: kill between the renames: .prev = the superseded copy, the older generation is dropped" "$A" "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev")"
# .prev.new.* that equals known-good (kill before checkpoint_build replaced it) or is partial: debris, an existing .prev stays
prev_crash_env; cp -al "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.prev.new.1"
mkdir "$PKG_RECOVERY_DIR/known-good.prev"; echo '{"packages":[]}' > "$PKG_RECOVERY_DIR/known-good.prev/manifest.json"
cp -al "$env_dir/old_dir" "$PKG_RECOVERY_DIR/known-good.prev.new.2"; rm -f "$PKG_RECOVERY_DIR"/known-good.prev.new.2/archives/grub-*   # partial copy
mtime_age "$PKG_RECOVERY_DIR/known-good.prev.new.1" 10; touch "$PKG_RECOVERY_DIR/known-good.prev.new.2"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "sweep: a duplicate or partial .prev.new.* is deleted, the existing .prev stays" "0 no" \
    "$(jq '.packages|length' "$PKG_RECOVERY_DIR/known-good.prev/manifest.json") $(ls "$PKG_RECOVERY_DIR" | grep -c 'prev.new' | sed 's/^0$/no/')"

# _apply_swap_prev: mv -T, never nests, a failure puts the old .prev back
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
cp -al "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/new1"; mkdir "$PKG_RECOVERY_DIR/known-good.prev"; echo '{"x":1}' > "$PKG_RECOVERY_DIR/known-good.prev/manifest.json"
( mv() { [ -n "$MVFAIL" ] && [ "$MVN" = "$MVFAIL" ] && { MVN=x; return 1; }; MVN=$((MVN + 1)); command mv "$@"; }
  MVN=1 MVFAIL=1; _apply_swap_prev "$PKG_RECOVERY_DIR/new1" 2>/dev/null; echo "rc=$?" ) > "$env_dir/o1"
check "swap_prev: the first rename failing: fails, old .prev intact, nothing nested, new copy kept" "rc=1 1 yes no" \
    "$(cat "$env_dir/o1") $(jq .x "$PKG_RECOVERY_DIR/known-good.prev/manifest.json") $([ -d "$PKG_RECOVERY_DIR/new1" ] && echo yes) $([ -e "$PKG_RECOVERY_DIR/known-good.prev/new1" ] && echo yes || echo no)"
( mv() { MVN=$((MVN + 1)); [ "$MVN" = 3 ] && return 1; command mv "$@"; }; MVN=1; _apply_swap_prev "$PKG_RECOVERY_DIR/new1" 2>/dev/null; echo "rc=$?" ) > "$env_dir/o2"
check "swap_prev: the second rename failing puts the old .prev back" "rc=1 1 yes" "$(cat "$env_dir/o2") $(jq .x "$PKG_RECOVERY_DIR/known-good.prev/manifest.json") $([ -d "$PKG_RECOVERY_DIR/new1" ] && echo yes)"
_apply_swap_prev "$PKG_RECOVERY_DIR/new1"
check "swap_prev: normally .prev is the new copy, nothing nested or left" "$(manifest_sum "$PKG_RECOVERY_DIR/known-good") no " \
    "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev") $([ -e "$PKG_RECOVERY_DIR/known-good.prev/new1" ] && echo yes || echo no) $(leftovers)"

# the rename block ignores INT/TERM/HUP and gives the caller's dispositions back
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
sed -i 's/^grub 2:2.16-1$/grub 2:2.15-1/' "$FAKE_PACMAN_DB"; : > "$PKG_CACHE_DIR/grub-2:2.15-1-x86_64.pkg.tar.zst"
out=$( trap 'echo caller-term' TERM
  _apply_swap_prev() { kill -TERM $BASHPID; kill -HUP $BASHPID; echo survived > "$env_dir/survived"; command true; }
  pkg_apply >/dev/null 2>&1; echo "rc=$?"; trap -p TERM )
check "swap block: TERM/HUP during the renames are ignored, the caller's trap is back" "rc=0
trap -- 'echo caller-term' SIGTERM" "$out"
check "swap block: apply carried on after them" yes "$([ -e "$env_dir/survived" ] && echo yes || echo no)"

# a signal that arrives before pacman -Syu is forked: the transaction does not start
new_apply_env
{ ( echo() { builtin echo "$@"; case "$1" in Installing*) kill -TERM $BASHPID ;; esac; }
  pkg_apply >/dev/null 2>&1 ); rc=$?; } 2>/dev/null
check "signal right after the phase change: apply dies by TERM" 143 "$rc"
check "signal right after the phase change: -Syu never started" "1" "$(pacman_calls | grep -c .)"
check "signal right after the phase change: record failed (143), nothing installed" "failed 143 0 no" \
    "$(pending_state) $(jq -r .pacman_exit "$PKG_RECOVERY_DIR/pending/manifest.json") $(jq '.packages|length' "$PKG_RECOVERY_DIR/pending/manifest.json") $([ -e "$PKG_PACMAN_DBLOCK" ] && echo yes || echo no)"
check "signal right after the phase change: no leftovers" "" "$(leftovers)"

# _apply_pacman never spins: a status below 128 ends the wait even if kill -0 still "finds" the pid (reuse)
RUNLIBS="source '$HERE/../lib.sh'; source '$HERE/../scripts/pkg-lib.sh'"
out=$(timeout 10 bash -c "$RUNLIBS; kill() { [ \"\$1\" = -0 ] && return 0; builtin kill \"\$@\"; }; PKG_PACMAN=false; _apply_pacman -Syu; echo rc=\$?" 2>&1); rc=$?
check "_apply_pacman: pid 'reused' (kill -0 succeeds): no busy loop, pacman's own status kept" "0 rc=1" "$rc $out"
printf '#!/usr/bin/env bash\nexit 7\n' > "$env_dir/exit7"; chmod +x "$env_dir/exit7"
out=$(timeout 10 bash -c "$RUNLIBS; PKG_PACMAN='$env_dir/exit7'; _apply_pacman; echo rc=\$?" 2>&1)
check "_apply_pacman: plain exit status" "rc=7" "$out"

# the test seam can only add root-ness: a real root (user namespace) with PKG_TEST_EUID=1000 is still root
if unshare -r true 2>/dev/null; then
    printf '#!/usr/bin/env bash\necho ran >> "%s/qs-as-root.log"\n' "$env_dir" > "$env_dir/qs"; chmod +x "$env_dir/qs"
    printf '#!/usr/bin/env bash\necho called >> "%s/pkexec-called"\n' "$env_dir" > "$env_dir/pkexec"; chmod +x "$env_dir/pkexec"
    unshare -r bash -c "$RUNLIBS; export PKG_QS='$env_dir/qs' PKG_TEST_EUID=1000; unset PKEXEC_UID; _apply_refresh_statusbar" >/dev/null 2>&1
    check "real root + PKG_TEST_EUID=1000: the refresh is skipped without PKEXEC_UID (qs never runs as root)" no "$([ -e "$env_dir/qs-as-root.log" ] && echo yes || echo no)"
    unshare -r bash -c "$RUNLIBS; export PKG_TEST_EUID=1000 PKG_PKEXEC='$env_dir/pkexec'; unset PKG_NO_ELEVATE; elevate /nonexistent x; echo \"rc=\$?\"" > "$env_dir/o3" 2>&1
    check "real root + PKG_TEST_EUID=1000: elevate does not re-exec" "rc=0 no" "$(cat "$env_dir/o3") $([ -e "$env_dir/pkexec-called" ] && echo yes || echo no)"
fi

# --- fix round 3: a failed restore keeps its source ---------------------------------------------
prev_crash_env; mv "$env_dir/old_dir" "$PKG_RECOVERY_DIR/known-good.prev.new.77"
mkdir "$PKG_RECOVERY_DIR/known-good.prev.old.55"; cp "$PKG_RECOVERY_DIR/known-good.prev.new.77/manifest.json" "$PKG_RECOVERY_DIR/known-good.prev.old.55/"
n77=$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev.new.77")
( mv() { case "$*" in *known-good.prev*) return 1 ;; esac; command mv "$@"; }; pkg_apply >/dev/null 2>"$env_dir/err" ); rc=$?
check "failed restore: apply itself carries on (exit 0)" 0 "$rc"
check "failed restore: .prev.new.77 and .prev.old.55 both survive, no .prev" "$n77 yes no" \
    "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev.new.77") $([ -d "$PKG_RECOVERY_DIR/known-good.prev.old.55" ] && echo yes) $([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no)"
check "failed restore: a warning names the kept directories" "1 1" \
    "$(grep -c 'known-good.prev.new.77' "$env_dir/err") $(grep -c 'known-good.prev.old.55' "$env_dir/err")"
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "failed restore: the next apply retries and restores the superseded copy as .prev" "$n77 no" \
    "$(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev") $(ls "$PKG_RECOVERY_DIR" | grep -c 'known-good.prev.\(new\|old\)' | sed 's/^0$/no/')"


# --- verify / promote ---------------------------------------------------------------------------
# Every external command a check runs (uname, nvidia-smi, systemctl, journalctl, ip) is a stub on
# a PATH directory of the test env: nothing real is queried, and the stubs log their calls.
ORIG_PATH=$PATH
make_verify_stubs() {  # make_verify_stubs DIR
    mkdir -p "$1"
    cat > "$1/uname" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = -r ]; then printf '%s\n' "${STUB_UNAME_R-6.16.0-arch1-1}"; exit "${STUB_UNAME_EXIT:-0}"; fi
exec /usr/bin/uname "$@"
STUB
    cat > "$1/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG_DIR/nvidia-smi.log"
printf '%b' "${STUB_NVSMI_ERR-}" >&2
printf '%b' "${STUB_NVSMI_OUT-GPU 0: NVIDIA Stub (UUID: GPU-1)\n}"
exit "${STUB_NVSMI_EXIT:-0}"
STUB
    cat > "$1/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG_DIR/systemctl.log"
printf '%b' "${STUB_SYSTEMCTL_ERR-}" >&2
printf '%b' "${STUB_SYSTEMCTL_OUT-}"
exit "${STUB_SYSTEMCTL_EXIT:-0}"
STUB
    cat > "$1/journalctl" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG_DIR/journalctl.log"
printf '%b' "${STUB_JOURNAL_OUT-}"
exit "${STUB_JOURNAL_EXIT:-0}"
STUB
    cat > "$1/ip" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG_DIR/ip.log"
case "$*" in
    *-6*) printf '%b' "${STUB_IP6_ERR-}" >&2; printf '%b' "${STUB_IP6_OUT-}" ;;
    *)    printf '%b' "${STUB_IP4_ERR-}" >&2; printf '%b' "${STUB_IP4_OUT-default via 192.168.1.1 dev eth0 proto dhcp\n}" ;;
esac
exit "${STUB_IP_EXIT:-0}"
STUB
    cat > "$1/sync" <<'STUB'
#!/usr/bin/env bash
# logs its arguments and what exists in the recovery dir at the moment of the call, then really syncs
rec="${PKG_RECOVERY_DIR:-/nonexistent}"
cnt() { ls -d "$rec"/$1 2>/dev/null | wc -l; }
state="old=$(cnt 'known-good.old.*') kg=$([ -e "$rec/known-good/manifest.json" ] && echo 1 || echo 0) prevold=$(cnt 'known-good.prev.old.*')"
echo "$* $state" >> "$STUB_LOG_DIR/sync.log"
if [ -n "${STUB_SYNC_FAIL_WHEN_OLD-}" ] && [[ $state == *old=1* || $state == *prevold=1* ]]; then exit 1; fi
if [ -n "${STUB_SYNC_FAIL_NEWDIR-}" ] && [[ " $* " =~ known-good\.new\.[0-9]+/manifest\.json ]]; then exit 1; fi
if [ -n "${STUB_SYNC_FAIL_TREE-}" ] && [ "${1:-}" = -- ]; then exit 1; fi
exec /usr/bin/sync "$@"
STUB
    chmod +x "$1"/*
}
# new_verify_env: an apply env (installed = the BEFORE packages) with the stubs first on PATH, all
# of them answering "healthy" (running kernel 6.16.0-arch1-1) until a test sets STUB_*.
new_verify_env() {
    new_apply_env
    make_verify_stubs "$env_dir/bin"
    export PATH="$env_dir/bin:$ORIG_PATH" STUB_LOG_DIR="$env_dir"
    unset STUB_UNAME_R STUB_UNAME_EXIT STUB_NVSMI_OUT STUB_NVSMI_EXIT STUB_SYSTEMCTL_OUT STUB_SYSTEMCTL_EXIT \
        STUB_JOURNAL_OUT STUB_JOURNAL_EXIT STUB_IP4_OUT STUB_IP6_OUT STUB_IP_EXIT STUB_IP4_ERR STUB_IP6_ERR STUB_NVSMI_ERR STUB_SYSTEMCTL_ERR \
        STUB_SYNC_FAIL_WHEN_OLD STUB_SYNC_FAIL_NEWDIR STUB_SYNC_FAIL_TREE \
        PKG_VERIFY_KERNEL PKG_VERIFY_GPU PKG_VERIFY_SERVICES PKG_VERIFY_JOURNAL PKG_VERIFY_NETWORK PKG_RECOVERY_SRC
}
use_after_db() { cp "$FAKE_PACMAN_AFTER" "$FAKE_PACMAN_DB"; }   # linux 6.16.0.arch1-1, nvidia-open 580.1-1, grub 2:2.17-1
has() { local o=(); while [ "$1" != -- ]; do o+=("$1"); shift; done; shift; grep -q "${o[@]}" -- "$1" <<<"$2" && echo yes || echo no; }   # has [grep opts] -- PATTERN TEXT
vl() { vlines "$V_OUT" | tr ',' '\n' | sed -n "$1p"; }   # the Nth check line, "STATUS check"
vlines() { sed -E 's/^([A-Z]+) ([a-z]+).*/\1 \2/' <<<"$1" | paste -sd,; }   # "PASS kernel,PASS gpu,..."
run_verify() {  # leaves V_OUT, V_ERR, V_RC
    V_OUT=$("$PKG_UPDATE" verify 2>"$env_dir/verr" </dev/null); V_RC=$?; V_ERR=$(cat "$env_dir/verr")
}

# all healthy
new_verify_env; use_after_db
before_listing=$(find "$PKG_RECOVERY_DIR" | sort)
run_verify
check "verify healthy: exit 0" 0 "$V_RC"
check "verify healthy: five check lines in order" "PASS kernel,PASS gpu,PASS services,PASS journal,PASS network" "$(vlines "$V_OUT")"
check "verify healthy: nothing but check lines on stdout" 5 "$(grep -c . <<<"$V_OUT")"
check "verify changes nothing (no lock file, log or record)" "$before_listing" "$(find "$PKG_RECOVERY_DIR" | sort)"
check "verify: kernel line shows both versions" 1 "$(grep -c '^PASS kernel: .*6.16.0-arch1-1' <<<"$V_OUT")"

# kernel: running vs installed
new_verify_env; use_after_db; export STUB_UNAME_R=6.15.3-arch1-1
run_verify
check "verify kernel mismatch: FAIL kernel, the rest PASS" "FAIL kernel,PASS gpu,PASS services,PASS journal,PASS network" "$(vlines "$V_OUT")"
check "verify kernel mismatch: exit 1" 1 "$V_RC"
check "verify kernel mismatch: names running and installed version" 1 "$(grep -c '^FAIL kernel: .*6.15.3-arch1-1.*linux 6.16.0.arch1-1' <<<"$V_OUT")"
# normalisation, directly
check "kernel release: arch dot form" 6.15.3-arch1-1 "$(_verify_kernel_release linux 6.15.3.arch1-1)"
check "kernel release: epoch dropped" 6.15.3-arch1-1 "$(_verify_kernel_release linux 1:6.15.3.arch1-1)"
check "kernel release: x.y gets .0 like uname does" 6.16.0-arch1-1 "$(_verify_kernel_release linux 6.16.arch1-1)"
check "kernel release: lts suffix" 6.12.30-1-lts "$(_verify_kernel_release linux-lts 6.12.30-1)"
check "kernel release: zen suffix" 6.15.3-zen1-1-zen "$(_verify_kernel_release linux-zen 6.15.3.zen1-1)"
check "kernel release: hardened suffix" 6.15.3-hardened1-1-hardened "$(_verify_kernel_release linux-hardened 6.15.3.hardened1-1)"
check "kernel release: pkgrel kept" 6.15.3-arch1-2 "$(_verify_kernel_release linux 6.15.3.arch1-2)"
check "kernel release: no pkgrel is not interpreted" "" "$(_verify_kernel_release linux 6.15.3 2>/dev/null)"
# normalisation, end to end
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux 1:6.16.0.arch1-1/' "$FAKE_PACMAN_DB"
run_verify; check "verify kernel: epoch in the package version still matches" "PASS kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux 6.16.arch1-1/' "$FAKE_PACMAN_DB"
run_verify; check "verify kernel: 6.16.arch1 matches uname 6.16.0-arch1-1" "PASS kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux 6.16.0.arch1-2/' "$FAKE_PACMAN_DB"
run_verify; check "verify kernel: a different pkgrel is a mismatch" "FAIL kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux 6.16.0.arch2-1/' "$FAKE_PACMAN_DB"
run_verify; check "verify kernel: a different arch tag is a mismatch" "FAIL kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux 6.16.0.arch1-1.1/' "$FAKE_PACMAN_DB"
run_verify; check "verify kernel: a longer pkgrel is not a prefix match" "FAIL kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
new_verify_env; use_after_db; export STUB_UNAME_R=6.16.0-arch1-12
run_verify; check "verify kernel: a running release that merely starts like the installed one is a mismatch" "FAIL kernel" "$(vl 1)"
# linux-lts only
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux-lts 6.12.30-1/' "$FAKE_PACMAN_DB"; export STUB_UNAME_R=6.12.30-1-lts
run_verify; check "verify kernel: linux-lts running and installed: PASS" "PASS kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
export STUB_UNAME_R=6.12.29-1-lts
run_verify; check "verify kernel: linux-lts older than installed: FAIL" "FAIL kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
# both installed: the running one decides, the other may be ahead
new_verify_env; use_after_db; echo "linux-lts 6.12.31-1" >> "$FAKE_PACMAN_DB"; export STUB_UNAME_R=6.16.0-arch1-1
run_verify; check "verify kernel: linux running, a newer linux-lts installed: PASS" "PASS kernel" "$(vlines "$V_OUT" | cut -d, -f1)"
# no kernel package at all: SKIP, said so
new_verify_env; use_after_db; sed -i '/^linux 6.16.0.arch1-1$/d' "$FAKE_PACMAN_DB"
run_verify
check "verify kernel: no kernel package: SKIP, exit 0" "SKIP kernel 0" "$(vlines "$V_OUT" | cut -d, -f1) $V_RC"
check "verify kernel: SKIP says why" 1 "$(grep -c '^SKIP kernel: no kernel package' <<<"$V_OUT")"
# pacman broken: fail closed
new_verify_env; use_after_db; export FAKE_PACMAN_EXIT=1
run_verify; check "verify: pacman -Q failing is a FAIL of kernel and gpu, exit 1" "FAIL kernel,FAIL gpu 1" "$(vlines "$V_OUT" | cut -d, -f1,2) $V_RC"
unset FAKE_PACMAN_EXIT

# gpu
new_verify_env; use_after_db; rm -f "$env_dir/nvidia-smi.log"
run_verify
check "verify gpu: nvidia installed: nvidia-smi -L runs" "-L" "$(cat "$env_dir/nvidia-smi.log" 2>/dev/null)"
check "verify gpu: PASS shows the GPU line" 1 "$(grep -c '^PASS gpu: GPU 0: NVIDIA Stub' <<<"$V_OUT")"
export STUB_NVSMI_EXIT=9
run_verify; check "verify gpu: nvidia-smi failing: FAIL, exit 1" "FAIL gpu 1" "$(vl 2) $V_RC"
unset STUB_NVSMI_EXIT; export STUB_NVSMI_OUT=""
run_verify; check "verify gpu: nvidia-smi listing no GPU: FAIL" "FAIL gpu" "$(vl 2)"
unset STUB_NVSMI_OUT
sed -i '/^nvidia-open /d' "$FAKE_PACMAN_DB"; rm -f "$env_dir/nvidia-smi.log"
run_verify
check "verify gpu: no nvidia package: SKIP, nvidia-smi never called" "SKIP gpu no" "$(vl 2) $([ -e "$env_dir/nvidia-smi.log" ] && echo yes || echo no)"
check "verify gpu: no nvidia package: exit 0" 0 "$V_RC"
echo "nvidia-utils 580.1-1" >> "$FAKE_PACMAN_DB"; export STUB_NVSMI_EXIT=9
run_verify; check "verify gpu: any package named nvidia* counts (nvidia-utils)" "FAIL gpu" "$(vl 2)"
unset STUB_NVSMI_EXIT
sed -i '/^nvidia-utils /d' "$FAKE_PACMAN_DB"; echo "lib32-nvidia-utils 580.1-1" >> "$FAKE_PACMAN_DB"; rm -f "$env_dir/nvidia-smi.log"
run_verify; check "verify gpu: only names that START with nvidia count (lib32-nvidia-utils does not)" "SKIP gpu no" "$(vl 2) $([ -e "$env_dir/nvidia-smi.log" ] && echo yes || echo no)"

# services
new_verify_env; use_after_db
export STUB_SYSTEMCTL_OUT='● foo.service loaded failed failed Foo daemon\n● bar.timer loaded failed failed Bar\n'
run_verify
check "verify services: failed units: FAIL, exit 1" "FAIL services 1" "$(vl 3) $V_RC"
check "verify services: the units are named" 1 "$(grep '^FAIL services: ' <<<"$V_OUT" | grep -c 'foo.service.*bar.timer')"
check "verify services: asked --failed --no-legend" 1 "$(grep -c -- '--failed.*--no-legend\|--no-legend.*--failed' "$env_dir/systemctl.log")"
export STUB_SYSTEMCTL_OUT="" STUB_SYSTEMCTL_EXIT=1
run_verify; check "verify services: systemctl itself failing is a FAIL (fail closed)" "FAIL services" "$(vl 3)"
unset STUB_SYSTEMCTL_OUT STUB_SYSTEMCTL_EXIT

# journal: a warning, never a failure
new_verify_env; use_after_db
export STUB_JOURNAL_OUT='Oct 17 10:00:00 host kernel: bad thing\nOct 17 10:00:01 host app: err one\nOct 17 10:00:02 host app: err two\n'
run_verify
check "verify journal: errors only WARN, exit 0" "WARN journal 0" "$(vl 4) $V_RC"
check "verify journal: the count is reported" 1 "$(grep -c '^WARN journal: 3 ' <<<"$V_OUT")"
check "verify journal: asked for priority err of this boot" 1 "$(grep -c -- '-b.*-p err\|-p err.*-b' "$env_dir/journalctl.log")"
export STUB_JOURNAL_OUT="" STUB_JOURNAL_EXIT=1
run_verify; check "verify journal: journalctl failing is a WARN, never a FAIL" "WARN journal 0" "$(vl 4) $V_RC"
unset STUB_JOURNAL_OUT STUB_JOURNAL_EXIT
run_verify; check "verify journal: none: PASS" "PASS journal" "$(vl 4)"

# network
new_verify_env; use_after_db
export STUB_IP4_OUT="" STUB_IP6_OUT=""
run_verify; check "verify network: no default route: FAIL, exit 1" "FAIL network 1" "$(vl 5) $V_RC"
export STUB_IP6_OUT="default via fe80::1 dev eth0 proto ra metric 1024\n"
run_verify; check "verify network: an IPv6 default route is enough" "PASS network" "$(vl 5)"
export STUB_IP4_OUT="" STUB_IP6_OUT="" STUB_IP_EXIT=1
run_verify; check "verify network: ip failing is a FAIL (fail closed)" "FAIL network" "$(vl 5)"
unset STUB_IP4_OUT STUB_IP6_OUT STUB_IP_EXIT

# PKG_VERIFY_<NAME> replaces a whole check: exit 0 = PASS, anything else = FAIL
new_verify_env; use_after_db; export STUB_UNAME_R=6.15.3-arch1-1 STUB_SYSTEMCTL_OUT='● foo.service loaded failed failed Foo\n'
export PKG_VERIFY_KERNEL=true PKG_VERIFY_SERVICES=true
run_verify; check "PKG_VERIFY_KERNEL=true / _SERVICES=true: PASS despite real mismatch / failed unit" "PASS kernel,PASS gpu,PASS services,PASS journal,PASS network 0" "$(vlines "$V_OUT") $V_RC"
export PKG_VERIFY_GPU=false PKG_VERIFY_NETWORK="test 1 = 2" PKG_VERIFY_JOURNAL=false
run_verify; check "PKG_VERIFY_*: a non-zero exit is FAIL (also for journal), exit 1" "PASS kernel,FAIL gpu,PASS services,FAIL journal,FAIL network 1" "$(vlines "$V_OUT") $V_RC"
export PKG_VERIFY_GPU="$env_dir/no-such-command"
run_verify; check "PKG_VERIFY_*: a command that cannot run is a FAIL" "FAIL gpu" "$(vl 2)"
printf '#!/usr/bin/env bash\necho "the driver said no"\necho second line\nexit 1\n' > "$env_dir/say-no"; chmod +x "$env_dir/say-no"
export PKG_VERIFY_GPU="$env_dir/say-no"
run_verify; check "PKG_VERIFY_*: the command's first output line is the detail" 1 "$(grep -c '^FAIL gpu: the driver said no' <<<"$V_OUT")"
export PKG_VERIFY_GPU="  "
run_verify; check "PKG_VERIFY_*: blank is not an override (the real gpu check runs)" "PASS gpu" "$(vl 2)"
unset PKG_VERIFY_KERNEL PKG_VERIFY_GPU PKG_VERIFY_SERVICES PKG_VERIFY_JOURNAL PKG_VERIFY_NETWORK

# dispatcher: verify needs no root, no lock, no log; extra arguments are a usage error
new_verify_env; use_after_db; make_pkexec_stub "$env_dir"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
  "$PKG_UPDATE" verify >/dev/null 2>&1 </dev/null; echo "ok-$?" > "$env_dir/rc"
  "$PKG_UPDATE" verify now >/dev/null 2>&1 </dev/null; echo "usage-$?" >> "$env_dir/rc" )
check "verify: no pkexec, usage error 2 for arguments" "ok-0 usage-2 no" "$(paste -sd' ' "$env_dir/rc") $([ -e "$env_dir/argv" ] && echo yes || echo no)"
( acquire_lock; "$PKG_UPDATE" verify >/dev/null 2>&1 </dev/null ); check "verify runs while the update lock is held" 0 "$?"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" verify 2>&1 </dev/null | grep -c '^LOG=' ) > "$env_dir/o"
check "verify prints no LOG= line" 0 "$(cat "$env_dir/o")"

# --- promote ---------------------------------------------------------------------------------------
# new_promote_env: the verify env, with a REAL old known-good (grub 2:2.16, created 2020), the update
# applied (installed = the after packages, their archives in the cache), pending awaiting-verification,
# a known-good.prev, a recovery.sh source (mode 644) and a healthy system running kernel 6.16.0-arch1-1.
new_promote_env() {
    new_verify_env
    rm -rf "$PKG_RECOVERY_DIR/known-good"; real_known_good
    jq '.created = "2020-01-01T00:00:00Z"' "$PKG_RECOVERY_DIR/known-good/manifest.json" | write_atomic "$PKG_RECOVERY_DIR/known-good/manifest.json"
    use_after_db
    local n v
    while read -r n v; do printf 'new archive %s %s\n' "$n" "$v" > "$PKG_CACHE_DIR/$n-$v-x86_64.pkg.tar.zst"; done < <(protected_installed)
    mkdir "$PKG_RECOVERY_DIR/pending"
    echo '{"started":"2026-10-17T10:00:00Z","finished":"2026-10-17T10:05:00Z","mode":"normal","pacman_exit":0,"state":"awaiting-verification","packages":[]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
    mkdir "$PKG_RECOVERY_DIR/known-good.prev"; echo older > "$PKG_RECOVERY_DIR/known-good.prev/marker"
    printf '#!/bin/sh\necho stub recovery\n' > "$env_dir/recovery-src.sh"; chmod 644 "$env_dir/recovery-src.sh"
    export PKG_RECOVERY_SRC="$env_dir/recovery-src.sh"
    rm -f "$FAKE_PACMAN_LOG" "$env_dir/qs.log"
    fp0=$(kg_fingerprint); pend0=$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json")
}
set_pending() {  # set_pending JSON
    printf '%s\n' "$1" > "$PKG_RECOVERY_DIR/pending/manifest.json"; pend0=$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json")
}
run_promote() {  # run_promote [args]: leaves P_OUT, P_ERR, P_RC
    "$PKG_UPDATE" promote "$@" </dev/null >"$env_dir/pout" 2>"$env_dir/perr"; P_RC=$?
    P_OUT=$(cat "$env_dir/pout"); P_ERR=$(cat "$env_dir/perr")
}
kg_version() { jq -r --arg n "$1" '.packages[] | select(.name == $n) | .version' "$PKG_RECOVERY_DIR/known-good/manifest.json"; }
assert_untouched() {  # assert_untouched LABEL: nothing a refused/failed promote may touch was touched
    check "$1: known-good untouched (inode, mtime, content)" "$fp0" "$(kg_fingerprint)"
    check "$1: pending kept" "$pend0" "$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json" 2>/dev/null)"
    check "$1: known-good.prev kept" yes "$([ -f "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes || echo no)"
    check "$1: recovery.sh not installed" no "$([ -e "$PKG_RECOVERY_DIR/recovery.sh" ] && echo yes || echo no)"
    check "$1: no leftovers" "" "$(leftovers)"
    check "$1: no statusbar refresh" no "$([ -e "$env_dir/qs.log" ] && echo yes || echo no)"
}

# kernel mismatch (installed but not rebooted): refused
new_promote_env; export STUB_UNAME_R=6.15.3-arch1-1
run_promote
check "promote kernel mismatch: exit 1" 1 "$P_RC"
check "promote kernel mismatch: the verify list is shown, FAIL kernel in it" 1 "$(grep -c '^FAIL kernel' <<<"$P_OUT")"
check "promote kernel mismatch: says it refuses and why" 1 "$(grep -c -i 'refus' <<<"$P_ERR")"
assert_untouched "promote kernel mismatch"

# healthy: known-good is replaced
new_promote_env
run_promote
check "promote: exit 0" 0 "$P_RC"
check "promote: LOG= is the first line" 1 "$(head -n 1 <<<"$P_OUT" | grep -c '^LOG=')"
check "promote: the verify list is shown" 1 "$(grep -c '^PASS kernel' <<<"$P_OUT")"
check "promote: known-good has the installed versions" "6.16.0.arch1-1 2:2.17-1 580.1-1" "$(kg_version linux) $(kg_version grub) $(kg_version nvidia-open)"
check "promote: known-good is newer than the old one" 1 "$(jq -r '.created > "2020-01-01T00:00:00Z"' "$PKG_RECOVERY_DIR/known-good/manifest.json" | grep -c true)"
check "promote: known-good records the running kernel" 6.16.0-arch1-1 "$(jq -r .kernel "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "promote: known-good archives are the new ones, hardlinked to the cache" "4 4" \
    "$(ls "$PKG_RECOVERY_DIR/known-good/archives" | wc -l) $(find "$PKG_RECOVERY_DIR/known-good/archives" -type f -links +1 | wc -l)"
check "promote: the old grub archive is not in the new known-good" 0 "$(ls "$PKG_RECOVERY_DIR/known-good/archives" | grep -c '2:2.16-1')"
check "promote: known-good describes the installed set" 0 "$(known_good_matches; echo $?)"
check "promote: pending removed" no "$([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
check "promote: known-good.prev removed" no "$([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no)"
check "promote: recovery.sh installed, mode 755, from the source" "755 stub recovery" \
    "$(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh") $(sh "$PKG_RECOVERY_DIR/recovery.sh")"
check "promote: no leftovers" "" "$(leftovers)"
check "promote: the final message" 1 "$(grep -c '^known-good updated: 20[0-9-]*T[0-9:]*Z, kernel 6.16.0-arch1-1$' <<<"$P_OUT")"
check "promote: statusbar refreshed" "ipc call updates refresh" "$(cat "$env_dir/qs.log" 2>/dev/null)"
check "promote: pacman was only queried (no -Sy/-S/-U/-R)" 0 "$(cat "$FAKE_PACMAN_LOG" 2>/dev/null | grep -c -E -- '-S|-U|-R')"
check "promote: status says matches, no pending" "true null" "$("$PKG_UPDATE" status | jq -r '"\(.matches) \(.pending)"')"
check "promote: the log has the output" 1 "$(grep -c '^known-good updated:' "$(head -n 1 <<<"$P_OUT" | sed 's/^LOG=//')")"
# the next apply can start (no pending gate), and an unrelated second promote is a harmless re-checkpoint
run_promote; check "promote twice (no pending the second time): works" 0 "$P_RC"
check "promote twice: says there was no pending record" 1 "$(grep -c -i 'no pending' <<<"$P_OUT$P_ERR")"

# --force over a failed check
new_promote_env; export PKG_VERIFY_NETWORK=false
run_promote
check "promote with a FAIL check: refused, exit 1" 1 "$P_RC"
check "promote refusal names the failed check" yes "$(has -- 'FAIL network' "$P_ERR")"
check "promote refusal tells about --force" 1 "$(grep -c -- '--force' <<<"$P_ERR")"
assert_untouched "promote FAIL check"
run_promote --force
check "promote --force despite a FAIL: exit 0" 0 "$P_RC"
check "promote --force: says loudly what it overrides" 1 "$(grep -c -- '--force.*network' <<<"$P_ERR")"
check "promote --force: known-good replaced, pending gone" "6.16.0.arch1-1 no" "$(kg_version linux) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
# --force over a kernel mismatch: still loud about the kernel
new_promote_env; export STUB_UNAME_R=6.15.3-arch1-1
run_promote --force
check "promote --force over a kernel mismatch: exit 0" 0 "$P_RC"
check "promote --force over a kernel mismatch: --force line names the kernel check" yes "$(has -- '--force.*kernel' "$P_ERR")"
check "promote --force over a kernel mismatch: names the running kernel" yes "$(has -- '6.15.3-arch1-1' "$P_ERR")"
check "promote --force over a kernel mismatch: explains that the new kernel is not the one running" yes "$(has -i -- 'not.*running\|running.*not\|reboot' "$P_ERR")"
check "promote --force over a kernel mismatch: known-good has the unbooted kernel package" 6.16.0.arch1-1 "$(kg_version linux)"
# a check command that exits non-zero is a FAIL, a journal warning is not
new_promote_env; export PKG_VERIFY_SERVICES=false
run_promote; check "promote: PKG_VERIFY_SERVICES=false (non-zero exit) refuses" 1 "$P_RC"; assert_untouched "promote services fail"
new_promote_env; export STUB_JOURNAL_OUT='err one\nerr two\n'
run_promote
check "promote: journal errors only WARN, promote goes through" "0 1" "$P_RC $(grep -c '^WARN journal' <<<"$P_OUT")"
new_promote_env; export STUB_SYSTEMCTL_OUT='● foo.service loaded failed failed Foo\n'
run_promote; check "promote: a failed service refuses" 1 "$P_RC"; assert_untouched "promote failed unit"

# pending state rules
for st in failed running; do
    new_promote_env; set_pending "{\"started\":\"2026-10-17T10:00:00Z\",\"mode\":\"normal\",\"state\":\"$st\",\"packages\":[]}"
    run_promote
    check "promote pending $st: refused, exit 1" 1 "$P_RC"
    check "promote pending $st: says why (state named)" 1 "$(grep -c "$st" <<<"$P_ERR")"
    check "promote pending $st: points to discard" 1 "$(grep -c 'discard' <<<"$P_ERR")"
    assert_untouched "promote pending $st"
    run_promote --force
    check "promote pending $st with --force: exit 0" 0 "$P_RC"
    check "promote pending $st with --force: warns" 1 "$(grep -c -- "--force.*$st" <<<"$P_ERR")"
    check "promote pending $st with --force: promoted, pending gone" "6.16.0.arch1-1 no" "$(kg_version linux) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no)"
done
new_promote_env; echo 'not json' > "$PKG_RECOVERY_DIR/pending/manifest.json"; pend0=$(sha256sum < "$PKG_RECOVERY_DIR/pending/manifest.json")
run_promote; check "promote pending unreadable: refused" 1 "$P_RC"; assert_untouched "promote pending unreadable"
run_promote --force; check "promote pending unreadable with --force: promoted" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"
new_promote_env; rm -f "$PKG_RECOVERY_DIR/pending/manifest.json"; pend0=none
run_promote; check "promote pending dir without a record: refused" 1 "$P_RC"
check "promote pending dir without a record: known-good untouched" "$fp0" "$(kg_fingerprint)"
# replaced: apply --force over an older record
for st in failed running; do
    new_promote_env; set_pending "{\"started\":\"2026-10-17T11:00:00Z\",\"mode\":\"normal\",\"state\":\"awaiting-verification\",\"packages\":[],\"replaced\":{\"started\":\"2026-10-17T10:00:00Z\",\"mode\":\"normal\",\"state\":\"$st\",\"packages\":[]}}"
    run_promote
    check "promote replaced.state $st: refused, exit 1" 1 "$P_RC"
    check "promote replaced.state $st: says the older update was $st" 1 "$(grep -c "replaced.*$st\|$st.*replaced\|older.*$st" <<<"$P_ERR")"
    assert_untouched "promote replaced $st"
    run_promote --force; check "promote replaced.state $st with --force: promoted" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"
done
new_promote_env; set_pending '{"started":"2026-10-17T11:00:00Z","mode":"normal","state":"awaiting-verification","packages":[],"replaced":{"started":"2026-10-17T10:00:00Z","state":"awaiting-verification","packages":[]}}'
run_promote; check "promote replaced.state awaiting-verification: fine" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"
new_promote_env; set_pending '{"started":"2026-10-17T11:00:00Z","mode":"normal","state":"awaiting-verification","packages":[],"replaced":{"started":"2026-10-17T10:00:00Z","packages":[]}}'
run_promote; check "promote replaced without a state: refused (only awaiting-verification is clean)" 1 "$P_RC"
# no pending record: promote the current verified state
new_promote_env; rm -rf "$PKG_RECOVERY_DIR/pending"
run_promote
check "promote without a pending record: works" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"
check "promote without a pending record: says so" 1 "$(grep -c -i 'no pending' <<<"$P_OUT$P_ERR")"
# no known-good at all (first run): nothing to swap aside
new_promote_env; rm -rf "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/pending"
run_promote; check "promote without any known-good: builds one" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"; check "promote without any known-good: no leftovers" "" "$(leftovers)"

# missing archive for a running version: the old known-good stays
new_promote_env; rm -f "$PKG_CACHE_DIR/grub-2:2.17-1-x86_64.pkg.tar.zst"
run_promote
check "promote archive missing: exit 1" 1 "$P_RC"
check "promote archive missing: names the package" 1 "$(grep -c 'grub 2:2.17-1' <<<"$P_ERR")"
assert_untouched "promote archive missing"
run_promote --force; check "promote archive missing even with --force: exit 1" 1 "$P_RC"; assert_untouched "promote archive missing --force"
# pacman -Q breaking after verify passed (via overrides): nothing changes
new_promote_env; export PKG_VERIFY_KERNEL=true PKG_VERIFY_GPU=true FAKE_PACMAN_EXIT=1
run_promote --force; check "promote pacman -Q failing during the build: exit 1" 1 "$P_RC"; unset FAKE_PACMAN_EXIT; assert_untouched "promote pacman failing"

# lock and usage
new_promote_env
( acquire_lock; "$PKG_UPDATE" promote >"$env_dir/pout" 2>"$env_dir/perr" </dev/null ); rc=$?
check "promote while the lock is held: exit 3" 3 "$rc"
check "promote while the lock is held: says another operation runs" 1 "$(grep -c -i 'another update' "$env_dir/perr")"
assert_untouched "promote locked"
touch "$env_dir/dblck"; PKG_PACMAN_DBLOCK="$env_dir/dblck" "$PKG_UPDATE" promote >/dev/null 2>&1 </dev/null; check "promote while pacman runs (db.lck): exit 3" 3 "$?"
assert_untouched "promote db.lck"
make_pkexec_stub "$env_dir"
printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" > "%s/argv"\n' "$env_dir" > "$env_dir/pkexec"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
  "$PKG_UPDATE" promote --bogus >/dev/null 2>&1; echo "bogus-$?" > "$env_dir/rc"
  "$PKG_UPDATE" promote now >/dev/null 2>&1; echo "word-$?" >> "$env_dir/rc" )
check "promote: unknown flag/word is exit 2 and never reaches pkexec" "bogus-2 word-2 no" "$(paste -sd' ' "$env_dir/rc") $([ -e "$env_dir/argv" ] && echo yes || echo no)"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" promote --force --yes >/dev/null 2>&1 </dev/null )
read_argv "$env_dir/argv"
check "promote re-executes through pkexec as 'promote --force --yes'" "$(readlink -f "$PKG_UPDATE") promote --force --yes" "${ARGV[*]: -4}"
assert_untouched "promote usage"
run_promote --yes; check "promote --yes is accepted" 0 "$P_RC"

# promote is the library function path: it never calls the dispatcher (a held lock would deadlock/exit 3)
new_promote_env
out=$( acquire_lock; pkg_promote >/dev/null 2>&1; echo "rc=$?" )
check "pkg_promote (library) does not take the lock itself" "rc=0" "$out"

# --- promote: interruption safety
# (perl: the shell must see INT with the default disposition even if this test run was started in the background)
RUN_LIB() { perl -e '$SIG{INT} = "DEFAULT"; $SIG{HUP} = "DEFAULT"; exec @ARGV' bash -c "$RUNLIBS; $1" >"$env_dir/lout" 2>"$env_dir/lerr" </dev/null; echo $?; }
SWAP1='-T\ --\ */known-good\ */known-good.old.*'    # mv case patterns: known-good -> known-good.old.PID
SWAP2='-T\ --\ */known-good.new.*\ */known-good'      #                   known-good.new.PID -> known-good
# TERM / HUP while the new known-good is being built: nothing changes, no half-built directory
for sig in TERM HUP; do
    new_promote_env
    rc=$(RUN_LIB 'sha256sum() { kill -'$sig' $$; command sha256sum "$@"; }; pkg_promote')
    check "promote $sig during the build: killed by $sig" "$(sigcode $sig)" "$rc"
    assert_untouched "promote $sig during the build"
done
new_promote_env
rc=$(RUN_LIB 'sha256sum() { kill -INT $$; command sha256sum "$@"; }; pkg_promote')
check "promote INT during the build: killed by INT" 130 "$rc"; assert_untouched "promote INT during the build"
# a caller's trap is run and the signal still ends promote
new_promote_env
rc=$(RUN_LIB 'trap "echo caller-term" TERM; sha256sum() { kill -TERM $$; command sha256sum "$@"; }; pkg_promote')
check "promote TERM during the build: the caller's trap ran" 1 "$(grep -c caller-term "$env_dir/lout")"
assert_untouched "promote TERM with a caller trap"
# TERM / HUP between the two renames: postponed, the swap completes, then the signal ends promote
for sig in TERM HUP INT; do
    new_promote_env
    rc=$(RUN_LIB 'mv() { case "$*" in '"$SWAP2"') kill -'$sig' $$ ;; esac; command mv "$@"; }; pkg_promote')
    check "promote $sig between the renames: ends by $sig after finishing" "$(sigcode $sig)" "$rc"
    check "promote $sig between the renames: known-good is the complete new one" "6.16.0.arch1-1 2:2.17-1" "$(kg_version linux) $(kg_version grub)"
    check "promote $sig between the renames: nothing left over, pending and prev cleared" " no no" "$(leftovers) $([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no)"
    check "promote $sig between the renames: recovery.sh installed" 755 "$(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh" 2>/dev/null)"
done
# a signal while recovery.sh is being installed (after the swap): postponed, the rest finishes, then it ends promote
new_promote_env
rc=$(RUN_LIB 'cp() { kill -TERM $$; command cp "$@"; }; pkg_promote')
check "promote TERM during the clean-up: ends by TERM" 143 "$rc"
check "promote TERM during the clean-up: recovery.sh installed, final message printed, nothing left" "755 1 " "$(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh" 2>/dev/null) $(grep -c '^known-good updated:' "$env_dir/lout") $(leftovers)"
# the rename processes themselves ignore INT/TERM/HUP (a Ctrl-C to the process group cannot cut a rename short)
new_promote_env
cat > "$env_dir/bin/mv" <<STUB
#!/usr/bin/env bash
[ "\${1:-}" != -T ] || echo "\$(awk '/^SigIgn/ { print \$2 }' /proc/\$\$/status) \$*" >> "$env_dir/mv-sigign.log"
exec /usr/bin/mv "\$@"
STUB
chmod +x "$env_dir/bin/mv"
run_promote
swaps=$(grep -E 'known-good\.old\.[0-9]+$|known-good\.new\.[0-9]+ ' "$env_dir/mv-sigign.log")
masks=$(while read -r m _; do [ $(( 0x$m & 0x4003 )) = $(( 0x4003 )) ] && echo ignored || echo "NOT-ignored:$m"; done <<<"$swaps" | sort | uniq -c | sed 's/^ *//' | paste -sd' ')
check "promote: the two swap renames' mv processes run with INT, TERM and HUP ignored" "0 2 ignored" "$P_RC $masks"
rm -f "$env_dir/bin/mv"
# the installed set changing while the new known-good is built: refused
new_promote_env
rc=$( ( sha256sum() { sed -i 's/^grub .*/grub 2:2.18-1/' "$FAKE_PACMAN_DB"; command sha256sum "$@"; }; pkg_promote >/dev/null 2>"$env_dir/lerr"; echo $? ) )
check "promote: installed packages changed during the build: exit 1" 1 "$rc"
check "promote: ... says so" yes "$(has -i -- 'changed while' "$(cat "$env_dir/lerr")")"
assert_untouched "promote installed set changed"
# an incomplete new known-good is never swapped in
new_promote_env
rc=$( ( eval "$(declare -f checkpoint_build | sed '1s/checkpoint_build/real_checkpoint_build/')"
        checkpoint_build() { real_checkpoint_build "$@" && rm -f "$1"/archives/grub-*; }   # a complete manifest, an archive missing
        pkg_promote >/dev/null 2>"$env_dir/lerr"; echo $? ) )
check "promote: an incomplete build is refused: exit 1" 1 "$rc"
assert_untouched "promote incomplete build"
# known-good missing and an earlier copy that cannot be restored: do not go on
new_promote_env; mv "$PKG_RECOVERY_DIR/known-good" "$PKG_RECOVERY_DIR/known-good.old.5"
rc=$( ( _apply_sweep() { :; }; pkg_promote >/dev/null 2>"$env_dir/lerr"; echo $? ) )
check "promote: no known-good + a restorable known-good.old.* the sweep left: exit 1, nothing touched" "1 yes" "$rc $([ -s "$PKG_RECOVERY_DIR/known-good.old.5/manifest.json" ] && echo yes)"
check "promote: ... nothing else created" "" "$(find "$PKG_RECOVERY_DIR" -mindepth 1 -maxdepth 1 \( -name 'known-good' -o -name 'known-good.new.*' -o -name recovery.sh \) | paste -sd' ')"
# the caller's traps are given back after a normal run, and SIGPIPE is ignored while promote runs
new_promote_env
out=$(trap 'echo A' INT; trap 'echo B' TERM; trap 'echo C' HUP; trap 'echo D' PIPE
      pkg_promote >/dev/null 2>&1; printf 'rc=%s ' $?; { trap -p INT; trap -p TERM; trap -p HUP; trap -p PIPE; } | tr '\n' ' ')
check "promote: the caller's INT/TERM/HUP/PIPE traps are back" "rc=0 trap -- 'echo A' SIGINT trap -- 'echo B' SIGTERM trap -- 'echo C' SIGHUP trap -- 'echo D' SIGPIPE " "$out"
new_promote_env; export PKG_VERIFY_NETWORK=false
out=$(trap 'echo B' TERM; pkg_promote >/dev/null 2>&1; echo "rc=$?"; trap -p TERM)
check "promote refused: the caller's trap is back too" "rc=1
trap -- 'echo B' SIGTERM" "$out"
new_promote_env
# the reader of promote's output is gone before the first line: without SIGPIPE ignored promote would die
bash -c "$RUNLIBS; sleep 0.4; pkg_promote; echo \"rc=\$?\" > '$env_dir/pipe-rc'" 2>/dev/null </dev/null | { exec 0<&-; true; }
check "promote with a dead output pipe: finishes, SIGPIPE ignored" "rc=0 6.16.0.arch1-1" "$(cat "$env_dir/pipe-rc" 2>/dev/null) $(kg_version linux)"

# a rename that fails: the old known-good is back
new_promote_env
rc=$( ( mv() { case "$*" in $SWAP2) return 1 ;; esac; command mv "$@"; }; pkg_promote >/dev/null 2>"$env_dir/lerr"; echo $? ) )
check "promote: the second rename failing: exit 1" 1 "$rc"
assert_untouched "promote second rename failing"
check "promote: the second rename failing: says the old one was restored" 1 "$(grep -c -i 'restor\|unchanged\|kept' "$env_dir/lerr")"
new_promote_env
rc=$( ( mv() { case "$*" in $SWAP1) return 1 ;; esac; command mv "$@"; }; pkg_promote >/dev/null 2>&1; echo $? ) )
check "promote: the first rename failing: exit 1" 1 "$rc"
assert_untouched "promote first rename failing"

# SIGKILL between the two renames (power loss): the next apply's sweep puts the old known-good back
new_promote_env
rc=$(RUN_LIB 'mv() { case "$*" in '"$SWAP2"') kill -KILL $$; sleep 0.3; return 1 ;; esac; command mv "$@"; }; pkg_promote')
check "crash: killed by SIGKILL" 137 "$rc"
check "crash leftover: known-good missing, known-good.old.* and known-good.new.* present, pending kept" "no 1 1 yes" \
    "$([ -e "$PKG_RECOVERY_DIR/known-good" ] && echo yes || echo no) $(ls -d "$PKG_RECOVERY_DIR"/known-good.old.* 2>/dev/null | wc -l) $(ls -d "$PKG_RECOVERY_DIR"/known-good.new.* 2>/dev/null | wc -l) $([ -f "$PKG_RECOVERY_DIR/pending/manifest.json" ] && echo yes || echo no)"
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "crash recovery: the next apply stops at the pending gate (4) after the sweep" 4 "$rc"
check "crash recovery: the sweep restored the old known-good, identical" "$fp0" "$(kg_fingerprint)"
check "crash recovery: the sweep said so" 1 "$(grep -c 'recovered known-good' "$env_dir/err")"
check "crash recovery: pending and prev intact, no debris" "yes yes " "$([ -f "$PKG_RECOVERY_DIR/pending/manifest.json" ] && echo yes) $([ -f "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes) $(leftovers)"
run_promote; check "after the crash and sweep: promote runs again and succeeds" "0 6.16.0.arch1-1" "$P_RC $(kg_version linux)"
# promote runs the sweep itself: right after the crash, no apply in between
new_promote_env
rc=$(RUN_LIB 'mv() { case "$*" in '"$SWAP2"') kill -KILL $$; sleep 0.3; return 1 ;; esac; command mv "$@"; }; pkg_promote')
run_promote
check "crash, then promote directly: its own sweep restores the old one first, promote succeeds" "0 6.16.0.arch1-1 yes" "$P_RC $(kg_version linux) $(has -- 'recovered known-good' "$P_ERR")"
check "crash, then promote directly: no leftovers" "" "$(leftovers)"
# a SIGKILL during the build leaves a known-good.new.* debris: swept, the old known-good untouched
new_promote_env
mkdir -p "$PKG_RECOVERY_DIR/known-good.new.999/archives" "$PKG_RECOVERY_DIR/known-good.new.998.tmp.998/archives" "$PKG_RECOVERY_DIR/known-good.prev.discard.997" "$PKG_RECOVERY_DIR/pending.discard.996"
: > "$PKG_RECOVERY_DIR/recovery.sh.tmp.995"
bash -c "$RUNLIBS; _apply_sweep" >/dev/null 2>&1
check "sweep: promote's debris (known-good.new.*, .discard.*, recovery.sh.tmp.*) is removed" "" "$(find "$PKG_RECOVERY_DIR" -mindepth 1 -maxdepth 1 \( -name 'known-good.new.*' -o -name '*.discard.*' -o -name 'recovery.sh.tmp.*' \) | paste -sd' ')"
check "sweep: ... and known-good, pending and prev are untouched" "$fp0 yes yes" "$(kg_fingerprint) $([ -f "$PKG_RECOVERY_DIR/pending/manifest.json" ] && echo yes) $([ -f "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes)"
# the sweep never resurrects a .prev that promote cleared (no .prev.old/.prev.new left by promote)
new_promote_env; run_promote
check "promote leaves nothing the sweep could resurrect as known-good.prev" "" "$(find "$PKG_RECOVERY_DIR" -mindepth 1 -maxdepth 1 -name 'known-good.prev*' | paste -sd' ')"

# recovery.sh: absent source, failing install, replacing an old copy
new_promote_env; export PKG_RECOVERY_SRC="$env_dir/not-there.sh"
run_promote
check "promote: recovery.sh source absent: warns, still promoted, exit 0" "0 6.16.0.arch1-1 yes" "$P_RC $(kg_version linux) $(has -i -- 'recovery.sh' "$P_ERR")"
check "promote: recovery.sh source absent: nothing installed" no "$([ -e "$PKG_RECOVERY_DIR/recovery.sh" ] && echo yes || echo no)"
new_promote_env; mkdir "$PKG_RECOVERY_DIR/recovery.sh"   # cannot be replaced by a file
run_promote
check "promote: recovery.sh install failing: known-good is promoted anyway, exit 0, loud warning" "0 6.16.0.arch1-1 yes" "$P_RC $(kg_version linux) $(has -i -- 'recovery.sh' "$P_ERR")"
check "promote: recovery.sh install failing: no temp file left" "" "$(leftovers)"
new_promote_env; printf 'old recovery\n' > "$PKG_RECOVERY_DIR/recovery.sh"; chmod 600 "$PKG_RECOVERY_DIR/recovery.sh"
run_promote
check "promote: an existing recovery.sh is replaced, mode 755" "755 stub recovery" "$(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh") $(sh "$PKG_RECOVERY_DIR/recovery.sh")"

# promote does not print the verify list twice and does not need a terminal
new_promote_env
check "promote: verify list printed once" 1 "$("$PKG_UPDATE" promote </dev/null 2>/dev/null | grep -c '^PASS kernel')"


# --- fix round 1 ------------------------------------------------------------------------------------
# sync_log_has PATTERN: a line of the sync stub's log matches (ERE)
sync_lines() { cat "$env_dir/sync.log" 2>/dev/null; }

# durability barrier in promote: the new tree is synced BEFORE the old known-good moves, the filesystem is
# committed AFTER the renames and BEFORE the old copy is deleted (the stub logs what exists at each call)
new_promote_env; rm -f "$env_dir/sync.log"
run_promote
check "promote: exit 0 with the sync stub in the way" 0 "$P_RC"
check "promote barrier: the new manifest is synced while the old known-good is still in place and not yet moved" 1 \
    "$(sync_lines | grep -Ec "^-- [^ ]*known-good\.new\.[0-9]+/manifest\.json .*old=0 kg=1")"
check "promote barrier: the filesystem is committed after the renames and before the old copy is gone" 1 \
    "$(sync_lines | grep -Ec "^-f -- $PKG_RECOVERY_DIR old=1 kg=1")"
check "promote barrier: tree sync comes first" yes "$( [ "$(sync_lines | grep -nE 'known-good\.new\.[0-9]+/manifest\.json' | tail -1 | cut -d: -f1)" -lt "$(sync_lines | grep -nE "^-f -- $PKG_RECOVERY_DIR old=1" | cut -d: -f1)" ] && echo yes || echo no)"
check "promote barrier: sync is given the manifest, archives dir and the dir" 1 "$(sync_lines | grep -Ec "^-- [^ ]*known-good\.new\.[0-9]+/manifest\.json [^ ]*known-good\.new\.[0-9]+/archives [^ ]*known-good\.new\.[0-9]+ ")"
# a sync that fails before the swap: nothing changes
new_promote_env; export STUB_SYNC_FAIL_NEWDIR=1
run_promote; check "promote: flushing the new tree fails: exit 1" 1 "$P_RC"; assert_untouched "promote tree sync fails"
# a sync that fails after the renames: the swap is undone
new_promote_env; export STUB_SYNC_FAIL_WHEN_OLD=1
run_promote
check "promote: committing after the swap fails: exit 1" 1 "$P_RC"
check "promote: ... the old known-good is back, byte for byte" "$fp0" "$(kg_fingerprint)"
check "promote: ... pending and prev kept, nothing left over" "yes yes " "$([ -f "$PKG_RECOVERY_DIR/pending/manifest.json" ] && echo yes) $([ -f "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes) $(leftovers)"
unset STUB_SYNC_FAIL_WHEN_OLD STUB_SYNC_FAIL_NEWDIR
# the same barrier in checkpoint_build's replace path (used by apply)
new_promote_env; rm -f "$env_dir/sync.log"
checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; rc=$?
check "checkpoint_build replace: exit 0" 0 "$rc"
check "checkpoint_build replace: the tmp tree is flushed while the old known-good is untouched" 1 "$(sync_lines | grep -Ec "^-- [^ ]*known-good\.tmp\.[0-9]+/manifest\.json .*old=0 kg=1")"
check "checkpoint_build replace: filesystem committed with the old copy still present" 1 "$(sync_lines | grep -Ec "^-f -- $PKG_RECOVERY_DIR old=1 kg=1")"
new_promote_env; export STUB_SYNC_FAIL_WHEN_OLD=1
checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; rc=$?
check "checkpoint_build replace: commit fails: exit 1, the old known-good is back unchanged, no leftovers" "1 $fp0 " "$rc $(kg_fingerprint) $(leftovers)"
unset STUB_SYNC_FAIL_WHEN_OLD
new_promote_env; export STUB_SYNC_FAIL_TREE=1
checkpoint_build "$PKG_RECOVERY_DIR/known-good" >/dev/null 2>&1; rc=$?
check "checkpoint_build replace: flushing the tmp tree fails: exit 1, old known-good untouched, no leftovers" "1 $fp0 " "$rc $(kg_fingerprint) $(leftovers)"
unset STUB_SYNC_FAIL_TREE
# ... and in the .prev swap, before the old .prev is deleted
new_promote_env; cp -al "$PKG_RECOVERY_DIR/known-good" "$env_dir/newprev"; rm -f "$env_dir/sync.log"
_apply_swap_prev "$env_dir/newprev" >/dev/null 2>&1; rc=$?
check "swap_prev: exit 0, the new copy is .prev" "0 $(manifest_sum "$PKG_RECOVERY_DIR/known-good")" "$rc $(manifest_sum "$PKG_RECOVERY_DIR/known-good.prev")"
check "swap_prev: committed to disk while the old .prev still exists" 1 "$(sync_lines | grep -Ec "^-f -- $PKG_RECOVERY_DIR/known-good\.prev .*prevold=1")"
new_promote_env; cp -al "$PKG_RECOVERY_DIR/known-good" "$env_dir/newprev"; export STUB_SYNC_FAIL_WHEN_OLD=1
_apply_swap_prev "$env_dir/newprev" >/dev/null 2>&1; rc=$?
check "swap_prev: commit fails: returns 1 and the older .prev is kept" "1 yes" "$rc $([ -f "$PKG_RECOVERY_DIR"/known-good.prev.old.*/marker ] && echo yes)"
unset STUB_SYNC_FAIL_WHEN_OLD

# kernel release of the realtime kernels (two tags: .rt3.arch1)
check "kernel release: linux-rt two tags" 6.14.0-rt3-arch1-1-rt "$(_verify_kernel_release linux-rt 6.14.0.rt3.arch1-1)"
check "kernel release: linux-rt-lts two tags" 6.12.30-rt8-arch1-1-rt-lts "$(_verify_kernel_release linux-rt-lts 6.12.30.rt8.arch1-1)"
new_verify_env; use_after_db; sed -i 's/^linux 6.16.0.arch1-1/linux-rt 6.14.0.rt3.arch1-1/' "$FAKE_PACMAN_DB"; export STUB_UNAME_R=6.14.0-rt3-arch1-1-rt
run_verify; check "verify kernel: linux-rt (two tags) running and installed: PASS" "PASS kernel" "$(vl 1)"
export STUB_UNAME_R=6.14.0-rt2-arch1-1-rt
run_verify; check "verify kernel: linux-rt with another rt number: FAIL" "FAIL kernel" "$(vl 1)"

# stderr is never parsed as output
new_verify_env; use_after_db; export STUB_SYSTEMCTL_ERR='Warning: journal has been rotated since unit was started' STUB_SYSTEMCTL_OUT=""
run_verify; check "verify services: a stderr warning with exit 0 is not a failed unit" "PASS services" "$(vl 3)"
export STUB_SYSTEMCTL_EXIT=1 STUB_SYSTEMCTL_ERR='Failed to connect to bus: No such file or directory'
run_verify
check "verify services: failing systemctl: FAIL with its stderr as the detail" 1 "$(grep -c '^FAIL services: .*Failed to connect to bus' <<<"$V_OUT")"
unset STUB_SYSTEMCTL_ERR STUB_SYSTEMCTL_EXIT STUB_SYSTEMCTL_OUT
export STUB_IP4_OUT="" STUB_IP6_OUT="" STUB_IP4_ERR='RTNETLINK answers: Operation not supported' STUB_IP6_ERR='Cannot open netlink socket'
run_verify
check "verify network: stderr text from ip is not a route" "FAIL network" "$(vl 5)"
check "verify network: ... the detail is not the stderr text" 0 "$(grep '^FAIL network' <<<"$V_OUT" | grep -c 'RTNETLINK\|netlink')"
export STUB_IP4_OUT="default via 10.0.0.1 dev eth0\n"
run_verify; check "verify network: the route comes from stdout, stderr noise ignored" "PASS network" "$(vl 5)"
check "verify network: ... and the PASS detail is the route" 1 "$(grep -c '^PASS network: default via 10.0.0.1' <<<"$V_OUT")"
export STUB_IP_EXIT=1 STUB_IP4_OUT=""
run_verify; check "verify network: ip failing: FAIL with its stderr" 1 "$(grep -c '^FAIL network: ip route did not run: RTNETLINK' <<<"$V_OUT")"
unset STUB_IP4_OUT STUB_IP6_OUT STUB_IP4_ERR STUB_IP6_ERR STUB_IP_EXIT
export STUB_NVSMI_OUT="" STUB_NVSMI_ERR='GPU 0: this is only a warning on stderr'
run_verify; check "verify gpu: a GPU-looking line on stderr is not a GPU list" "FAIL gpu" "$(vl 2)"
unset STUB_NVSMI_OUT STUB_NVSMI_ERR

# refusal wording (the sweep may already have run)
new_promote_env; export PKG_VERIFY_NETWORK=false
run_promote
check "promote refusal: says what was not changed" yes "$(has -- 'known-good, pending and known-good.prev were not changed' "$P_ERR")"
check "promote refusal: no longer claims 'nothing was changed'" no "$(has -- 'nothing was changed' "$P_ERR")"

# the old known-good is renamed to a name the sweep deletes (never restores) before it is removed
new_promote_env
rc=$( ( mv() { case "$*" in *known-good.discard.*) echo "$*" >> "$env_dir/mv-discard.log" ;; esac; command mv "$@"; }
        rm() { case "$*" in *known-good.old.*) echo "$*" >> "$env_dir/rm-old.log" ;; esac; command rm "$@"; }
        pkg_promote >/dev/null 2>&1; echo $? ) )
check "promote: exit 0 with mv/rm watched" 0 "$rc"
check "promote: the old known-good is renamed to known-good.discard.PID" 1 "$(grep -c -- '-T -- .*known-good\.old\.[0-9]* .*known-good\.discard\.[0-9]*$' "$env_dir/mv-discard.log" 2>/dev/null)"
check "promote: no rm ever touches a known-good.old.* path" no "$([ -e "$env_dir/rm-old.log" ] && echo yes || echo no)"
# known-good.discard.* is debris for the sweep, never a known-good
new_promote_env; mkdir "$PKG_RECOVERY_DIR/known-good.discard.994"; cp -al "$PKG_RECOVERY_DIR/known-good/." "$PKG_RECOVERY_DIR/known-good.discard.994/"
rm -rf "$PKG_RECOVERY_DIR/known-good"
bash -c "$RUNLIBS; _apply_sweep" >/dev/null 2>&1
check "sweep: known-good missing + only known-good.discard.*: nothing is restored from it, it is removed" "no no" \
    "$([ -e "$PKG_RECOVERY_DIR/known-good" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/known-good.discard.994" ] && echo yes || echo no)"

# a forced promotion is marked, and keeps the superseded known-good as known-good.prev
new_promote_env; export PKG_VERIFY_NETWORK=false
run_promote --force
check "forced: exit 0" 0 "$P_RC"
check "forced: manifest has forced=true and the overridden check names" 'true ["network"]' "$(jq -c '"\(.forced) \(.verify_failures)"' -r "$PKG_RECOVERY_DIR/known-good/manifest.json")"
check "forced: status shows forced" true "$("$PKG_UPDATE" status | jq -r .known_good.forced)"
check "forced: .prev is the superseded known-good (created 2020, old grub archive)" "2020-01-01T00:00:00Z 1" \
    "$(jq -r .created "$PKG_RECOVERY_DIR/known-good.prev/manifest.json") $(ls "$PKG_RECOVERY_DIR/known-good.prev/archives" | grep -c '2:2.16-1')"
check "forced: the older .prev (marker) is replaced, not nested" no "$([ -e "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes || echo no)"
check "forced: .prev is a whole known-good (every archive present)" 0 "$(_apply_dir_complete "$PKG_RECOVERY_DIR/known-good.prev"; echo $?)"
check "forced: pending gone, nothing left over" "no " "$([ -e "$PKG_RECOVERY_DIR/pending" ] && echo yes || echo no) $(leftovers)"
check "forced: the final lines say so" 1 "$(grep -c 'updated by --force' <<<"$P_OUT")"
# kernel mismatch + failing network: both names, in check order
new_promote_env; export STUB_UNAME_R=6.15.3-arch1-1 PKG_VERIFY_NETWORK=false
run_promote --force
check "forced: verify_failures lists every overridden check" '["kernel","network"]' "$(jq -c .verify_failures "$PKG_RECOVERY_DIR/known-good/manifest.json")"
# forced only because of the pending record: forced=true, no failed checks, .prev kept
new_promote_env; set_pending '{"started":"2026-10-17T10:00:00Z","mode":"normal","state":"failed","packages":[]}'
run_promote --force
check "forced by a failed pending record: forced=true, verify_failures empty, .prev kept" 'true [] 2020-01-01T00:00:00Z' \
    "$(jq -r '"\(.forced) \(.verify_failures)"' "$PKG_RECOVERY_DIR/known-good/manifest.json") $(jq -r .created "$PKG_RECOVERY_DIR/known-good.prev/manifest.json")" 
# a normal promote is not forced and clears .prev
new_promote_env
run_promote
check "not forced: no forced marker in the manifest, status says false, .prev cleared" "null false no" \
    "$(jq -r '.forced' "$PKG_RECOVERY_DIR/known-good/manifest.json") $("$PKG_UPDATE" status | jq -r .known_good.forced) $([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no)"
# forced and no known-good yet: nothing to keep; an existing .prev stays
new_promote_env; rm -rf "$PKG_RECOVERY_DIR/known-good"; export PKG_VERIFY_NETWORK=false
run_promote --force
check "forced without a known-good: promoted, the existing .prev stays" "0 true yes" "$P_RC $(jq -r .forced "$PKG_RECOVERY_DIR/known-good/manifest.json") $([ -f "$PKG_RECOVERY_DIR/known-good.prev/marker" ] && echo yes)"
# an unmarkable manifest never gets promoted
new_promote_env; export PKG_VERIFY_NETWORK=false
rc=$( ( write_atomic() { return 1; }; pkg_promote --force >/dev/null 2>"$env_dir/lerr"; echo $? ) )
check "forced: the mark cannot be written: exit 1, nothing changed (no swallowed failure)" 1 "$rc"; assert_untouched "forced mark fails"
# a forced promote that fails the .prev copy changes nothing
new_promote_env; export PKG_VERIFY_NETWORK=false
rc=$( ( cp() { return 1; }; pkg_promote --force >/dev/null 2>&1; echo $? ) )
check "forced: the old known-good cannot be kept: exit 1, nothing changed" 1 "$rc"; assert_untouched "forced prev copy fails"
# SIGKILL between the renames of the .prev swap: the next sweep makes the superseded known-good the .prev
new_promote_env; export PKG_VERIFY_NETWORK=false
rc=$(RUN_LIB 'mv() { case "$*" in -T\ --\ */known-good.prev.new.*\ */known-good.prev) kill -KILL $$; sleep 0.3; return 1 ;; esac; command mv "$@"; }; pkg_promote --force')
check "forced crash in the .prev swap: killed" 137 "$rc"
check "forced crash: known-good is the new forced one, .prev is missing, the copy waits in .prev.new.*" "true no 1" \
    "$(jq -r .forced "$PKG_RECOVERY_DIR/known-good/manifest.json") $([ -e "$PKG_RECOVERY_DIR/known-good.prev" ] && echo yes || echo no) $(ls -d "$PKG_RECOVERY_DIR"/known-good.prev.new.* 2>/dev/null | wc -l)"
bash -c "$RUNLIBS; _apply_sweep" >/dev/null 2>&1
check "forced crash: the sweep restores the old known-good as .prev" "2020-01-01T00:00:00Z 0" \
    "$(jq -r .created "$PKG_RECOVERY_DIR/known-good.prev/manifest.json" 2>/dev/null) $(ls -d "$PKG_RECOVERY_DIR"/known-good.prev.new.* "$PKG_RECOVERY_DIR"/known-good.prev.old.* 2>/dev/null | wc -l)"

# recovery.sh source: the default (next to pkg-lib.sh) and PKG_RECOVERY_SRC are different files; assert which one wins
new_promote_env
mkdir "$env_dir/libdir"; printf '#!/bin/sh\necho default-source\n' > "$env_dir/libdir/recovery.sh"; printf '#!/bin/sh\necho env-source\n' > "$env_dir/envsrc.sh"
rc=$(RUN_LIB 'unset PKG_RECOVERY_SRC; PKG_LIB_DIR="'$env_dir'/libdir"; pkg_promote')
check "promote: no PKG_RECOVERY_SRC: the recovery.sh next to pkg-lib.sh is installed" "0 default-source 755" "$rc $(sh "$PKG_RECOVERY_DIR/recovery.sh") $(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh")"
new_promote_env; mkdir "$env_dir/libdir"; printf '#!/bin/sh\necho default-source\n' > "$env_dir/libdir/recovery.sh"; printf '#!/bin/sh\necho env-source\n' > "$env_dir/envsrc.sh"
rc=$(RUN_LIB 'export PKG_RECOVERY_SRC="'$env_dir'/envsrc.sh"; PKG_LIB_DIR="'$env_dir'/libdir"; pkg_promote')
check "promote: PKG_RECOVERY_SRC wins over the default" "0 env-source" "$rc $(sh "$PKG_RECOVERY_DIR/recovery.sh")"
new_promote_env; mkdir "$env_dir/libdir"
rc=$(RUN_LIB 'unset PKG_RECOVERY_SRC; PKG_LIB_DIR="'$env_dir'/libdir"; pkg_promote')
check "promote: neither source: warns naming the default path, exit 0, nothing installed" "0 1 no" "$rc $(grep -c "$env_dir/libdir/recovery.sh" "$env_dir/lerr") $([ -e "$PKG_RECOVERY_DIR/recovery.sh" ] && echo yes || echo no)"
check "pkg-lib.sh: PKG_LIB_DIR is the directory of pkg-lib.sh" "$(readlink -f "$HERE/../scripts")" "$PKG_LIB_DIR"

# --- cache: size, keep N, clear -------------------------------------------------------------------
# cache_dispatch ARGS...: the dispatcher as the tests run it (no terminal, no elevation unless the test unsets
# PKG_NO_ELEVATE); stdout+stderr in $C_OUT, status in $C_RC.
cache_dispatch() { C_OUT=$(timeout 60 "$PKG_UPDATE" "$@" </dev/null 2>&1); C_RC=$?; }
pkgfiles_in_cache() { find "$PKG_CACHE_DIR" -maxdepth 1 -name '*.pkg.tar.*' | wc -l; }
# stub_pacman_scc DIR: a pacman that behaves like the real -Scc (checked by hand in a user namespace, see
# the README): it logs its argv and its whole stdin, answers the "remove ALL files from cache?" prompt with
# the first line of stdin (no line = the default, N; --noconfirm = the default too, nothing is read) and on "y"
# deletes every package file of the cache by name.
stub_pacman_scc() {
    cat > "$1/pacman-scc" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$1/scc.argv"
case " \$* " in
    *" --noconfirm "*) exit "\${STUB_SCC_EXIT:-0}" ;;
esac
cat > "$1/scc.stdin"
read -r answer < "$1/scc.stdin"
[ "\$answer" = y ] && [ -z "\${STUB_SCC_KEEP:-}" ] && rm -f "\${PKG_CACHE_DIR:?}"/*.pkg.tar.*
exit "\${STUB_SCC_EXIT:-0}"
STUB
    chmod +x "$1/pacman-scc"
    export PKG_PACMAN="$1/pacman-scc"
}
fill_cache() {  # known sizes: 100 + 50 packages, 20 sig, 7 part, 1000 in download-*, 5 unrelated
    rm -rf "${PKG_CACHE_DIR:?}"; mkdir -p "$PKG_CACHE_DIR/download-AbC123"
    head -c 100 /dev/zero > "$PKG_CACHE_DIR/foo-1-1-x86_64.pkg.tar.zst"
    head -c 50  /dev/zero > "$PKG_CACHE_DIR/bar-2:3-1-any.pkg.tar.xz"
    head -c 20  /dev/zero > "$PKG_CACHE_DIR/foo-1-1-x86_64.pkg.tar.zst.sig"
    head -c 7   /dev/zero > "$PKG_CACHE_DIR/baz-1-1-x86_64.pkg.tar.zst.part"
    head -c 1000 /dev/zero > "$PKG_CACHE_DIR/download-AbC123/qux-1-1-x86_64.pkg.tar.zst"
    head -c 5   /dev/zero > "$PKG_CACHE_DIR/notes.txt"
}
# known_good_link: a known-good archive that is a hardlink of a cache file, content "kernel bits"
KG_ARCHIVE=linux-6.15.3.arch1-1-x86_64.pkg.tar.zst
known_good_link() {
    mkdir -p "$PKG_RECOVERY_DIR/known-good"; echo "kernel bits" > "$PKG_CACHE_DIR/$KG_ARCHIVE"
    ln "$PKG_CACHE_DIR/$KG_ARCHIVE" "$PKG_RECOVERY_DIR/known-good/$KG_ARCHIVE"
}

# cache size: only package files, as a plain integer, no root, no lock, no log
new_apply_env; fill_cache
make_pkexec_stub "$env_dir"; printf '#!/usr/bin/env bash\necho x >> "%s/pkexec-called"\n' "$env_dir" > "$env_dir/pkexec"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; cache_dispatch cache size; echo "$C_RC|$C_OUT" > "$env_dir/o" )
check "cache size: 150 bytes (packages only: no .sig, .part, download-*, other files), exit 0, no pkexec" "0|150 no" "$(cat "$env_dir/o") $([ -e "$env_dir/pkexec-called" ] && echo yes || echo no)"
check "cache size: no log taken" "no" "$([ -e "$PKG_RECOVERY_DIR/logs" ] && echo yes || echo no)"
( acquire_lock; cache_dispatch cache size; echo "$C_RC|$C_OUT" > "$env_dir/o" )
check "cache size runs while the update lock is held" "0|150" "$(cat "$env_dir/o")"
rm -rf "${PKG_CACHE_DIR:?}"; mkdir "$PKG_CACHE_DIR"; cache_dispatch cache size
check "cache size: empty cache" "0|0" "$C_RC|$C_OUT"
rm -rf "${PKG_CACHE_DIR:?}"; cache_dispatch cache size
check "cache size: no cache dir = 0, exit 0" "0|0" "$C_RC|$C_OUT"
mkdir "$PKG_CACHE_DIR"
truncate -s 5000000000 "$PKG_CACHE_DIR/big-1-1-x86_64.pkg.tar.zst"; truncate -s 5000000000 "$PKG_CACHE_DIR/big2-1-1-x86_64.pkg.tar.zst"
cache_dispatch cache size
check "cache size: more than 2^32 bytes is summed exactly" "0|10000000000" "$C_RC|$C_OUT"
rm -rf "${PKG_CACHE_DIR:?}"; mkdir "$PKG_CACHE_DIR"; : > "$PKG_CACHE_DIR/a-1-1-any.pkg.tar.zst"; chmod 000 "$PKG_CACHE_DIR"
cache_dispatch cache size; chmod 755 "$PKG_CACHE_DIR"
if [ "$EUID" != 0 ]; then
    check "cache size: an unreadable cache dir is exit 1 with a message on stderr" "1 1" "$C_RC $(grep -c -i 'cannot read' <<<"$C_OUT")"
fi
cache_dispatch cache size now;   check "cache size with an argument: usage, exit 2" 2 "$C_RC"
cache_dispatch cache;            check "cache without a subcommand: exit 2" 2 "$C_RC"
cache_dispatch cache bogus;      check "cache with an unknown subcommand: exit 2" 2 "$C_RC"
cache_dispatch cache keep;       check "cache keep without N: exit 2" 2 "$C_RC"
cache_dispatch cache clear now;  check "cache clear with an argument: exit 2" 2 "$C_RC"

# cache keep N: validated before anything runs (no pkexec, no paccache, no lock, no log)
new_apply_env
make_pkexec_stub "$env_dir"; printf '#!/usr/bin/env bash\necho x >> "%s/pkexec-called"\n' "$env_dir" > "$env_dir/pkexec"
bad_rcs=""
for v in 0 abc 21 "" 3x -1 007 " 3" "3 " 1.5 +4 100 99999999999999999999 $'3\n' 08; do
    ( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; cache_dispatch cache keep "$v"; echo "$C_RC" > "$env_dir/o" )
    bad_rcs+="$(cat "$env_dir/o")"
done
check "cache keep: 0, abc, 21, '', 3x, -1, 007, ' 3', '3 ', 1.5, +4, 100, huge, '3<newline>', 08 are all exit 2" "222222222222222" "$bad_rcs"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; cache_dispatch cache keep 3 4; echo "$C_RC" > "$env_dir/o" )
check "cache keep with two arguments: exit 2" 2 "$(cat "$env_dir/o")"
check "cache keep bad input: no pkexec, no paccache, no log, no lock file" "no no no no" \
    "$([ -e "$env_dir/pkexec-called" ] && echo yes || echo no) $([ -e "$env_dir/paccache.log" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/logs" ] && echo yes || echo no) $([ -e "$PKG_RECOVERY_DIR/lock" ] && echo yes || echo no)"
cache_dispatch cache keep 0
check "cache keep bad input: the message names the range" 1 "$(grep -c '1 to 20' <<<"$C_OUT")"

# cache keep / clear: root work through pkexec, nothing but the three settings forwarded
new_apply_env
make_pkexec_stub "$env_dir"; printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" > "%s/argv"\n' "$env_dir" > "$env_dir/pkexec"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec" PKG_PACCACHE=evil PKG_PACMAN=evil PKG_CACHE_DIR=/evil PKG_RECOVERY_DIR=/evil; "$PKG_UPDATE" cache keep 5 </dev/null >/dev/null 2>&1 )
read_argv "$env_dir/argv"
check "cache keep elevates through pkexec with the real script path" "env|$(readlink -f "$PKG_UPDATE")|cache|keep|5" "${ARGV[0]}|$(IFS='|'; echo "${ARGV[*]: -4}")"
check "cache keep forwards exactly the three settings (no PKG_PACCACHE, PKG_CACHE_DIR, ...)" \
    "PKG_CACHE_KEEP PKG_PROTECTED_PATTERNS PKG_USER_HOME" "$(printf '%s\n' "${ARGV[@]}" | sed -n 's/^\(PKG_[A-Z_]*\)=.*/\1/p' | paste -sd' ')"
rm -f "$env_dir/argv"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" cache clear </dev/null >/dev/null 2>&1 )
read_argv "$env_dir/argv"
check "cache clear elevates through pkexec with the real script path" "env|$(readlink -f "$PKG_UPDATE")|cache|clear" "${ARGV[0]}|$(IFS='|'; echo "${ARGV[*]: -3}")"
check "cache clear forwards exactly the three settings" \
    "PKG_CACHE_KEEP PKG_PROTECTED_PATTERNS PKG_USER_HOME" "$(printf '%s\n' "${ARGV[@]}" | sed -n 's/^\(PKG_[A-Z_]*\)=.*/\1/p' | paste -sd' ')"

# cache keep: paccache -rk<N> -c <cache>
new_apply_env; fill_cache
echo 7 > "$PKG_CACHE_KEEP_FILE"
cache_dispatch cache keep 1
check "cache keep 1: exit 0" 0 "$C_RC"
check "cache keep 1: paccache gets -rk1 and -c <cache>, nothing else" "-rk1 -c $PKG_CACHE_DIR" "$(cat "$env_dir/paccache.log")"
check "cache keep: first line LOG=<file>" 1 "$(head -n 1 <<<"$C_OUT" | grep -c '^LOG=')"
check "cache keep: the setting file is not written (the UI owns it)" 7 "$(cat "$PKG_CACHE_KEEP_FILE")"
check "cache keep: refreshes the statusbar" "ipc call updates refresh" "$(cat "$env_dir/qs.log" 2>/dev/null)"
rm -f "$env_dir/paccache.log"; cache_dispatch cache keep 20
check "cache keep 20 is the top of the range" "0 -rk20 -c $PKG_CACHE_DIR" "$C_RC $(cat "$env_dir/paccache.log")"
rm -f "$env_dir/paccache.log"; cache_dispatch cache keep 9
check "cache keep 9 (one digit)" "0 -rk9 -c $PKG_CACHE_DIR" "$C_RC $(cat "$env_dir/paccache.log")"
# paccache runs with the update lock closed (fd 200) and no terminal
printf '#!/usr/bin/env bash\n[ -e /proc/$$/fd/200 ] && echo open > "%s/fd200" || echo closed > "%s/fd200"\ncat > "%s/stdin"\n' "$env_dir" "$env_dir" "$env_dir" > "$env_dir/paccache"
cache_dispatch cache keep 2
check "cache keep: paccache does not inherit the lock fd, stdin is /dev/null" "closed 0" "$(cat "$env_dir/fd200") $(wc -c < "$env_dir/stdin")"
# paccache failing / missing: exit 1 and no statusbar refresh
new_apply_env; fill_cache
STUB_PACCACHE_EXIT=1 cache_dispatch cache keep 2
check "cache keep: paccache failure is exit 1 with a message" "1 1" "$C_RC $(grep -c -i 'paccache failed' <<<"$C_OUT")"
check "cache keep: no statusbar refresh after a failure" no "$([ -e "$env_dir/qs.log" ] && echo yes || echo no)"
PKG_PACCACHE="$env_dir/no-such-paccache" cache_dispatch cache keep 2
check "cache keep: paccache missing is exit 1" 1 "$C_RC"
STUB_QS_EXIT=1 cache_dispatch cache keep 2
check "cache keep: a failing statusbar refresh is ignored" 0 "$C_RC"
# lock held / pacman running: exit 3, paccache not run
new_apply_env; fill_cache
( acquire_lock; cache_dispatch cache keep 2; echo "$C_RC" > "$env_dir/o" )
check "cache keep with the lock held: exit 3, paccache not run" "3 no" "$(cat "$env_dir/o") $([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
touch "$env_dir/dblck"; PKG_PACMAN_DBLOCK="$env_dir/dblck" cache_dispatch cache keep 2
check "cache keep while pacman runs: exit 3, paccache not run" "3 no" "$C_RC $([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"
rm -rf "${PKG_CACHE_DIR:?}"; cache_dispatch cache keep 2
check "cache keep without a cache dir: exit 1, paccache not run" "1 no" "$C_RC $([ -e "$env_dir/paccache.log" ] && echo yes || echo no)"

# cache clear: real pacman -Scc asks "remove ALL files from cache? [y/N]"; --noconfirm answers the default N,
# so `pacman -Scc --noconfirm` removes nothing. The answers are fed on stdin instead (never a terminal).
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
cache_dispatch cache clear
check "cache clear: exit 0" 0 "$C_RC"
check "cache clear: pacman is called as -Scc, without --noconfirm (that would answer N and clear nothing)" "-Scc" "$(cat "$env_dir/scc.argv")"
check "cache clear: only y answers on stdin" "y" "$(sort -u "$env_dir/scc.stdin")"
check "cache clear: no package or .sig left in the cache" "0" "$(pkgfiles_in_cache)"
check "cache clear: stale download-* directories are removed first (pacman cannot: it exits 255)" "no" "$([ -e "$PKG_CACHE_DIR/download-AbC123" ] && echo yes || echo no)"
check "cache clear: LOG= first, statusbar refreshed" "1 ipc call updates refresh" "$(head -n 1 <<<"$C_OUT" | grep -c '^LOG=') $(cat "$env_dir/qs.log")"
# no terminal is ever needed: a stdin that never delivers anything must not block
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
C_OUT=$(sleep 5 | timeout 3 "$PKG_UPDATE" cache clear 2>&1); C_RC=$?
check "cache clear: an open stdin with no data does not block it (pacman gets its own stdin)" "0 0" "$C_RC $(pkgfiles_in_cache)"
# a pacman that removes nothing (answered N) is an error, not a silent success
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
STUB_SCC_KEEP=1 cache_dispatch cache clear
check "cache clear: packages left behind is exit 1 and says so" "1 1" "$C_RC $(grep -c -i 'left' <<<"$C_OUT")"
check "cache clear: no statusbar refresh after a failure" no "$([ -e "$env_dir/qs.log" ] && echo yes || echo no)"
STUB_SCC_EXIT=1 cache_dispatch cache clear
check "cache clear: pacman failing is exit 1" 1 "$C_RC"
new_apply_env; rm -f "${PKG_CACHE_DIR:?}"/*; stub_pacman_scc "$env_dir"
cache_dispatch cache clear
check "cache clear: an empty cache is exit 0" 0 "$C_RC"
# lock held / pacman running / no cache dir
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
( acquire_lock; cache_dispatch cache clear; echo "$C_RC" > "$env_dir/o" )
check "cache clear with the lock held: exit 3, pacman not run, cache intact" "3 no 4" "$(cat "$env_dir/o") $([ -e "$env_dir/scc.argv" ] && echo yes || echo no) $(pkgfiles_in_cache)"
touch "$env_dir/dblck"; PKG_PACMAN_DBLOCK="$env_dir/dblck" cache_dispatch cache clear
check "cache clear while pacman runs: exit 3, pacman not run" "3 no" "$C_RC $([ -e "$env_dir/scc.argv" ] && echo yes || echo no)"
rm -rf "${PKG_CACHE_DIR:?}"; cache_dispatch cache clear
check "cache clear without a cache dir: exit 1, pacman not run" "1 no" "$C_RC $([ -e "$env_dir/scc.argv" ] && echo yes || echo no)"
# a download-* that is a symlink is not followed
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
mkdir "$env_dir/elsewhere"; : > "$env_dir/elsewhere/precious"; ln -s "$env_dir/elsewhere" "$PKG_CACHE_DIR/download-link"
cache_dispatch cache clear
check "cache clear: a download-* symlink does not delete its target" "yes" "$([ -e "$env_dir/elsewhere/precious" ] && echo yes || echo no)"

# known-good archives are hardlinks of cache files: wiping the cache by name keeps their content
new_apply_env; fill_cache; known_good_link; stub_pacman_scc "$env_dir"
cache_dispatch cache clear
check "cache clear: the cache name is gone, the known-good hardlink keeps its content" "no kernel bits 1" \
    "$([ -e "$PKG_CACHE_DIR/$KG_ARCHIVE" ] && echo yes || echo no) $(cat "$PKG_RECOVERY_DIR/known-good/$KG_ARCHIVE") $(stat -c %h "$PKG_RECOVERY_DIR/known-good/$KG_ARCHIVE")"
new_apply_env; fill_cache; known_good_link
printf '#!/usr/bin/env bash\ncat >/dev/null\nfind "${PKG_CACHE_DIR:?}" -mindepth 1 -delete\n' > "$env_dir/pacman-rm"; chmod +x "$env_dir/pacman-rm"
PKG_PACMAN="$env_dir/pacman-rm" cache_dispatch cache clear
check "cache clear with a pacman that deletes every cache entry: known-good archive intact, cache empty" "0 kernel bits 0" \
    "$C_RC $(cat "$PKG_RECOVERY_DIR/known-good/$KG_ARCHIVE") $(find "$PKG_CACHE_DIR" -mindepth 1 | wc -l)"
new_apply_env; fill_cache; known_good_link
printf '#!/usr/bin/env bash\nrm -f "${PKG_CACHE_DIR:?}/%s"\n' "$KG_ARCHIVE" > "$env_dir/paccache"
cache_dispatch cache keep 1
check "cache keep with a paccache that unlinks the cache name: known-good archive intact" "0 kernel bits" "$C_RC $(cat "$PKG_RECOVERY_DIR/known-good/$KG_ARCHIVE")"

# --- cache: fix round 1 -----------------------------------------------------------------------------
# the cache directory is a symlink to a real directory (a cache on another disk): find must enter it
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
mv "$PKG_CACHE_DIR" "$env_dir/realcache"; ln -s "$env_dir/realcache" "$PKG_CACHE_DIR"
cache_dispatch cache size
check "cache size through a symlinked cache dir: the real bytes, not 0" "0|150" "$C_RC|$C_OUT"
cache_dispatch cache clear
check "cache clear through a symlinked cache dir: exit 0, packages gone, download-* removed, the link stays" "0 0 no yes" \
    "$C_RC $(find "$env_dir/realcache" -maxdepth 1 -name '*.pkg.tar.*' | wc -l) $([ -e "$env_dir/realcache/download-AbC123" ] && echo yes || echo no) $([ -L "$PKG_CACHE_DIR" ] && echo yes || echo no)"
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
mv "$PKG_CACHE_DIR" "$env_dir/realcache"; ln -s "$env_dir/realcache" "$PKG_CACHE_DIR"
STUB_SCC_KEEP=1 cache_dispatch cache clear
check "cache clear through a symlinked cache dir with a pacman that removes nothing: exit 1 (the post-check sees the files)" "1 1 4" \
    "$C_RC $(grep -c -i 'left' <<<"$C_OUT") $(find "$env_dir/realcache" -maxdepth 1 -name '*.pkg.tar.*' | wc -l)"
new_apply_env; fill_cache
mv "$PKG_CACHE_DIR" "$env_dir/realcache"; ln -s "$env_dir/realcache" "$PKG_CACHE_DIR"
cache_dispatch cache keep 2
check "cache keep through a symlinked cache dir" "0 -rk2 -c $PKG_CACHE_DIR" "$C_RC $(cat "$env_dir/paccache.log")"

# a find that fails part-way is an error, never a partial sum / a false "nothing left" (find is a PATH stub;
# find itself does not descend into subdirectories at -maxdepth 1, so an unreadable subdir is no error)
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
mkdir "$env_dir/fbin"
cat > "$env_dir/fbin/find" <<STUB
#!/usr/bin/env bash
case "\$*:\${STUB_FIND_FAIL:-}" in
    *-printf*:size) echo 100; echo "find: '\$2/x': Input/output error" >&2; exit 1 ;;
    *'*.pkg.tar.*'*:post) [ -z "\$("$(command -v find)" "\$@" 2>/dev/null)" ] || echo "\$2/a" ; echo "find: cannot read" >&2; exit 1 ;;
esac
exec "$(command -v find)" "\$@"
STUB
chmod +x "$env_dir/fbin/find"
PATH="$env_dir/fbin:$PATH" STUB_FIND_FAIL=size cache_dispatch cache size
check "cache size: a find that fails part-way is exit 1 with its message, no partial sum on stdout" "1 1 0" \
    "$C_RC $(grep -c 'Input/output error' <<<"$C_OUT") $(grep -c '^100$' <<<"$C_OUT")"
PATH="$env_dir/fbin:$PATH" STUB_FIND_FAIL=post STUB_SCC_KEEP=1 cache_dispatch cache clear
check "cache clear: a failing post-check listing is exit 1 (never a pass)" "1 1" "$C_RC $(grep -c 'cannot list' <<<"$C_OUT")"
rm -rf "${PKG_CACHE_DIR:?}"; mkdir -p "$PKG_CACHE_DIR/locked"; head -c 40 /dev/zero > "$PKG_CACHE_DIR/a-1-1-any.pkg.tar.zst"; chmod 000 "$PKG_CACHE_DIR/locked"
cache_dispatch cache size; chmod 755 "$PKG_CACHE_DIR/locked"
if [ "$EUID" != 0 ]; then
    check "cache size: an unreadable subdirectory is not entered and not an error" "0|40" "$C_RC|$C_OUT"
fi

# pacman exits 255 because the cache holds a directory it cannot remove: the message names it
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"; mkdir "$PKG_CACHE_DIR/weird-dir"
STUB_SCC_EXIT=255 cache_dispatch cache clear
check "cache clear: exit 255 with a foreign directory in the cache is exit 1 naming that directory" "1 1" "$C_RC $(grep -c 'weird-dir' <<<"$C_OUT")"
new_apply_env; fill_cache; stub_pacman_scc "$env_dir"
STUB_SCC_EXIT=1 cache_dispatch cache clear
check "cache clear: another pacman failure says its exit status" "1 1" "$C_RC $(grep -c 'exit 1' <<<"$C_OUT")"

# --- final review fixes ------------------------------------------------------------------------------
PATH=$ORIG_PATH
kg_field() { jq -r "$1" "$PKG_RECOVERY_DIR/known-good/manifest.json"; }
st_field() { "$PKG_UPDATE" status | jq -r "$1"; }
exists() { [ -e "$1" ] || [ -L "$1" ] && echo yes || echo no; }

# C2.1 provenance in every known-good manifest; status exposes it
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1
check "provenance: apply's checkpoint is source checkpoint, verified false" "checkpoint false" "$(kg_field '"\(.source) \(.verified)"')"
check "provenance: status shows source and verified" "checkpoint false false" "$(st_field '"\(.known_good.source) \(.known_good.verified) \(.known_good.forced)"')"
new_apply_env   # known-good written without the keys (an older manifest)
check "provenance: a manifest without the keys is a verified promote" "promote true false" "$(st_field '"\(.known_good.source) \(.known_good.verified) \(.known_good.forced)"')"
jq '. + {forced: true}' "$PKG_RECOVERY_DIR/known-good/manifest.json" > "$env_dir/m" && cp "$env_dir/m" "$PKG_RECOVERY_DIR/known-good/manifest.json"
check "provenance: ... unless it is forced" "promote false true" "$(st_field '"\(.known_good.source) \(.known_good.verified) \(.known_good.forced)"')"
new_promote_env; run_promote
check "provenance: promote writes source promote, verified true" "0 promote true" "$P_RC $(kg_field '"\(.source) \(.verified)"')"
check "provenance: status of a promoted known-good" "promote true" "$(st_field '"\(.known_good.source) \(.known_good.verified)"')"
new_promote_env; export PKG_VERIFY_NETWORK=false; run_promote --force
check "provenance: a forced promote is not verified" "0 promote false true" "$P_RC $(kg_field '"\(.source) \(.verified) \(.forced)"')"
unset PKG_VERIFY_NETWORK
PATH=$ORIG_PATH

# C2.2 discard keeps the evidence: pending/ becomes pending.discarded/ (replacing an older one)
new_apply_env; kg_before=$(kg_fingerprint)
mkdir "$PKG_RECOVERY_DIR/pending"
echo '{"state":"failed","started":"2026-10-01T00:00:00Z","packages":[{"name":"linux","from":"1","to":"2"}]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
out=$("$PKG_UPDATE" discard </dev/null 2>&1); rc=$?
check "discard: exit 0, pending gone, kept as pending.discarded" "0 no 2026-10-01T00:00:00Z" \
    "$rc $(exists "$PKG_RECOVERY_DIR/pending") $(jq -r .started "$PKG_RECOVERY_DIR/pending.discarded/manifest.json" 2>/dev/null)"
check "discard: says the update stays installed and known-good stays" "1 1" "$(grep -c -i 'stays installed' <<<"$out") $(grep -c -i 'known-good' <<<"$out")"
check "discard: known-good untouched" "$kg_before" "$(kg_fingerprint)"
check "status: the discarded record (state, started, changed)" '{"state":"failed","started":"2026-10-01T00:00:00Z","changed":1}' "$(st_field '.discarded | tojson')"
check "status: no pending after discard" null "$(st_field '.pending')"
mkdir "$PKG_RECOVERY_DIR/pending"; echo '{"state":"failed","started":"2026-10-02T00:00:00Z","packages":[]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
check "discard again: the newer record replaces the older pending.discarded, no leftovers" "2026-10-02T00:00:00Z " \
    "$(jq -r .started "$PKG_RECOVERY_DIR/pending.discarded/manifest.json") $(leftovers)$(find "$PKG_RECOVERY_DIR" -maxdepth 1 -name 'pending.discard*' ! -name pending.discarded | paste -sd' ')"
ln -s known-good "$PKG_RECOVERY_DIR/pending"
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
check "discard of a pending symlink: the link goes, pending.discarded is unchanged and no link" "no 2026-10-02T00:00:00Z no $kg_before" \
    "$(exists "$PKG_RECOVERY_DIR/pending") $(jq -r .started "$PKG_RECOVERY_DIR/pending.discarded/manifest.json") $([ -L "$PKG_RECOVERY_DIR/pending.discarded" ] && echo yes || echo no) $(kg_fingerprint)"
new_env
check "status: discarded is null without a record" null "$(st_field '.discarded')"

# C2.2 apply after a discard never rewrites known-good from the unverified state
new_apply_env
sed -i 's/^linux 6.15.3.arch1-1$/linux 6.14.0.arch1-1/' "$FAKE_PACMAN_DB"   # installed state differs from known-good
mkdir "$PKG_RECOVERY_DIR/pending.discarded"; echo '{"state":"failed","started":"2026-10-01T00:00:00Z","packages":[]}' > "$PKG_RECOVERY_DIR/pending.discarded/manifest.json"
sleep 1.1; kg_before=$(kg_fingerprint)
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"; rc=$?
check "after a discard: apply proceeds (exit 0, awaiting-verification)" "0 awaiting-verification" "$rc $(pending_state)"
check "after a discard: known-good NOT rewritten, no known-good.prev" "$kg_before no" "$(kg_fingerprint) $(exists "$PKG_RECOVERY_DIR/known-good.prev")"
check "after a discard: says so" 1 "$(cat "$env_dir/out" "$env_dir/err" | grep -c -i 'not rewritten.*discarded\|discarded.*not rewritten')"
check "after a discard: the sweep leaves pending.discarded alone" yes "$(exists "$PKG_RECOVERY_DIR/pending.discarded/manifest.json")"
# ... with no known-good at all there is nothing to protect: the checkpoint is taken (unverified)
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"
mkdir "$PKG_RECOVERY_DIR/pending.discarded"; echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending.discarded/manifest.json"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; rc=$?
check "after a discard, no known-good: a checkpoint is taken" "0 checkpoint false" "$rc $(kg_field '"\(.source) \(.verified)"')"

# C2: the cycle from the review: verified known-good, failed update, discard, update, discard, update
new_promote_env; run_promote; fp_verified=$(kg_fingerprint)
PATH=$ORIG_PATH
sed -e 's/^linux .*/linux 6.17.0.arch1-1/' -e 's/^grub .*/grub 2:2.18-1/' "$FAKE_PACMAN_DB" > "$env_dir/after2"
sed -e 's/^linux .*/linux 6.18.0.arch1-1/' "$env_dir/after2" > "$env_dir/after3"
FAKE_PACMAN_AFTER="$env_dir/after2" FAKE_PACMAN_SYU_EXIT=1 "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; c1=$?
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
FAKE_PACMAN_AFTER="$env_dir/after3" "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; c2=$?
"$PKG_UPDATE" discard </dev/null >/dev/null 2>&1
FAKE_PACMAN_AFTER="$env_dir/after3" "$PKG_UPDATE" apply </dev/null >/dev/null 2>&1; c3=$?
check "cycle: failed update, then two updates after discards" "1 0 0" "$c1 $c2 $c3"
check "cycle: the verified known-good is never replaced, no .prev appears" "$fp_verified no true" \
    "$(kg_fingerprint) $(exists "$PKG_RECOVERY_DIR/known-good.prev") $(st_field .known_good.verified)"

# C2.2 promote clears pending.discarded; a refused promote keeps it
new_promote_env; mkdir "$PKG_RECOVERY_DIR/pending.discarded"; echo '{"state":"failed"}' > "$PKG_RECOVERY_DIR/pending.discarded/manifest.json"
export PKG_VERIFY_NETWORK=false; run_promote; unset PKG_VERIFY_NETWORK
check "promote refused: pending.discarded kept" "1 yes" "$P_RC $(exists "$PKG_RECOVERY_DIR/pending.discarded")"
run_promote
check "promote: pending.discarded removed with pending, no leftovers" "0 no no " "$P_RC $(exists "$PKG_RECOVERY_DIR/pending.discarded") $(exists "$PKG_RECOVERY_DIR/pending") $(leftovers)"
PATH=$ORIG_PATH

# M3: a pending/ (or pending.discarded/) without a readable record is state "unknown", never null
new_env
mkdir "$PKG_RECOVERY_DIR/pending" "$PKG_RECOVERY_DIR/pending.discarded"
check "status: pending dir without a manifest is unknown" unknown "$(st_field .pending.state)"
check "status: pending.discarded dir without a manifest is unknown" unknown "$(st_field .discarded.state)"
echo 'not json' > "$PKG_RECOVERY_DIR/pending/manifest.json"
check "status: an unreadable pending record is unknown" unknown "$(st_field .pending.state)"

# I2: changed = packages whose version changed; a failed update that changed packages says so
new_env; mkdir "$PKG_RECOVERY_DIR/pending"
echo '{"state":"failed","started":"x","packages":[{"name":"a","from":"1","to":"2"},{"name":"b","from":null,"to":"1"}]}' > "$PKG_RECOVERY_DIR/pending/manifest.json"
check "status: pending.changed counts the changed packages" 2 "$(st_field .pending.changed)"
new_apply_env
FAKE_PACMAN_SYU_EXIT=2 "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>"$env_dir/err"
check "-Syu fails with changes: says partly changed, do not reboot, restore or finish" "1 1 1 1" \
    "$(grep -c 'partly changed' "$env_dir/err") $(grep -c -i 'do not reboot' "$env_dir/err") $(grep 'partly changed' "$env_dir/err" | grep -c -F "$PKG_RECOVERY_DIR/recovery.sh") $(grep -c -i 'finish the update' "$env_dir/err")"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err2"
check "gate over a failed record with changes: says partly changed, do not reboot" "1 1" "$(grep -c 'partly changed' "$env_dir/err2") $(grep -c -i 'do not reboot' "$env_dir/err2")"
new_apply_env
FAKE_PACMAN_SYUW_EXIT=1 "$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"
check "-Syuw fails (nothing changed): no partly-changed alarm" 0 "$(grep -c 'partly changed' "$env_dir/err")"

# I1: apply installs recovery.sh after the checkpoint, before pacman; a failure only warns
new_apply_env; rm -rf "$PKG_RECOVERY_DIR/known-good"
printf '#!/bin/sh\necho stub recovery\n' > "$env_dir/rsrc.sh"; export PKG_RECOVERY_SRC="$env_dir/rsrc.sh"
FAKE_PACMAN_WATCH="$PKG_RECOVERY_DIR/recovery.sh" FAKE_PACMAN_WATCH_OUT="$env_dir/rwatch" "$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>&1; rc=$?
check "apply: recovery.sh installed (755) before pacman -Syuw ran" "0 755 stub recovery" "$rc $(stat -c %a "$PKG_RECOVERY_DIR/recovery.sh" 2>/dev/null) $(sh "$env_dir/rwatch.Syuw" 2>/dev/null)"
check "apply: the final message names the installed recovery.sh by its absolute path" 1 "$(tail -n 3 "$env_dir/out" | grep -c -F "$PKG_RECOVERY_DIR/recovery.sh")"
new_apply_env; export PKG_RECOVERY_SRC="$env_dir/not-there.sh"
"$PKG_UPDATE" apply </dev/null >/dev/null 2>"$env_dir/err"; rc=$?
check "apply: recovery.sh source missing only warns" "0 awaiting-verification 1 no" "$rc $(pending_state) $(grep -c -i 'recovery.sh' "$env_dir/err") $(exists "$PKG_RECOVERY_DIR/recovery.sh")"
unset PKG_RECOVERY_SRC

# I3: at a terminal apply warns before -Syu; without one (the UI) it does not
new_apply_env
"$PKG_UPDATE" apply </dev/null >"$env_dir/out" 2>&1
check "no terminal: no Ctrl-C warning" 0 "$(grep -c 'do not press Ctrl-C' "$env_dir/out")"
new_apply_env
timeout 60 script -qec "$PKG_UPDATE apply" /dev/null </dev/null >"$env_dir/out" 2>&1
check "terminal: one Ctrl-C warning, before -Syu starts" "1 awaiting-verification" "$(grep -c 'Installing — do not press Ctrl-C or close this terminal until it finishes.' "$env_dir/out") $(pending_state)"

# M2: fetch-missing validates its arguments before elevating
new_apply_env
printf '#!/usr/bin/env bash\nprintf "%%s\\0" "$@" > "%s/argv"\n' "$env_dir" > "$env_dir/pkexec"; chmod +x "$env_dir/pkexec"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"
  "$PKG_UPDATE" fetch-missing --bogus >/dev/null 2>&1; echo "a-$?" > "$env_dir/rc"
  "$PKG_UPDATE" fetch-missing --yes extra >/dev/null 2>&1; echo "b-$?" >> "$env_dir/rc" )
check "fetch-missing: a bad argument is exit 2 and never reaches pkexec" "a-2 b-2 no" "$(paste -sd' ' "$env_dir/rc") $(exists "$env_dir/argv")"
( unset PKG_NO_ELEVATE; export PKG_PKEXEC="$env_dir/pkexec"; "$PKG_UPDATE" fetch-missing --yes </dev/null >/dev/null 2>&1 )
check "fetch-missing --yes still elevates" yes "$(exists "$env_dir/argv")"


PATH=$ORIG_PATH

if [ "$fails" -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
