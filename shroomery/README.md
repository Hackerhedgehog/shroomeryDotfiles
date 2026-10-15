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
├── tests/            bash tests for lib.sh helpers (bash tests/night-light.sh)
├── colors/           matugen output
└── effects/          wallpaper effects, one ImageMagick snippet per file (sourced by wallpaper.sh)
~/.cache/shroomery/   generated wallpaper files (safe to delete, see clear-wallpaper-cache.sh)
$XDG_RUNTIME_DIR/shroomery/  runtime state, gone after a reboot (lib.sh SHROOMERY_RUNTIME)
```

## Scripts

| Script | What it does | Called by |
|--------|--------------|-----------|
| `scripts/autostart.sh` | Session start: creates the cache, starts `nm-applet`, `qs` and the OverviewApp instance, restores the wallpaper + theme. Logs to `~/.cache/shroomery/autostart.log`. | `hypr/autostart.lua` |
| `scripts/wallpaper.sh [IMAGE] [opts]` | Applies the wallpaper effect, sets the image with `awww` (a video or GIF instead goes to `animated-wallpaper.sh start`, without effect; theming and the variants then use its first frame, `~/.cache/shroomery/frames/`), runs `matugen` on it (seeded by the accent settings: the chosen one of the image's colors, or the fixed accent color; also writes `~/.cache/shroomery/wallpaper-colors`), reloads theme consumers, then renders the blurred/square copies in the background (exits without waiting for them). `--random [DIR]`, `--skip-wallpaper`, `--skip-theming`, `--monitor`, `--crop-gravity`. | WallpaperApp, `autostart.sh`, `apply-theme.sh`, keybind |
| `scripts/animated-wallpaper.sh` | Animated wallpapers with `mpvpaper` (`no-audio loop hwdec=auto profile=fast panscan=1.0`, `-p -a FULL`: pauses itself while hidden or a window is fullscreen) above awww's still. `start FILE [OUTPUT]` (default `ALL`; one monitor out of an `ALL` one splits it into one mpvpaper per remaining monitor), `stop [OUTPUT]`, `pause` (awww gets a still of the frame on screen via mpv IPC `screenshot-to-file`, then mpvpaper stops), `resume` (from where it paused), `sync` (pause on battery or in gamemode, else resume), `status`. What plays is kept in `~/.cache/shroomery/animated-wallpaper`. | `wallpaper.sh`, `autostart.sh`, `listeners/animated-wallpaper.sh`, `hypr/scripts/gamemode.sh` |
| `scripts/screen-colors.py` | Screen color sampler daemon (protocol v2): per monitor it rebuilds a small picture of the screen (wallpaper — an animated one decoded by `ffmpeg` in step with mpv — + visible windows via `grim -T`, piped, never written to disk) and each client subscribes to its own monitor, source (screen / wallpaper) and regions (ring, edges, rectangles); smoothed colors on `$XDG_RUNTIME_DIR/shroomery/screen-colors.sock` (protocol in `screencolors/README.md`). One copy at a time; exits 5 s after its last client. `--rate`, `--idle-exit`, `--pattern` (test picture), `--watch [--monitor M] [--subscribe JSON\|@file]`. | quickshell VisualizerApp overlay + setup preview (later: the LED bridge) |
| `scripts/apply-theme.sh` | `--color '#rrggbb'` palette from a fixed accent, `--wallpaper [N]` palette from the current wallpaper's Nth color (0 = most dominant), `--scheme TYPE` switches the matugen scheme type, `--reapply` re-applies whatever is recorded. Records each choice in `settings/accent`, `accent-index`, `accent-scheme` once matugen succeeded. | SettingsApp accent picker, `toggle-theme.sh`, `listeners/gtk-theme.sh` |
| `scripts/toggle-theme.sh` | Flips GTK dark/light in `gtk-3.0`/`gtk-4.0` `settings.ini`. Re-themes itself only if the gtk-theme listener isn't running. | SettingsApp, `SUPER+SHIFT+M` |
| `scripts/power.sh -l\|-s\|-e\|-r\|-p` | Lock (hyprlock), suspend, logout, reboot, power off. Uses `hyprshutdown` when installed. | PowerApp, `hypr/autostart.lua` (lock on login), `SUPER+L` |
| `scripts/check-updates.sh` | Prints pending update count as JSON (`text`, `class` green/yellow/red); prints nothing at 0. Runs serialized via `flock`. | StatusbarApp UpdatesModule |
| `scripts/install-updates.sh` | Opens the terminal (`--class dotfiles-floating`) running `system-update.sh`. | StatusbarApp UpdatesModule, `SUPER+U` |
| `scripts/system-update.sh` | Interactive `gum` confirm, then `yay`/`paru` (or `dnf`), `flatpak update`, refreshes the statusbar counter. | `install-updates.sh` |
| `scripts/terminal.sh [args]` | Launches the terminal named in `settings/terminal`. | StatusbarApp TerminalModule |
| `scripts/ocr.sh [--lang CODE]` | Freezes the screen (`hyprpicker -z`), lets you drag a region (`slurp`), prints the text `tesseract` reads in it (`grim` → `magick` cleanup → `tesseract`). Exit 1 = selection cancelled or timed out, 2 = missing dependency, 3 = capture/OCR failed. `--list-langs` lists installed tesseract languages (without `osd`/`equ`). Language defaults to `settings/ocr-language`. | quickshell OcrApp (`SUPER+ALT+A`) |
| `scripts/lid-switch.sh status\|set KEY [ACTION]` | What closing the lid does. `status` prints `present=true\|false`, the `HandleLidSwitch` / `HandleLidSwitchExternalPower` values logind uses now (`""` = not set) and logind's `CanHibernate` / `CanHybridSleep` / `CanSuspendThenHibernate`. `set` re-runs itself through `pkexec`, writes the key in the `[Login]` section of `/etc/systemd/logind.conf` (no ACTION = comment it out) and runs `systemctl reload systemd-logind`. Exit 1 = bad arguments, 2 = password prompt dismissed, 3 = write failed. | quickshell PerformanceApp (battery panel) |
| `scripts/editor.sh FILE` | Opens a file in the editor named in `settings/editor`. | SettingsApp "Edit Settings" |
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
| `terminal` | Terminal command | `kitty` | `terminal.sh`, `install-updates.sh`, `hypr/scripts/gtk.sh` | — |
| `editor` | Editor command | `gnome-text-editor` | `editor.sh` | — |
| `launcher` | `quickshell` or `walker` | `quickshell` | `hypr/scripts/launcher.sh` (statusbar launcher button, `SUPER+E`) | — |
| `gamemode-enabled` | Flag file: exists = gamemode on | absent | SettingsApp, `hypr/scripts/gamemode.sh`, `hypr/hyprland.lua` (re-applies it on every config load) | `hypr/scripts/gamemode.sh` |
| `hide-fastfetch` | Flag file: exists = no fastfetch in new terminals | absent | `bashrc`/`zshrc` `30-autostart` | SettingsApp |
| `launcher-view.json` | JSON `{ "appsGrid": bool, "emojiGrid": bool }` — launcher apps/emoji tabs as grid or list | apps list, emoji grid | quickshell LauncherApp | SettingsApp ("Grid Apps", "Grid Emojis") |
| `ocr-language` | tesseract language code for OCR captures (`eng`, `est`, …) | `eng` | `ocr.sh`, quickshell OcrApp | OcrApp |
| `weather-location` | Place for the dashboard's weather, anything wttr.in understands (`Tallinn`, `59.43,24.75`, an airport code) | empty = located by IP | quickshell DashboardApp, `hyprsunset.sh` (sun times) | — |
| `night-light.json` | `{ "mode": "off"\|"fixed"\|"sun", "on": "HH:MM", "off": "HH:MM", "temperature": 2500–6500, "gamma": 50–100 }`. `sun` = on at sunset, off at sunrise (fixed times when unknown). Bad values: default or clamped | mode off, 21:00, 07:00, 4500, 100 | `hyprsunset.sh`, `listeners/night-light.sh`, quickshell SettingsApp | quickshell SettingsApp |

## Generated files

| File | Produced by | Consumed by |
|------|-------------|-------------|
| `colors/colors.json` | matugen, template `[templates.colorsjson]` in `~/.config/matugen/config.toml` (input `~/.config/matugen/templates/colors.json`): Material color roles as `"name": "#rrggbb"` | `quickshell/shared/Theme.qml`, `system-update.sh` |
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
| `~/.cache/shroomery/weather.json` | quickshell DashboardApp — last wttr.in answer, refetched after 30 min | DashboardApp |
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
`flatpak` (optional), `nm-applet`, `swaync-client`, `flock`.
Notifications: Quickshell is the notification daemon; swaync's systemd user unit is masked
(`systemctl --user mask swaync.service`) so D-Bus can't start it first — `unmask` to go back.
`ocr.sh`: `grim`, `slurp`, `hyprpicker`, `tesseract` + a `tesseract-data-*` language.
`lid-switch.sh`: `busctl`, `pkexec` + a polkit agent.
`screen-colors.py`: `python3` + `numpy`, `grim` (with `-T`), `magick`, `hyprctl`, `ffmpeg` (animated wallpaper; CUDA decode when available).
`hyprsunset.sh`: `hyprsunset`, `jq`, `curl`. `screenshot.sh`: `grim`, `slurp`, `jq`, `wl-copy`.
`finder.sh`, `apps.sh`, `quicklinks.sh`: `fzf`. `ascii-header.sh`: `figlet`, `wl-copy`.
Optional: `hyprshutdown`, `pywalfox`.
