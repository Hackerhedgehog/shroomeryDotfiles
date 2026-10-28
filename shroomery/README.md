# shroomery

The non-UI half of the desktop: scripts that set the wallpaper and keep the
color theme in sync across apps, background listeners, user settings and the
generated palette. The UI lives in `~/.config/quickshell`, the compositor
config in `~/.config/hypr`.

Nothing here depends on `~/.mydotfiles` or `~/.config/ml4w`.

## Layout

```
shroomery/
├── lib.sh            paths + helpers sourced by every script (mirror of quickshell/shared/Paths.qml)
├── notify.sh         notify_user() wrapper around notify-send, sourced by hypr scripts
├── listeners.sh      start/stop the background listeners
├── listeners/        gtk-theme.sh, low-battery.sh, animated-wallpaper.sh, night-light.sh
├── screencolors/     screen color sampler package for scripts/screen-colors.py (own README.md)
├── scripts/          the commands (see below)
├── settings/         user state, plain files
├── tests/            bash tests for lib.sh helpers and the safe update (bash tests/night-light.sh, bash tests/pkg-update.sh, bash tests/recovery.sh; `tests/fakes/pacman` is the fake pacman)
├── colors/           matugen output
└── effects/          wallpaper effects, one ImageMagick snippet per file (sourced by wallpaper.sh)
~/.cache/shroomery/   generated wallpaper files (safe to delete, see clear-wallpaper-cache.sh)
$XDG_RUNTIME_DIR/shroomery/  runtime state, gone after a reboot (lib.sh SHROOMERY_RUNTIME)
```

## Scripts

