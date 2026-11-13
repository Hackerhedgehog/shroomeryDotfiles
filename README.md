# shroomeryDotfiles

A personal Arch Linux + Hyprland desktop, split in three parts that each own one
job. This file is the map; every part has its own README with the details.

| Part | Job | Details |
|------|-----|---------|
| [`hypr/`](hypr/) | The compositor: Hyprland (Lua config), hypridle, hyprlock, hyprpaper, and the small helper scripts keybinds call | the files themselves (`hyprland.lua` includes the rest) |
| [`quickshell/`](quickshell/) | Everything you see: status bar, dock, launcher, notifications, and every panel/app | [`quickshell/README.md`](quickshell/README.md) |
| [`shroomery/`](shroomery/) | Everything behind the scenes: wallpaper and theme scripts, background listeners, user settings, the generated palette | [`shroomery/README.md`](shroomery/README.md), [`shroomery/screencolors/README.md`](shroomery/screencolors/README.md) |
| [`matugen/`](matugen/) | matugen config + templates: turn the wallpaper into palette files for Quickshell, Hyprland, GTK, Qt, kitty, btop | `matugen/config.toml` |
| [`install/`](install/) | The installer's steps and package lists (`install.sh` runs them) | [Install](#install) below |

Rule of thumb: if it draws UI it goes in `quickshell`; if it is a script, a
setting or generated data it goes in `shroomery`; if it configures Hyprland
itself it goes in `hypr`. [`CLAUDE.md`](CLAUDE.md) has the working conventions
(for Claude and for me).

## Install

On a fresh Arch Linux (base system, a user account, network and `git`):

```bash
git clone <this repo> ~/.config/shroomeryDotfiles
~/.config/shroomeryDotfiles/install.sh
```

Run it as your normal user; it asks for the sudo password in the terminal (on
a system without sudo it offers to set it up with the root password). Then
reboot and pick the Hyprland session. The repo can live anywhere — the links
point at wherever it was cloned.

`install.sh` runs the scripts in `install/steps/` in order:

| Step | Does |
|------|------|
| `preflight` | Arch? internet? not root? sudo works (asks the password once) |
| `packages` | `pacman -Syu` the missing packages of `install/packages/pacman.txt`, builds `yay-bin` if no AUR helper is there, then `install/packages/aur.txt` |
| `gpu` | Mesa + Vulkan for AMD/Intel; for NVIDIA asks, then `nvidia-open-dkms` (+ kernel headers) and the NVIDIA env in `hypr/custom.lua` (git-ignored) |
| `link` | Symlinks `hypr`, `quickshell`, `shroomery`, `matugen` into `~/.config`; anything already there is moved to `<name>.bak-<date>` |
| `config` | Writes GTK 3/4, qt5ct/qt6ct, kitty and cursor configs **only when missing**, paints `WallpaperApp/wallpapers/default.jpg` when there are no wallpapers, and (asked; default yes on a first install) resets the per-machine settings in the repo: `hypr/monitors.lua` to one auto rule, the keyboard layout (`settings/input.json` + `hypr/input.lua`), the visualizer monitor and Hyprland's locale |
| `services` | Enables NetworkManager (offers to turn off systemd-networkd/dhcpcd/iwd, effective after the reboot), bluetooth, power-profiles-daemon, and SDDM when no login manager is enabled |
| `finish` | Next steps and the main keybinds |

Options: `-y`/`--yes` (take every default), `-n`/`--dry-run` (print, change
nothing), `--only STEP,…`, `--skip STEP,…`, `--list`. Every step is safe to
run again. When a script starts using a new program, add its package to
`install/packages/pacman.txt` (or `aur.txt`); `bash install/tests/deps.sh`
checks that every program, QML module and Python module the code uses comes
from a listed package (or a dependency of one, or `base`).

Wallpapers aren't in git: put images in `~/.config/quickshell/WallpaperApp/wallpapers/`
(videos/GIFs in its `animated/`).

## Install layout

On this machine the repo lives at `~/shroomeryDotfiles` (`install.sh` works
from any clone location). Each part is symlinked into `~/.config`, and all
code and docs use the `~/.config/...` paths:

```
~/.config/hypr       -> ~/shroomeryDotfiles/hypr
~/.config/quickshell -> ~/shroomeryDotfiles/quickshell
~/.config/shroomery  -> ~/shroomeryDotfiles/shroomery
~/.config/matugen    -> ~/shroomeryDotfiles/matugen
```

Other places the system touches (none are in the repo):

