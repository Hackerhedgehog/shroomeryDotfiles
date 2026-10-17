# shroomeryDotfiles

A personal Arch Linux + Hyprland desktop, split in three parts that each own one
job. This file is the map; every part has its own README with the details.

| Part | Job | Details |
|------|-----|---------|
| [`hypr/`](hypr/) | The compositor: Hyprland (Lua config), hypridle, hyprlock, hyprpaper, and the small helper scripts keybinds call | the files themselves (`hyprland.lua` includes the rest) |
| [`quickshell/`](quickshell/) | Everything you see: status bar, dock, launcher, notifications, and every panel/app | [`quickshell/README.md`](quickshell/README.md) |
| [`shroomery/`](shroomery/) | Everything behind the scenes: wallpaper and theme scripts, background listeners, user settings, the generated palette | [`shroomery/README.md`](shroomery/README.md), [`shroomery/screencolors/README.md`](shroomery/screencolors/README.md) |

Rule of thumb: if it draws UI it goes in `quickshell`; if it is a script, a
setting or generated data it goes in `shroomery`; if it configures Hyprland
itself it goes in `hypr`. [`CLAUDE.md`](CLAUDE.md) has the working conventions
(for Claude and for me).

## Install layout

The repo lives at `~/shroomeryDotfiles`. Each part is symlinked into
`~/.config`, and all code and docs use the `~/.config/...` paths:

```
~/.config/hypr       -> ~/shroomeryDotfiles/hypr
~/.config/quickshell -> ~/shroomeryDotfiles/quickshell
~/.config/shroomery  -> ~/shroomeryDotfiles/shroomery
```

Other places the system touches (none are in the repo):

- `~/.cache/shroomery/` — generated wallpaper variants, weather cache, logs (safe to delete)
- `$XDG_RUNTIME_DIR/shroomery/` — runtime state (sockets, flags); gone after reboot
- `~/.config/matugen/` — matugen config and templates that write the palette files

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
portals, the polkit agent and hypridle, then runs
`shroomery/listeners.sh --startall` (background watchers) and
`shroomery/scripts/autostart.sh`. That script starts `qs` (the Quickshell
shell) plus the separate OverviewApp instance, and restores the last wallpaper
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
| add or change a panel/app | `quickshell/<Name>Panel/` (bar popout) or `quickshell/<Name>App/` (window), shared widgets in `quickshell/shared/ui/` |
| add a new external path or command a UI uses | `quickshell/shared/Paths.qml`, then update `quickshell/README.md` |
| change wallpaper/theme behavior | `shroomery/scripts/wallpaper.sh`, `apply-theme.sh`, `shroomery/effects/` |
| add a background watcher | `shroomery/listeners/` + `listeners.sh` |
| find a design spec or plan | `quickshell/docs/superpowers/` |