| Script | What it does | Called by |
|--------|--------------|-----------|
| `scripts/autostart.sh` | Session start: creates the cache, starts `qs` and the OverviewApp instance, restores the wallpaper + theme. Logs to `~/.cache/shroomery/autostart.log`. | `hypr/autostart.lua` |
| `scripts/wallpaper.sh [IMAGE] [opts]` | Applies the wallpaper effect, sets the image with `awww` (a video or GIF instead goes to `animated-wallpaper.sh start`, without effect; theming and the variants then use its first frame, `~/.cache/shroomery/frames/`), runs `matugen` on it (seeded by the accent settings: the chosen one of the image's colors, or the fixed accent color; also writes `~/.cache/shroomery/wallpaper-colors`), reloads theme consumers, then renders the blurred/square copies in the background (exits without waiting for them). `--random [DIR]`, `--skip-wallpaper`, `--skip-theming`, `--monitor`, `--crop-gravity`. | WallpaperApp, `autostart.sh`, `apply-theme.sh`, keybind |
| `scripts/animated-wallpaper.sh` | Animated wallpapers with `mpvpaper` (`no-audio loop hwdec=auto profile=fast panscan=1.0`, `-p -a FULL`: pauses itself while hidden or a window is fullscreen) above awww's still. `start FILE [OUTPUT]` (default `ALL`; one monitor out of an `ALL` one splits it into one mpvpaper per remaining monitor), `stop [OUTPUT]`, `pause` (awww gets a still of the frame on screen via mpv IPC `screenshot-to-file`, then mpvpaper stops), `resume` (from where it paused), `sync` (pause on battery or in gamemode, else resume), `status`. What plays is kept in `~/.cache/shroomery/animated-wallpaper`. | `wallpaper.sh`, `autostart.sh`, `listeners/animated-wallpaper.sh`, `hypr/scripts/gamemode.sh` |
| `scripts/screen-colors.py` | Screen color sampler daemon (protocol v2): per monitor it rebuilds a small picture of the screen (wallpaper — an animated one decoded by `ffmpeg` in step with mpv — + visible windows via `grim -T`, piped, never written to disk) and each client subscribes to its own monitor, source (screen / wallpaper) and regions (ring, edges, rectangles); smoothed colors on `$XDG_RUNTIME_DIR/shroomery/screen-colors.sock` (protocol in `screencolors/README.md`). One copy at a time; exits 5 s after its last client. `--rate`, `--idle-exit`, `--pattern` (test picture), `--watch [--monitor M] [--subscribe JSON\|@file]`. | quickshell VisualizerApp overlay + setup preview (later: the LED bridge) |
| `scripts/apply-theme.sh` | `--color '#rrggbb'` palette from a fixed accent, `--wallpaper [N]` palette from the current wallpaper's Nth color (0 = most dominant), `--scheme TYPE` switches the matugen scheme type, `--reapply` re-applies whatever is recorded. Records each choice in `settings/accent`, `accent-index`, `accent-scheme` once matugen succeeded. | SettingsApp accent picker, `toggle-theme.sh`, `listeners/gtk-theme.sh` |
| `scripts/toggle-theme.sh` | Flips GTK dark/light in `gtk-3.0`/`gtk-4.0` `settings.ini`. Re-themes itself only if the gtk-theme listener isn't running. | QuickSettingsPanel, `SUPER+SHIFT+M` |
| `scripts/power.sh -l\|-s\|-e\|-r\|-p` | Lock (hyprlock), suspend, logout, reboot, power off. Uses `hyprshutdown` when installed. | PowerPanel, `hypr/autostart.lua` (lock on login), `SUPER+L` |
| `scripts/check-updates.sh` | Prints pending update count as JSON (`text`, `class` green/yellow/red); prints nothing at 0. Runs serialized via `flock`. | StatusbarApp UpdatesModule |
| `scripts/install-updates.sh` | Opens the Settings window on the Update tab (`qs ipc call settings openTab update`); exit 1 with a message on stderr when qs is not running. There is no terminal fallback. | StatusbarApp UpdatesModule, `SUPER+U` |
| `scripts/pkg-update.sh status` | Safe system update (see "Safe update" below). `check [--refresh] [--system]` prints the pending updates as JSON `{updates:[{name,old,new,held}], count, held_count, refreshed}` (`count` = updates not held back by `IgnorePkg`/`IgnoreGroup`, `held_count` = the held ones, which are also listed with `held:true`); no root, it syncs a private temp database under `$XDG_RUNTIME_DIR/shroomery/pkg-check-db` the way `checkupdates` does and never touches `/var/lib/pacman/sync`; `--refresh` deletes that temp database first (full re-download); `--system` ignores `IgnorePkg`/`IgnoreGroup` (nothing held); exit 1 with a message on stderr when the sync or query fails. `status`: JSON `{known_good: null\|{created,kernel,forced,source,verified}, pending: null\|{state,started,changed}, discarded: null\|{state,started,changed}, matches: bool}`; `matches` = the installed protected set equals the known-good record by package name + version (`false` with no known-good); `source`/`verified` see "Provenance" under Safe update; `discarded` is the record `discard` kept (`pending.discarded/`); `changed` = the number of packages whose version the update changed (`null` when the record does not list them); a `pending/` or `pending.discarded/` that exists without a readable record is `{state: "unknown"}`, never `null`. `fetch-missing [--yes]` downloads the archives of installed protected packages that the pacman cache lacks from the Arch Linux Archive (`https://archive.archlinux.org/packages/<letter>/<name>/`, epoch colon as `%3A`, saved under pacman's literal-colon name): it checks that the cache filesystem has the summed `Content-Length` plus 10 % free (else refuses, nothing downloaded), lists the packages and asks y/N on stdin unless `--yes` (declined = "nothing downloaded", exit 0), then fetches each package and its `.sig` as `*.part`, verifies the signature (gpg against the pacman keyring, key fully trusted) and `.PKGINFO` pkgname/pkgver, and only then moves them into the cache; a package that fails is deleted, reported by name and version and skipped, and the exit status is 1. Needs write access to the cache: it re-executes itself as root through `pkexec` (see "Elevation, lock and log" under Safe update), takes the update lock and logs to `logs/`; a UI always passes `--yes`. `apply [--system] [--force] [--yes]` and `discard` are the update transaction (see "Apply and discard" under Safe update); `fetch-missing` and `apply` check their arguments before `pkexec` (a typo never reaches the password prompt); exit codes 0 done, 1 failed, 2 usage, 3 another update runs, 4 an unpromoted pending update. Exit 2 on an unknown subcommand. `verify` and `promote [--force] [--yes]` are described under "Verify and promote" below (`verify`: no root; `promote`: root, same elevation, lock and log as `apply`; exit 1 = refused or failed). `cache size`, `cache keep N` and `cache clear` are described under "Cache management" below. | quickshell SettingsApp Update tab (`SettingsApp/UpdateState.qml`) |
| `scripts/pkg-lib.sh` | Functions for `pkg-update.sh`, sourced after `lib.sh`: `protected_patterns`, `protected_installed` (`name version` lines of installed packages matching a pattern), `manifest_json KIND` (`{created, kernel, patterns[], packages[{name,version,archive,sha256}], installed[{name,version}]}`), `write_atomic FILE` (stdin to `FILE.tmp.$$`, then `mv`). `check_updates [--refresh] [--system]` (the `check` JSON), `pacman_conf_without_ignores SRC DEST` (SRC minus every `IgnorePkg`/`IgnoreGroup` line). `missing_archives` (`name version` lines of protected packages without a cache file), `archive_url NAME VERSION ARCH`, `fetch_missing [--yes]`, `pkg_verify_signature SIG PKG` (default `PKG_VERIFY`). `settings_cache_keep` (1..20, else 3), `settings_protected` (both: `PKG_CACHE_KEEP` / `PKG_PROTECTED_PATTERNS` env first, the settings file second), `elevate SCRIPT ARGS…`, `acquire_lock`, `log_start NAME` / `log_finish`. Test overrides: `PKG_RECOVERY_DIR`, `PKG_CACHE_DIR`, `PKG_PACMAN`, `PKG_PACMAN_CONF`, `PKG_PROTECTED_FILE`, `PKG_DBPATH` (the real pacman DBPath). Fetch overrides: `PKG_ARCHIVE_URL` (Archive base, https or file://), `PKG_VERIFY` (command run as `$PKG_VERIFY SIGFILE PKGFILE`), `PKG_GPG_DIR` (keyring home), `PKG_FREE_BYTES` (free space of the cache fs). Elevation/lock overrides: `PKG_PKEXEC` (the pkexec command), `PKG_NO_ELEVATE` (never re-exec), `PKG_PACMAN_DBLOCK` (pacman's `db.lck`), `PKG_CACHE_KEEP_FILE`, `PKG_TEST_EUID`. `verify_system` and `pkg_promote [--force]` (see "Verify and promote"); test overrides `PKG_VERIFY_KERNEL`/`_GPU`/`_SERVICES`/`_JOURNAL`/`_NETWORK` (a command that replaces one check: exit 0 = PASS) and `PKG_RECOVERY_SRC` (the `recovery.sh` to install). | `pkg-update.sh` |
| `scripts/recovery.sh` | Emergency restore of the protected packages from a TTY (see "Recovery" below). Standalone: bash, `pacman`, `jq`, `sha256sum`, `flock`, `gum` when present; no `lib.sh`, nothing from `~/.config`. `promote` installs it as `<storage>/recovery.sh`, and that copy is the one to run after a bad update. Not root: re-executes through `sudo`. Test overrides: `PKG_RECOVERY_DIR`, `PKG_PACMAN`, `PKG_MKINITCPIO`, `PKG_GRUB_MKCONFIG`, `PKG_PACMAN_DBLOCK`, `PKG_ASSUME_YES` (skip the questions), `PKG_NO_GUM`, `PKG_NO_ELEVATE`, `PKG_SUDO`. | you, from a TTY (`sudo /var/lib/shroomery/recovery/recovery.sh`) |
| `scripts/terminal.sh [args]` | Launches the terminal named in `settings/terminal`. | StatusbarApp TerminalModule |
| `scripts/uninstall-app.sh --plan\|--run <desktop-entry-id>` | Uninstalls a launcher app. `--plan` prints what would go (then `default=n`); `--run` does it, printing progress (stderr merged). An app whose `Exec` is under `~/AppImages` loses the AppImage (or its folder), its `.desktop` file and its icon in `~/AppImages/icons`; one owned by a pacman/AUR package gets `pkexec pacman -Rns`. | quickshell LauncherApp (right click → Uninstall) |
| `scripts/ocr.sh [--lang CODE]` | Freezes the screen (`hyprpicker -z`), lets you drag a region (`slurp`), prints the text `tesseract` reads in it (`grim` → `magick` cleanup → `tesseract`). Exit 1 = selection cancelled or timed out, 2 = missing dependency, 3 = capture/OCR failed. `--list-langs` lists installed tesseract languages (without `osd`/`equ`). Language defaults to `settings/ocr-language`. | quickshell OcrApp (`SUPER+ALT+A`) |
| `scripts/conservation-mode.sh status\|on\|off\|toggle` | Lenovo battery conservation mode (`/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode`, caps charging). `status` prints `available=` and `enabled=`; changes re-run the script through `pkexec`. Exit 1 = bad arguments / unsupported, 2 = password prompt dismissed, 3 = write failed. | quickshell BatteryPanel (click the charge level), battery module (right click) |
| `scripts/lid-switch.sh status\|set KEY [ACTION]` | What closing the lid does. `status` prints `present=true\|false`, the `HandleLidSwitch` / `HandleLidSwitchExternalPower` values logind uses now (`""` = not set) and logind's `CanHibernate` / `CanHybridSleep` / `CanSuspendThenHibernate`. `set` re-runs itself through `pkexec`, writes the key in the `[Login]` section of `/etc/systemd/logind.conf` (no ACTION = comment it out) and runs `systemctl reload systemd-logind`. Exit 1 = bad arguments, 2 = password prompt dismissed, 3 = write failed. | quickshell BatteryPanel (battery panel) |
| `scripts/editor.sh FILE` | Opens a file in the editor named in `settings/editor`. | SettingsApp "Edit" (Bar & Dock) |
| `scripts/clear-wallpaper-cache.sh` | Deletes `~/.cache/shroomery` and re-applies the default wallpaper. | WallpaperApp |
| `scripts/wallpaper-thumbnails.sh [DIR]` | Renders 560px JPEG previews (videos/GIFs: first frame via `ffmpeg`) of a wallpaper folder (default: the configured one) into `~/.cache/shroomery/thumbnails/<md5 of folder>/`, skipping ones that exist and deleting ones whose image was edited, replaced or removed. | WallpaperApp (on open, folder change, reload) |
| `scripts/hyprsunset.sh [toggle\|on\|off\|status\|apply\|sync\|wanted\|sun-times]` | Night light. `on` starts `hyprsunset -t T -g G` from `settings/night-light.json`, `apply` re-applies them live (`hyprctl hyprsunset temperature/gamma`), `wanted` prints what the schedule wants now (`on`/`off`/`none`), `sync` switches to it, `sun-times` prints today's `SUNRISE SUNSET` (wttr.in `?format=%S+%s`, same location as the dashboard weather; cached in `~/.cache/shroomery/sun-times`, at most one attempt per 30 min). No argument = `toggle`. | `SUPER+SHIFT+H`, quickshell SettingsApp, `listeners/night-light.sh` |
| `scripts/screenshot.sh [area\|window\|fullscreen [DELAY]]` | Terminal screenshot (`grim`, `slurp`, window geometry from `hyprctl`) into `~/Pictures/Screenshots`, copied with `wl-copy`. No arguments: pick mode and delay with `fzf`. | shell alias `screenshot` |
| `scripts/finder.sh` | `fzf` over the current directory (4 levels); prints `TYPE_DIR:path` or `TYPE_FILE:path`. | `finder` function in `bashrc`/`zshrc` `30-autostart` |
| `scripts/apps.sh` | `fzf` launcher over desktop entries (system, user, Flatpak); starts the pick with `setsid`. | shell alias `apps` |
| `scripts/quicklinks.sh` | `fzf` over `~/.quicklinks` (`Name \| Description \| Command` per line), runs the pick. | shell alias `quick` |
| `scripts/ascii-header.sh [TEXT]` | `figlet -f smslant` of TEXT (asks when missing) as a `cat <<"EOF"` block, copied with `wl-copy`. | shell alias `ascii` |
| `listeners/gtk-theme.sh` | Watches `gtk-3.0/settings.ini`; on a dark/light flip runs `apply-theme.sh --reapply` and `hypr/scripts/gtk.sh`. | `listeners.sh --startall` |
| `listeners/low-battery.sh` | Notifies at 20 % and 15 % while discharging. | `listeners.sh --startall` |
| `listeners/animated-wallpaper.sh` | Watches power-supply uevents (`udevadm monitor`); when AC is plugged or unplugged runs `animated-wallpaper.sh sync`. | `listeners.sh --startall` |
| `listeners/night-light.sh` | Every minute runs `hyprsunset.sh wanted`; switches on/off only when that changes (a manual toggle holds until the next on/off time). The first pass and the first after a suspend (over 3 min since the last pass) apply the schedule, so a listener restart drops a manual override. Decision: `lib.sh night_light_action`. | `listeners.sh --startall` |
| `listeners.sh` | `--startall`, `--stopall`, `--restartall`, `--start/--stop/--restart NAME`. | `hypr/autostart.lua`, `hypr/scripts/power.sh` (stop on exit) |

## Settings (`settings/`)

Plain one-line text files unless noted. A missing file means the default.

| File | Content | Default | Read by | Written by |
|------|---------|---------|---------|------------|
| `statusbar.json` | JSON merged over StatusbarApp defaults (`bar.enabled`, `bar.alwaysExpanded`, modules, sizes…). Reference: `quickshell/StatusbarApp/statusbar.json` | built-in | StatusbarApp | StatusbarApp, SettingsApp |
| `dock.json` | JSON merged over DockApp defaults (`dock.enabled`, `dock.autohide`, `apps.pinned`…). Reference: `quickshell/DockApp/dock.json` | built-in | DockApp | DockApp, SettingsApp |
| `accent` | `wallpaper` or `#rrggbb` — what the palette is generated from (a fixed color also survives wallpaper changes) | `wallpaper` | `apply-theme.sh`, `wallpaper.sh`, SettingsApp | `apply-theme.sh` |
| `accent-index` | Which of the wallpaper's colors seeds the palette: `0`–`2`, most dominant first | `0` | `apply-theme.sh`, `wallpaper.sh`, SettingsApp | `apply-theme.sh` |
| `visualizer.json` | Visualizer look, written by the setup panel's Start (and Super+arrows): `style` (`center-out`\|`center-in`\|`border`), `draw` (`bars`\|`wave`\|`line`), `monitor` ("" = focused), `sensitivity` (0.5–2.0), `barWidth` (1–12 px), `barSpacing` (0–12), `lineWidth` (1–8), `minLength` (0–40), `outX`/`outY`/`outDiameter` and `inX`/`inY`/`inDiameter` (circle center as fractions of the screen, diameter of its short side, 0.05–1.0), `smoothness` (0–1, blur across bands), `outline` (0–6 px dark rim, 0 = off), `wallpaperOnly` (bool, used from part 3). Bad values fall back per key. | style center-out, draw bars, sensitivity 1.0, barWidth 3, barSpacing 2, lineWidth 3, minLength 4, out 0.5/0.5/0.24, in 0.5/0.5/0.90, smoothness 0.5, outline 1.5 | quickshell VisualizerApp | quickshell VisualizerApp |
| `accent-scheme` | matugen scheme type (`scheme-tonal-spot`, `scheme-vibrant`, `scheme-expressive`, `scheme-content`, `scheme-fidelity`, `scheme-fruit-salad`, `scheme-rainbow`, `scheme-neutral`, `scheme-monochrome`) | `scheme-tonal-spot` | `apply-theme.sh`, `wallpaper.sh`, SettingsApp | `apply-theme.sh` |
| `wallpaper-folder` | Folder of images; its `animated/` subfolder holds the animated wallpapers (videos, GIFs). `$HOME`/`~` are expanded | `~/.config/quickshell/WallpaperApp/wallpapers` | WallpaperApp, `wallpaper.sh` | WallpaperApp |
| `wallpaper-transition-effect` | awww transition (`simple`, `left`, `any`, …) | `simple` | `wallpaper.sh`, WallpaperApp | WallpaperApp |
| `wallpaper-effect` | Name of a script in `effects/`, or `off` | `off` | `wallpaper.sh`, WallpaperApp | WallpaperApp |
| `wallpaper-blur` | ImageMagick blur for the blurred copy, e.g. `50x30` (`0x0` = none) | `50x30` | `wallpaper.sh` | — |
| `terminal` | Terminal command | `kitty` | `terminal.sh`, `hypr/scripts/gtk.sh` | — |
| `editor` | Editor command | `gnome-text-editor` | `editor.sh` | — |
| `launcher` | `quickshell` or `walker` | `quickshell` | `hypr/scripts/launcher.sh` (statusbar launcher button, `SUPER+E`) | — |
| `gamemode-enabled` | Flag file: exists = gamemode on | absent | SettingsApp, `hypr/scripts/gamemode.sh`, `hypr/hyprland.lua` (re-applies it on every config load) | `hypr/scripts/gamemode.sh` |
| `hide-fastfetch` | Flag file: exists = no fastfetch in new terminals | absent | `bashrc`/`zshrc` `30-autostart` | SettingsApp |
| `launcher-view.json` | JSON `{ "appsGrid": bool, "emojiGrid": bool }` — launcher apps/emoji tabs as grid or list | apps list, emoji grid | quickshell LauncherApp | SettingsApp ("Grid Apps", "Grid Emojis") |
| `ocr-language` | tesseract language code for OCR captures (`eng`, `est`, …) | `eng` | `ocr.sh`, quickshell OcrApp | OcrApp |
| `weather-location` | Place for the dashboard's weather, anything wttr.in understands (`Tallinn`, `59.43,24.75`, an airport code) | empty = located by IP | quickshell DashboardPanel, `hyprsunset.sh` (sun times) | — |
| `night-light.json` | `{ "mode": "off"\|"fixed"\|"sun", "on": "HH:MM", "off": "HH:MM", "temperature": 2500–6500, "gamma": 50–100 }`. `sun` = on at sunset, off at sunrise (fixed times when unknown). Bad values: default or clamped | mode off, 21:00, 07:00, 4500, 100 | `hyprsunset.sh`, `listeners/night-light.sh`, quickshell SettingsApp | quickshell SettingsApp |
| `recovery-protected` | Name patterns (glob, one per line; blank lines and `#` comments skipped) of the protected packages the safe update keeps archives of. Patterns matching nothing installed are ignored. Copied into every manifest. The protected set is these matches **plus their closure**: every installed package with an exact (`=`) versioned dependency on a package already in the set, repeated until nothing is added (e.g. `lib32-glibc` needs `glibc=<exact>`, `systemd-sysvcompat` and `systemd-resolvconf` need `systemd=<exact>`); see "Safe update" | `linux`, `linux-headers`, `linux-lts*`, `nvidia*`, `egl-wayland`, `linux-firmware*`, `amd-ucode`, `intel-ucode`, `mkinitcpio*`, `grub`, `systemd`, `systemd-libs`, `glibc`, `mesa`, `vulkan-radeon`, `libdrm` | `pkg-lib.sh` | — |
| `cache-keep` | How many versions per package `paccache -rk<N>` keeps after a successful update | `3` | `pkg-update.sh` (`apply` trims with it; `cache keep N` takes the number as an argument and does not write this file) | SettingsApp Update tab |

## Safe update

A full `pacman -Syu` can break the machine (kernel, GPU driver, firmware, core
libraries). The safe update keeps the last working versions of the critical
packages (the *protected set*, see `recovery-protected`) as real package files,
so a recovery command can put them back from a TTY. The flow is checkpoint,
update, verify, promote. `known-good` is replaced in two places only: `promote`
(a verified state, recorded `source: "promote"`, `verified: true`; a `--force`
promote is `verified: false`), and `apply`'s checkpoint, which takes the installed
state as known-good when known-good does not describe it (first run, a `pacman -Syu`
outside the tool), recorded `source: "checkpoint"`, `verified: false`, with the
superseded one kept as `known-good.prev`. apply never takes that checkpoint from a
state an unpromoted update made: not while a pending record exists (`--force`), and
not while `pending.discarded/` exists (an update was discarded since the last
promote). Design: `~/.config/quickshell/docs/superpowers/specs/2026-10-17-safe-system-update-design.md`.
The parts: the protected set, manifests, `pkg-update.sh status`/`check`/`fetch-missing`/`apply`/`discard`/`verify`/`promote`/`cache`, the root machinery (elevation, lock, log), the emergency `recovery.sh` and the Settings Update tab.

**The protected set** is every installed package matching a `recovery-protected` pattern, plus the
closure over exact reverse dependencies: every installed package that has an exact versioned
dependency (`name=X` or `name=X-REL` in `pacman -Qi`'s "Depends On"; `>=`, `<=`, `<`, `>` do not
count) on a package already in the set is added, repeated until nothing new is added. Without it the
restore's single `pacman -U` fails when glibc or systemd moved ("breaks dependency 'glibc=<new>'
required by lib32-glibc"). Closure members are treated exactly like matched packages: checkpoint
archives, manifest, the missing-archive refusal, `fetch-missing`, recovery. On the machine this was
written on the closure adds `lib32-glibc`, `systemd-resolvconf` and `systemd-sysvcompat`.

**Provenance.** Every known-good manifest (and `known-good.prev`'s) records `source` (`checkpoint` or
`promote`) and `verified` (true only for a non-forced promote); `status` shows both. A manifest written
before these keys existed counts as `source: "promote"`, verified unless it has `forced: true`.

Storage is `/var/lib/shroomery/recovery/` (root-owned, world-readable;
lib.sh `RECOVERY_DIR`): `known-good/` and `pending/` (each a `manifest.json`;
`known-good/` also `archives/`), `known-good.prev/` (the superseded known-good, see Apply and discard),
`pending.discarded/` (the record of a discarded update, until the next promote),
`logs/`, `recovery.sh` (installed by `apply` before pacman runs, and by `promote`). `archives/` holds
**hardlinks** to `/var/cache/pacman/pkg/`, so they cost no space and survive
`paccache` and `pacman -Scc`; the cache and the storage must be on one filesystem.
`/etc/pacman.conf` is never edited. Needs `jq`.

### Apply and discard

`pkg-update.sh apply [--system] [--force] [--yes]` (root, via `elevate`; takes the lock, logs to `logs/`)
runs the spec's update flow:

1. **Checks** before anything is touched: `jq` present, the storage writable, one filesystem with
   the cache (hardlinks), at least 64 MiB free on it (the checkpoint itself costs nothing; downloads
   are checked by `fetch-missing`). A failure is exit 1 and changes nothing.
2. **Pending gate:** if `pending/` exists (any state: `running`, `failed`, `awaiting-verification`)
   it is a hard stop, exit 4, before pacman is called. Verify and promote it, or `discard` it. A `failed`
   record that already changed packages also says "packages were partly changed — do not reboot; restore
   now (recovery.sh) or finish the update".
   `--force` overrides only this stop: known-good is never rewritten from an unverified state (the
   checkpoint step is skipped; with no known-good at all `--force` refuses), and the new pending
   record keeps the old one under `replaced`.
3. **Checkpoint:** without a pending record, if known-good does not match the installed protected
   set by name + version (first run, a `pacman -Syu` outside the tool, a new protected package), the
   current state is taken as the new known-good (`source: "checkpoint"`, `verified: false`): missing archives are fetched first (`--yes` is
   passed on; declining or a failed fetch refuses, naming the package), then it replaces the old
   known-good atomically (the new tree is `sync`ed first and the filesystem committed with `sync -f` before the old known-good, and later the old `.prev`, is deleted). Nothing has been updated at this point. The superseded known-good is not
   thrown away: before it is replaced it is copied as hardlinks (no extra space) to
   **`known-good.prev`** (one generation: an older `.prev` is replaced), with a loud warning naming
   its `created` date and the protected packages whose versions differ from the installed set (a
   mismatch usually means a `pacman -Syu` outside this tool; the old record may be the only verified
   one). If the new known-good cannot be built nothing is renamed and the old one stays. `--force`
   and the pending paths never touch `.prev`. `promote` clears it (see "Verify and promote") and `recovery.sh` (see "Recovery")
   lists it. **After a discard** (`pending.discarded/` exists) a known-good that does not match is NOT
   rewritten: the installed state was made by a discarded, never verified (maybe half applied) update, so
   apply says so and goes ahead against the existing known-good (no `.prev` either). With no known-good at
   all there is nothing to keep, and the checkpoint is taken as on a first run.
   Then **`recovery.sh` is installed** into the storage (the same copy-and-rename as `promote`'s step; a
   missing source or a failing copy only warns), so the emergency tool exists before pacman runs.
4. **Update:** `pacman -Syuw`, then `pacman -Syu`, with `--config` the real config, or with
   `--system` a copy of it without every `IgnorePkg`/`IgnoreGroup` line (made under
   `<storage>/tmp/`, never under `$XDG_RUNTIME_DIR` or the user's home; removed on every exit path).
   `--noconfirm` is added with `--yes` or when stdin is not a terminal; at a terminal without `--yes`
   pacman asks. If the update changed no package (and no earlier pending record is being kept) the
   `running` record is removed again and apply says "nothing to update" (exit 0): there is nothing to
   verify. A failing step always keeps its `failed` record. A `-Syu` that failed after it had changed
   packages ends with "packages were partly changed — do not reboot; restore now (sudo
   /var/lib/shroomery/recovery/recovery.sh) or finish the update (`discard`, then `apply`; known-good is kept)".
   At a terminal apply prints "Installing — do not press Ctrl-C or close this terminal until it finishes."
   right before `-Syu` (see Signals).
5. **Pending record** `pending/manifest.json`, always written to a temp file and renamed:
   `started`, `finished`, `mode` (`normal`/`system`), `pacman_exit`, `state` and `packages`, one
   `{name, from, to}` per package whose version differs between the `pacman -Q` lists before and after
   (sorted by name; `from` is null for an added, `to` null for a removed package; epochs kept, e.g.
   `2:2.16-1`). It is first written with state `running` just before pacman starts, and ends as
   `awaiting-verification` (both steps succeeded) or `failed` (a pacman step failed, the signal below,
   or `pacman -Q` failing afterwards; `error` says why).
6. **After a success:** `paccache -rk<cache-keep> -c <cache>` (a failure only warns), then
   `qs ipc call updates refresh` (best effort, 5 s timeout, skipped when `qs` is missing). As root the
   refresh runs as the invoking user (`setpriv --reuid=$PKEXEC_UID --regid=<gid> --init-groups env
   HOME=<user home> qs ...`, because pkexec sets `HOME=/root` and root cannot find the user's
   quickshell); root without `PKEXEC_UID` skips it, `qs` is never run as root. Then reboot,
   `verify`, `promote`; the last line names the installed `sudo /var/lib/shroomery/recovery/recovery.sh` for
   when the machine misbehaves.

At the start of apply (lock held) a sweep first RECOVERS rollback state a hard kill cut off, then
removes the debris: no `known-good` but a `known-good.old.*` (checkpoint_build cut off while
replacing it) puts the newest one back; a complete `known-good.prev.new.*` that differs from the
current known-good (cut off between the checkpoint and the `.prev` swap) becomes `known-good.prev`;
with no `.prev`, the newest `known-good.prev.old.*` comes back; each recovery prints a notice. Then
`<storage>/tmp/apply.*`, `known-good.tmp.*`, remaining `known-good.prev.new.*` and (once `known-good.prev` exists) `.old.*` and, once
`known-good` exists, `known-good.old.*` are deleted. The `.prev` swap itself ignores INT/TERM/HUP for
its two renames (`mv -T`, so a failed rename never nests one copy in the other). A failed restore keeps its source: the `known-good.prev.new.*` that could not be promoted, and any `known-good.prev.old.*` while `.prev` is missing, are kept with a warning naming them, and the next apply retries. The 64 MiB check is only the recovery
storage's own margin: pacman's `CheckSpace` covers the downloads, `fetch-missing` checks its own.

**Signals.** pacman soft-stops on INT and HUP (finishes the current package, releases `db.lck`) but
dies at once on TERM, leaving a half-extracted package and a stale `db.lck`; so apply never sends
TERM to pacman and apply itself never interrupts the `-Syu` transaction. A Ctrl-C or hang-up **in the
terminal** is another matter: it goes to the whole foreground process group, so it reaches pacman
directly, which then stops part way: a partial upgrade whose hooks (initramfs, GRUB, ...) did not run,
recorded as `failed`. Do not reboot then; run `recovery.sh` (or finish the update). That is why apply
prints "Installing — do not press Ctrl-C or close this terminal until it finishes." before `-Syu` when it
runs at a terminal. Signals to apply: before pacman starts
or after the final record, clean up and re-raise; during `-Syuw` (download only) INT is forwarded to
pacman (for any of the three signals), the record becomes `failed`; during `-Syu` the signal is only
remembered: apply waits for pacman, writes the record with the real outcome, skips `paccache` and
the refresh, cleans up, restores the caller's traps and re-raises the signal ("a closed tab does not
interrupt an update": closing the *terminal* sends HUP to the foreground process group, so pacman
itself soft-stops and the record says `failed`; the Settings UI runs apply without a terminal, where
nothing signals pacman). A signal that arrives before the check made right before `-Syu` is
forked stops there (`failed`, nothing installed); one arriving in the few instructions after that
check is remembered like any signal during `-Syu` and re-raised once pacman is done. SIGPIPE is ignored from the first trap on, i.e. from the moment the pending
record exists (the log's `tee` dies when a terminal closes); earlier, during the fetch or the
checkpoint, a dead log can still kill apply, but then no record exists and known-good is intact or
recovered by the next sweep. The record is written before anything is printed. Known-good is unchanged by an
interrupted apply; a SIGKILL or power loss leaves the `running` record, which gates the next apply
like any pending record. `discard` (root, same lock and log) ends the pending record without promoting
it: `pending/` is renamed to **`pending.discarded/`** (an older one is replaced; a `pending` that is not a
directory, e.g. a symlink, is just removed). Nothing else changes: the update stays installed and
known-good stays as it is; while `pending.discarded/` exists the next apply does not replace known-good
(step 3), and `recovery.sh` restores it. `promote` deletes `pending.discarded/`; the sweep leaves it alone.
With nothing pending discard says so and exits 0.

### Verify and promote

`pkg-update.sh verify` runs as the normal user (no root, no lock, no log, it changes nothing) and prints
one line per check, `PASS|FAIL|WARN|SKIP <check>[: detail]`, in this order; exit 1 when any check FAILs:

| Check | PASS when | Otherwise |
|-------|-----------|-----------|
| `kernel` | the running `uname -r` is the release of an installed kernel package (`linux`, `linux-lts`, `linux-zen`, `linux-hardened`, `linux-rt`, `linux-rt-lts`). Arch's `6.15.3.arch1-1` is the kernel's `6.15.3-arch1-1`, `6.16.arch1-1` is `6.16.0-arch1-1`, an epoch (`1:`) is ignored, the variants add their name (`linux-lts 6.12.30-1` = `6.12.30-1-lts`), every `.tag` of the version becomes `-tag` (`linux-rt 6.14.0.rt3.arch1-1` = `6.14.0-rt3-arch1-1-rt`); the whole string must match, pkgrel included | FAIL: the update has not been booted (names both). SKIP, exit 0: none of those packages is installed (a custom kernel: nothing to compare) |
| `gpu` | `nvidia-smi -L` lists a GPU (30 s limit), when any package named `nvidia*` is installed | FAIL (also when `nvidia-smi` is missing or hangs). SKIP when no `nvidia*` package is installed |
| `services` | `systemctl --failed --no-legend` lists nothing | FAIL naming the units; FAIL when systemctl cannot run |
| `journal` | `journalctl -b -p err` has no lines | WARN with the count (and WARN when the journal cannot be read). Never a FAIL: the messages are reported, not judged. Run as a normal user outside the `systemd-journal`/`wheel` groups, `verify` sees only the user's own journal, while `promote` (root) sees all of it, so the count can differ between the two (WARN only either way) |
| `network` | an IPv4 or IPv6 default route exists (`ip route show default`) | FAIL |

A check whose command cannot run is a FAIL (fail closed). Only stdout of `systemctl`, `ip`, `nvidia-smi` and
`journalctl` is parsed; stderr is kept apart and used only as the detail of a failure. Tests replace a whole check with
`PKG_VERIFY_<KERNEL|GPU|SERVICES|JOURNAL|NETWORK>=<command>` (exit 0 = PASS, else FAIL, its first output line is
the detail); these are never forwarded to the root process.

`pkg-update.sh promote [--force] [--yes]` (root, via `elevate`; takes the lock, exit 3 while an apply or another
promote runs; logs to `logs/`; `--yes` is accepted and ignored, promote never asks) makes the installed state the new
`known-good`. It is meant for after the reboot into an update. In this order:

1. **Sweep** (as apply does): a promote or apply that was cut off is recovered first.
2. **Verify** (the list is printed) and the **pending record** are checked. Promote REFUSES (exit 1, nothing changed,
   every reason printed) when any check FAILs; when `pending/` is `failed` (the update did not finish) or `running` (it
   was cut short), or its record is unreadable or has another state; or when `pending.replaced.state` is anything but
   `awaiting-verification` (an `apply --force` replaced an older pending record, `replaced` holds that record: if the
   older update had failed, the installed packages hold a half-done update). The way out is `pkg-update.sh discard`
   (known-good untouched) and a new apply, or `--force`. `awaiting-verification`, and no pending record at all (a manual
   `pacman -Syu`, an apply that changed nothing: "nothing to update" leaves none), are fine: with no record promote
   checkpoints the current verified state, which is how a plain `pacman -Syu` outside the tool gets a known-good.
   **`--force`** promotes anyway and prints, for every reason it overrides, `--force: promoting although: <reason>`
   (with an extra warning that the new known-good then holds a kernel this boot has not run when the `kernel` check
   FAILed). It overrides nothing else: a missing archive still fails. A forced promotion is recorded: the new
   `known-good/manifest.json` gets `"forced": true`, `"verified": false` and `"verify_failures": [<names of the failed checks>]` (empty
   when only the pending record was overridden), and `status` shows `known_good.forced` (`false` for every other
   known-good). A normal promotion records `"source": "promote"`, `"verified": true`. The record is written before anything is swapped; if it cannot be written nothing changes.
3. **Build** the new known-good with `checkpoint_build` (hardlinks to the cache, sha256, manifest) into
   `known-good.new.<pid>` next to the old one, then check that it is complete and still describes the installed set.
   A missing archive for an installed version (say `paccache` removed it, or it was never fetched) fails here: exit
   1, the old `known-good`, `pending/` and `known-good.prev` are unchanged; `pkg-update.sh fetch-missing` fills the gap.
4. **Swap** (with a durability barrier: the new tree, `manifest.json`, `archives/` and the directory, is `sync`ed
   before the old known-good is touched, and the filesystem is committed with `sync -f` after the renames and before
   the old copy is deleted, so a power loss cannot leave an empty new manifest and no old copy; a failing sync
   changes nothing, or undoes the swap): `known-good` is renamed to `known-good.old.<pid>`, then `known-good.new.<pid>` to `known-good` (the same
   names `checkpoint_build` uses, so the apply sweep understands them). A rename that fails puts the old one back. The
   two renames ignore INT/TERM/HUP; a hard kill (SIGKILL, power loss) between them leaves no `known-good` but
   `known-good.old.<pid>` and the untouched pending record, and the next apply's or promote's sweep renames it back:
   the machine is exactly as before the promote.
5. **Clean up**: `known-good.old.<pid>` (renamed to `known-good.discard.<pid>` first, which the sweep deletes and never
   restores), `pending/` and `pending.discarded/` are deleted. A normal promotion also deletes `known-good.prev` (a promoted, verified state
   supersedes the unverified one apply kept as `.prev`; the sweep never resurrects it). A **forced** promotion
   instead KEEPS the superseded known-good as `known-good.prev` (one generation, hardlinks, replacing any older
   `.prev`; made before the swap as `known-good.prev.new.<pid>` and moved into place by the same crash-safe steps
   apply uses, which the sweep finishes after a kill), so it never leaves zero verified rollbacks. `recovery.sh` is installed:
   `PKG_RECOVERY_SRC` or `scripts/recovery.sh` next to `pkg-lib.sh` is copied to `<storage>/recovery.sh`, mode 755, as a
   temp file and a rename (an older copy stays complete until the new one is). A missing source or a failing copy only
   WARNS and promote still exits 0: the known-good swap is what promote is for, and it has happened (the older
   `recovery.sh`, if any, stays). The sweep also deletes the debris a kill can leave (`known-good.new.*`,
   `known-good.discard.*`, `known-good.prev.discard.*`, `pending.discard.*`, `recovery.sh.tmp.*`).
6. The statusbar counter is refreshed (as after apply) and the last line is `known-good updated: <created>, kernel <ver>`.

Signals: INT, TERM and HUP before the swap remove `known-good.new.<pid>`, give the caller's traps back and re-raise
the signal (known-good was never touched); from the swap on they are remembered, the swap and the clean-up finish and
the signal is re-raised at the end. SIGPIPE is ignored from the start (the log's `tee` dies when a terminal closes).

### Recovery

`/var/lib/shroomery/recovery/recovery.sh` (installed by `apply` before pacman runs, and by `promote`; the repo copy is `scripts/recovery.sh`) puts the
protected packages back after a bad update. Run it as root from a TTY (`sudo /var/lib/shroomery/recovery/recovery.sh`);
not root, it re-executes itself through `sudo`. It needs only `bash`, `pacman`, `jq`, `sha256sum`, `flock` and, when
present, `gum`: it sources no other script and reads nothing under `$HOME` or `~/.config`, so a broken desktop or config
does not matter. Steps:

1. **Refuses while busy:** pacman's `db.lck` exists, or another `pkg-update.sh` run holds `<storage>/lock` (same lock
   file as `acquire_lock`): message, exit 3. A lock file it cannot open is only a warning.
2. **Recovery points:** `known-good`, `known-good.prev` ("previous recovery point") and `pending`. Each restore point is
   labelled by its provenance (see "Provenance" above), never by its name: `verified (promoted <date>)`, `checkpoint of
   the installed state <date>, NOT verified` (apply's checkpoint), or `promoted with --force <date>, NOT verified` (with
   the checks that failed on the line below). When `known-good.prev` is verified and `known-good` is not, `.prev` is
   listed first (so it is also the one `PKG_ASSUME_YES` takes). `pending` is shown with the packages the update changed,
   from -> to; choosing it restores the `known-good` archives (the state the update started from; the pending update
   itself has none). `pending.discarded/` is not a point. With no usable
   `known-good`, a `known-good.old.*` / `known-good.new.*` copy an interrupted promote or apply left is offered
   instead ("left by an interrupted update"). One point is taken without asking; several: a numbered prompt (`gum choose`
   when `gum` is installed and stdin is a terminal). No point at all: message, exit 1.
3. **Checksums:** every archive of the chosen point is checked against its manifest sha256 before anything is shown;
   a missing file or a mismatch is exit 1 and nothing is run.
4. **Table and question:** name, installed version, target version of every package whose version differs (a package
   no longer installed shows `(not installed)`), then `Reinstall these N package(s) with pacman -U? [y/N]` (`gum
   confirm` when available, else a plain prompt; anything but yes, or end of input, is no: exit 1, nothing changed).
   Everything already at the target version: "nothing to restore", exit 0, no pacman call.
5. **Restore:** one `pacman -U --noconfirm` over those archives (one transaction, so kernel, headers and driver move
   together), run with `LC_ALL=C`. Never `-dd`, never `--overwrite`. The protected set's closure (see above) keeps
   packages like `lib32-glibc` in the same transaction, so restoring glibc or systemd does not break an exact
   dependency. If it fails (a dependency conflict, say) pacman's message is shown, nothing else is run and the exit
   status is 1; the message says the transaction may be partly applied, not to reboot, and to run `recovery.sh` again.
   Then `mkinitcpio -P` and
   `grub-mkconfig -o /boot/grub/grub.cfg`; if one fails the packages are already restored, the message says which
   command to re-run by hand, and the exit status is 1. Finally it says to reboot (it never reboots itself) and, when
   a `pending/` record exists, to run `pkg-update.sh discard` afterwards (it blocks the next update; discard keeps it
   as `pending.discarded/` and leaves known-good as it is).
6. **Log:** the whole run, prompts included, is copied to `logs/<UTC time>-restore.log` (a log that cannot be written is a
   warning, never a reason to stop). Ctrl-C before `pacman -U` ends the run with nothing changed; from `pacman -U` on
   the script goes on (pacman handles the interrupt itself) and reports what failed.

Not part of it: best-effort restore of non-protected packages from the cache (the manifest's `installed` list is kept
for that, nothing reads it yet).

### Cache management

`pkg-update.sh cache ...` manages the pacman cache (`/var/cache/pacman/pkg`; `PKG_CACHE_DIR` in tests).

- `cache size` prints the bytes the package files take, one integer (the UI formats it). Package files are the
  regular files `*.pkg.tar.*` directly in the cache that are not `.sig` or `.part`; `download-*` directories (pacman's
  partial downloads), signatures and other files are not counted, and a file that known-good also links to is counted
  once, under its cache name. No root, no lock. No cache directory prints `0`; a directory that cannot be read is exit 1.
- `cache keep N` runs `paccache -rk<N> -c <cache>`, the same call `apply` makes after an update (`PKG_PACCACHE`
  in tests). N must be an integer from 1 to 20 in plain form: `0`, `21`, `abc`, an empty value, `3x`, `-1`, `+4`, `007`
  and `3 ` are all exit 2 with a usage message, before `pkexec` is started (no password prompt for a typo). It does not
  write the `cache-keep` setting: the UI owns that file. Exit 1 when `paccache` fails (or is not installed:
  `pacman-contrib`).
- `cache clear` removes every package file from the cache (what `pacman -Scc` does). Root, like `apply`.
  It is **not** `pacman -Scc --noconfirm`: `--noconfirm` answers each prompt with its default, and the default of
  "Do you want to remove ALL files from cache? [y/N]" is **N**, so that command exits 0 and removes nothing (checked
  with pacman 7.1 in a user namespace on a throwaway cache). So the answers are fed on pacman's stdin (`y` for every
  question, a here-string; pacman never reads the caller's stdin and never needs a terminal, and a missing answer
  is the default, never a wait). Two side effects of `-Scc` are accepted: it also asks to "remove unused
  repositories" and, answered `y`, deletes the sync databases of repositories that are no longer in `pacman.conf`
  (the configured ones stay), and it removes every file in the cache directory. Stale `download-*` directories are
  removed first, because pacman cannot (`Is a directory`, exit 255). The result is checked: package files left in
  the cache, or a failing pacman, is exit 1, so a silent no-op cannot look like a success.
- `keep` and `clear` take the update lock (exit 3 while another operation or pacman runs), log to `logs/`
  (`cache-keep`, `cache-clear`) and refresh the statusbar updates entry afterwards (best effort).

Known-good archives are hardlinks of cache files, so neither command can remove a protected archive: the cache's
name goes, the data stays reachable through `known-good/`. What they do remove are the best-effort rollback files for
every other package (older versions of firefox and the like), so downgrading those from the cache is no longer
possible; the UI warns before `clear`, and before a low `keep`, that older versions of the non-protected packages are
gone afterwards. `cache clear` also leaves `known-good` with link count 1 on those archives: they then take real
disk space that the cache used to share, so the cache size drops by less than the amount of the protected set.

### Elevation, lock and log

Root subcommands (`fetch-missing`, `apply`, `discard`, `promote`, `cache keep`, `cache clear`) start with
`elevate`: unless already root (or `PKG_NO_ELEVATE` is set) the script re-executes itself, by its
resolved real path, as `pkexec env WAYLAND_DISPLAY=… XDG_RUNTIME_DIR=… DISPLAY=… PKG_CACHE_KEEP=…
PKG_PROTECTED_PATTERNS=… PKG_USER_HOME=… <script> <subcommand> <args…>` (the same shape as the
launcher's run-as-root). Only those variables reach the root process (`pkexec` clears the
environment, `env` adds just the listed names), so no `PKG_*` test override can steer it. The
user's `cache-keep` (1..20, else 3) and `recovery-protected` settings are resolved before the
re-exec and passed as `PKG_CACHE_KEEP` and `PKG_PROTECTED_PATTERNS` (newline separated); the root
process never reads `$HOME`. Without `pkexec` it prints an error and exits 1, it never runs
unprivileged. After the re-exec there is no guarantee of a terminal for questions, so a UI always
passes `--yes`. Security note: the elevated script lives in the user's own home, so anything that
can write it can run as root once the user authenticates; this is inherent to the design and the
polkit prompt.

`acquire_lock` takes `flock -n` on `<storage>/lock` (fd 200, released when the process exits, also
when killed; `pkg_pacman` and the log's `tee` close it so a background child of pacman cannot
keep it) and exits 3 with a message when another update holds it or pacman's
`/var/lib/pacman/db.lck` exists. `log_start NAME` prints `LOG=<path>` as the first stdout line, then
copies stdout and stderr (still separate) into `logs/<UTC time>-NAME.log` (755/644); an EXIT trap
flushes it before the script ends, so the UI can follow the file.

### First run

`SUPER+U` and the statusbar update button open Settings -> Update (`install-updates.sh`); the old terminal update
script (with dnf support) is gone. AUR and flatpak updates are not part of the safe flow: run
`yay -Sua` and `flatpak update` yourself after a safe update.

Before trusting the tool, walk through this once with a terminal open (it touches the real system, so do it
yourself, not from a script; every step shows what it will do first):

1. `~/.config/shroomery/scripts/pkg-update.sh status` -- expect JSON with `known_good: null`, `pending: null`,
   `matches: false` on a machine that never ran the tool.
2. `~/.config/shroomery/scripts/pkg-update.sh fetch-missing` -- the polkit prompt comes first (the script
   re-executes itself as root), then it lists the protected packages whose archives the pacman cache lacks and asks
   `y/N`; on `y` it downloads them from the Arch Linux Archive and verifies each signature. When the cache has
   them all it says "nothing missing: every protected package has an archive in the cache". Answer `n` to the list
   to download nothing (on the machine this was written on `linux`, `linux-headers`, `nvidia-open`, `nvidia-utils`
   and `mkinitcpio-busybox` were missing from the cache).
3. `~/.config/shroomery/scripts/pkg-update.sh apply` -- polkit prompt, then a log under
   `/var/lib/shroomery/recovery/logs/`. On the first run it builds the first known-good (an unverified checkpoint,
   `verified: false` in `status`) and installs `/var/lib/shroomery/recovery/recovery.sh`, and only then calls pacman.
   If archives are still missing (you answered `n` in step 2) it lists them again and asks its own **"Download N
   archive(s)? [y/N]"**: `y` fetches them as in step 2; `n` makes apply refuse at the checkpoint ("no checkpoint
   without these archives; nothing was changed", exit 1: no known-good, no pending record, pacman not called).
   A system that is already up to date gets no pacman prompt and ends with "nothing to update: no package changed,
   no pending record kept" (known-good is built, nothing to verify). Run from a terminal without `--yes`, the first
   pacman call is `-Syuw` and it asks **"Proceed with download?"**, not an install question; the install prompt
   ("Proceed with installation?" of `-Syu`) only comes after you answered `y` to the download, and the package
   databases are already synced at that point. To look without updating, answer `n` to the download prompt. Be
   aware of what that leaves:
   - known-good is already built (check with `pkg-update.sh status`: `known_good` is no longer `null`);
   - pacman exits non-zero, so `pending/` is left with state `failed` (nothing was downloaded or installed) and the
     next `apply` exits 4 until you run `~/.config/shroomery/scripts/pkg-update.sh discard` (polkit prompt; known-good
     stays; the record is kept as `pending.discarded/` until the next promote, and while it is there apply does not
     replace known-good, even after a `pacman -Syu` outside the tool);
   - `-Syuw` has synced the real package databases: until the system is fully updated, do not install a single
     package with `pacman -S` (a partial upgrade).
   Continue only when you accept a real update: answer `y` to the download, and `n` at the install prompt is
   the second place to stop (that leaves a `failed` pending record too, with packages downloaded but not installed;
   `discard` it). Once the install runs, apply prints "Installing — do not press Ctrl-C or close this terminal
   until it finishes.": a Ctrl-C or a closed terminal reaches pacman, which stops part way (a partial upgrade whose
   hooks did not run; the record says `failed` and apply says "packages were partly changed — do not reboot").
   Then do not reboot: run `sudo /var/lib/shroomery/recovery/recovery.sh`, or finish the update (`discard`, then
   `apply`).
4. After an update you approved, reboot, then `pkg-update.sh verify` (expect a `PASS` line per check; `FAIL kernel`
   if you did not reboot into the new kernel), then `pkg-update.sh promote` (it verifies again, makes known-good
   `verified: true` and installs `/var/lib/shroomery/recovery/recovery.sh` again).
5. `sudo /var/lib/shroomery/recovery/recovery.sh` (installed by step 3 once apply got past the checkpoint; it is the
   one to run from a TTY. If step 3 refused at the checkpoint there is no known-good either, and nothing to restore;
   the repo copy `sudo ~/.config/shroomery/scripts/recovery.sh` behaves the same, it reads the recovery storage,
   not its own location) -- the known-good is labelled `checkpoint of the installed state <date>, NOT verified`
   before the first promote and `verified (promoted <date>)` after it. It lists the
   recovery points, checks every archive's sha256 and compares with the installed versions; it also writes a log
   to `logs/` and takes the update lock, nothing else. When everything is already at the recovery point's versions
   (the case right after step 3) it says there is nothing to restore; otherwise it asks "Reinstall these N
   package(s) with pacman -U?" -- answer `n` unless you really want to restore.

The Update tab does the same steps with buttons; its output log follows the same `logs/` files.

Out of scope (documented only, kept so it can be picked up):

- **Level 2: recovery that survives a broken kernel.** Possible on the same disk.
  Cheapest version: install `linux-lts` plus its matching driver; GRUB lists it
  automatically and it boots the same root, covering a bad kernel or GPU driver
  (not a broken glibc or root filesystem). A fully separate recovery environment
  (own kernel, initramfs, tools and archives, with its own GRUB entry) is more
  work and has to be maintained and tested.
- **Level 3: Arch installation USB.** Always the last resort; keep one.
- **Automatic failure detection / rollback.** After manual recovery is proven: a
  service records the update and checks health after reboot. It must tell apart
  kernel panic (may never run), broken GPU driver (system up, display unusable),
  an unrelated failed service, and power loss mid-update. A kernel panic needs an
  independent mechanism, such as a bootloader boot-attempt counter or a watchdog.
  Add safeguards against restoring the same broken state repeatedly.
- **GRUB recovery entries.** An "Arch Recovery" entry booting the installed system
  with `systemd.unit=multi-user.target nomodeset` to reach a TTY and run
  `recovery.sh`, plus the Level 2 entry above.
- **AUR and flatpak** are not part of the safe flow (repo packages only).
- **Btrfs note.** The planned new PC will probably use Btrfs; then native
  snapshots (e.g. snapper or timeshift with grub-btrfs) can replace the archive
  layer: snapshot before the update, boot a snapshot from GRUB. The
  update/verify/promote flow and the Update tab stay, only the checkpoint and
  restore backends change, so keep those two behind small functions.

## Generated files

| File | Produced by | Consumed by |
|------|-------------|-------------|
| `colors/colors.json` | matugen, template `[templates.colorsjson]` in `~/.config/matugen/config.toml` (input `~/.config/matugen/templates/colors.json`): Material color roles as `"name": "#rrggbb"` | `quickshell/shared/Theme.qml` |
| `$XDG_RUNTIME_DIR/shroomery/screen-colors.sock`, `screen-colors.lock` | `screen-colors.py` — protocol socket and single-instance lock | quickshell VisualizerApp |
| `$XDG_RUNTIME_DIR/shroomery/visualizer-active` | quickshell VisualizerApp — exists while visualizer mode is on | `hypr/keybindings.lua` (Super+arrows, Super+Esc) |
| `$XDG_RUNTIME_DIR/shroomery/cava-<bars>-<fps>.conf` | quickshell `shared/CavaSpectrum.qml` | `cava` |
| `~/.cache/shroomery/wallpaper-colors` | `wallpaper.sh` — the wallpaper's top 3 candidate source colors, one `#rrggbb` per line | SettingsApp accent picker |
| `~/.cache/shroomery/current_wallpaper` | `wallpaper.sh` — absolute path of the original image | WallpaperApp (highlights current), `screen-colors.py` (fallback wallpaper base), `apply-theme.sh`, `autostart.sh` |
| `~/.cache/shroomery/displayed_wallpaper` | `wallpaper.sh` — what is actually shown (the effect copy, the original, or the video); `animated-wallpaper.sh` points it at the paused still while paused | `screen-colors.py` (wallpaper base) |
| `~/.cache/shroomery/still_wallpaper` | `wallpaper.sh` — path of a still of the wallpaper (the image, or the animated one's first frame) | quickshell WallpaperApp (current preview), VisualizerApp (mini screen) |
| `~/.cache/shroomery/frames/<md5 of path>.png` | `lib.sh video_frame` — an animated wallpaper's first frame | matugen, the blurred/square variants, `animated-wallpaper.sh` (still while paused) |
| `~/.cache/shroomery/animated-wallpaper` | `animated-wallpaper.sh` — `OUTPUT<TAB>FILE<TAB>SECONDS` per mpvpaper that should play | `animated-wallpaper.sh`, `autostart.sh` |
| `$XDG_RUNTIME_DIR/shroomery/mpvpaper/` | `animated-wallpaper.sh` — `OUTPUT.pid`, `OUTPUT.sock` (mpv IPC), `paused-OUTPUT.png` (still while paused), `lock` | `animated-wallpaper.sh`, `screen-colors.py` (video position) |
| `~/.cache/shroomery/blurred_wallpaper.png` | `wallpaper.sh` | `hypr/hyprlock.conf`, wlogout themes, quickshell LauncherApp (backdrop) |
| `~/.cache/shroomery/square_wallpaper.png` | `wallpaper.sh` | `hypr/hyprlock.conf` |
| `~/.cache/shroomery/<effect>-<image>` | `wallpaper.sh` (effect copies) | `awww`, matugen |
| `~/.cache/shroomery/weather.json` | quickshell DashboardPanel — last wttr.in answer, refetched after 30 min | DashboardPanel |
| `~/.cache/shroomery/thumbnails/<md5 of folder>/<md5>.jpg` | `wallpaper-thumbnails.sh` — key is md5 of `<file name>:<size in bytes>` | WallpaperApp grid |
| `~/.cache/shroomery/sun-times` | `hyprsunset.sh sun-times` — `YYYY-MM-DD SUNRISE SUNSET` | `hyprsunset.sh` |
| `$XDG_RUNTIME_DIR/shroomery/sun-times-attempt` | `hyprsunset.sh` — time of the last wttr.in try | `hyprsunset.sh` |

matugen also writes other apps' colors in the same run (kitty, gtk, qt, swaync,
OverviewApp's `common/Appearance.colors.qml`, …) — see `~/.config/matugen/config.toml`.

## Theme flow

```
wallpaper.sh IMAGE ──► awww img ──► matugen image ──► colors/colors.json + other templates
wallpaper.sh VIDEO ──► animated-wallpaper.sh start (mpvpaper) ─► matugen on its first frame
                                         │
apply-theme.sh --color ─► matugen color ─┤   (both use -t settings/accent-scheme)
                                         ▼
                      reload: qs ipc call theme-manager reload, waybar (if running),
                              swaync-client -rs, pywalfox (if installed)

toggle-theme.sh ─► gtk settings.ini ─► listeners/gtk-theme.sh ─► apply-theme.sh --reapply
```

## Requirements

`awww`/`awww-daemon`, `matugen`, ImageMagick (`magick`), `qs` (Quickshell),
`mpvpaper` + `ffmpeg` (animated wallpapers, `python3` for mpv IPC, `udevadm` for the power listener),
`hyprctl`, `hyprlock`, `notify-send`, `inotifywait` (inotify-tools),
`gum`, `figlet` (optional), `yay` or `paru` + `checkupdates` (pacman-contrib),
`flatpak` (optional), `swaync-client`, `flock`.
Notifications: Quickshell is the notification daemon; swaync's systemd user unit is masked
(`systemctl --user mask swaync.service`) so D-Bus can't start it first — `unmask` to go back.
`ocr.sh`: `grim`, `slurp`, `hyprpicker`, `tesseract` + a `tesseract-data-*` language.
`lid-switch.sh`: `busctl`, `pkexec` + a polkit agent.
`conservation-mode.sh`: `pkexec` + a polkit agent.
`screen-colors.py`: `python3` + `numpy`, `grim` (with `-T`), `magick`, `hyprctl`, `ffmpeg` (animated wallpaper; CUDA decode when available).
`hyprsunset.sh`: `hyprsunset`, `jq`, `curl`. `pkg-update.sh`: `jq`, `pacman`, `fakeroot` and `flock` (the update check; `fakeroot` is also a `checkupdates` dependency), and for `fetch-missing` `curl`, `bsdtar` (libarchive), `gpg` and `numfmt`/`stat` (coreutils) and `pkexec` (polkit; root subcommands); `apply` also `paccache` (`pacman-contrib`), `timeout`, and for the statusbar refresh `qs` and `setpriv` (util-linux). `screenshot.sh`: `grim`, `slurp`, `jq`, `wl-copy`.
`finder.sh`, `apps.sh`, `quicklinks.sh`: `fzf`. `ascii-header.sh`: `figlet`, `wl-copy`.
Optional: `hyprshutdown`, `pywalfox`.