- `~/.cache/shroomery/` — generated wallpaper variants, weather cache, logs (safe to delete)
- `$XDG_RUNTIME_DIR/shroomery/` — runtime state (sockets, flags); gone after reboot
- matugen's outputs outside the repo: `~/.config/kitty/colors-matugen.conf`, `~/.config/gtk-{3,4}.0/colors.css`,
  `~/.config/qt{5,6}ct/colors/matugen.conf`, `~/.config/btop/themes/matugen.theme`, `~/.cache/wal/`

## How it fits together

```
                     ┌──────────────┐
   keybinds, idle ──▶│     hypr     │── hyprland.start ──┐
                     └──────┬───────┘                    │
          keybind calls     │ calls scripts              ▼
   quickshell/*/toggle.sh   │                 shroomery/listeners.sh
                            │                 shroomery/scripts/autostart.sh
                            ▼                            │ starts `qs`, restores wallpaper
                     ┌──────────────┐                    ▼
  user actions ─────▶│  quickshell  │◀── colors.json ── matugen ◀── wallpaper.sh
  (clicks, IPC)      │  (one `qs`)  │── runs scripts, writes settings ──▶ shroomery
                     └──────────────┘
```

**Startup.** Hyprland fires `hyprland.start` → `hypr/autostart.lua` starts the
portals and hypridle, then runs
`shroomery/listeners.sh --startall` (background watchers) and
`shroomery/scripts/autostart.sh`. That script starts `qs` (the Quickshell
shell, which is also the polkit agent: `quickshell/PolkitApp`) plus the separate OverviewApp instance, and restores the last wallpaper
and its theme.

**Keybinds → UI.** `hypr/keybindings.lua` binds keys either to Hyprland
dispatchers, to `hypr/scripts/*.sh` helpers, or to a
`quickshell/<Name>App/toggle.sh` (or `<Name>Panel/`). Those talk to the running `qs` over IPC to
show or hide a panel. The KeybindsApp edits `keybindings.lua` back, so the
file is both config and data.

**Wallpaper → theme → UI.** Choosing a wallpaper (WallpaperApp or
`shroomery/scripts/wallpaper.sh`) applies effects, sets it (awww, or mpvpaper
for animated ones), and runs matugen. matugen writes
`shroomery/colors/colors.json` (plus GTK/other templates), then
`qs ipc call theme-manager reload` makes `quickshell/shared/Theme.qml`
re-read it. Every app takes its colors from `Theme`, so the whole desktop
re-themes at once. The GTK dark/light listener and the accent settings feed
the same pipeline.

**Settings.** UI state that must survive a restart (bar, dock, launcher view,
night light, visualizer, …) is stored as plain files in `shroomery/settings/`.
QML reads and writes them through `quickshell/shared/Paths.qml`; shell scripts
use the same paths via `shroomery/lib.sh`. The two files mirror each other —
change both together.

**Screen colors / visualizer.** `shroomery/scripts/screen-colors.py` is a
sampler daemon that publishes smoothed screen/wallpaper colors on a socket;
quickshell's VisualizerApp subscribes to it (protocol in
`shroomery/screencolors/README.md`).

**Background work.** `shroomery/listeners/` holds the watchers: GTK theme
changes, low battery, AC plug (pause/resume animated wallpaper) and the night
light schedule.

## Where to look when…

| I want to… | Go to |
|------------|-------|
| change a keybind or window rule | `hypr/keybindings.lua`, `hypr/windowrules.lua` (or the KeybindsApp) |
| change monitors, idle/lock behavior | `hypr/monitors.lua`, `hypr/hypridle.conf`, `hypr/hyprlock.conf` |
| change picture-in-picture (Ctrl+Super+V, a pinned see-through window in a corner above fullscreen games) | `hypr/pip.lua` (Hyprland calls), `hypr/piplogic.lua` (geometry, tested by `lua ~/.config/hypr/tests/piplogic.lua`) |
| change where Unity Editor's floating windows open (under the cursor, held there for 2 s; tooltips/menus only kept on screen) and the asset picker focus fix | `hypr/unity.lua` (rules, placement, follow_mouse switch), `hypr/unitylogic.lua` (geometry, tested by `lua ~/.config/hypr/tests/unitylogic.lua`) |
| add or change a panel/app | `quickshell/<Name>Panel/` (bar popout) or `quickshell/<Name>App/` (window), shared widgets in `quickshell/shared/ui/` |
| add a new external path or command a UI uses | `quickshell/shared/Paths.qml`, then update `quickshell/README.md` |
| change wallpaper/theme behavior | `shroomery/scripts/wallpaper.sh`, `apply-theme.sh`, `shroomery/effects/` |
| add a background watcher | `shroomery/listeners/` + `listeners.sh` |
| find a design spec or plan | `quickshell/docs/superpowers/` |
