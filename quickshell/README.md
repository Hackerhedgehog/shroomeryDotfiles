# quickshell

Quickshell UI apps for a Hyprland desktop. Every app lives in the one running
`qs` shell (except OverviewApp) and is shown or hidden over IPC with its own
`toggle.sh`:

```bash
~/.config/quickshell/AudioPanel/toggle.sh            # toggle
~/.config/quickshell/AudioPanel/toggle.sh open|close|status
```

Scripts, theme sync and settings live in `~/.config/shroomery`. Colors come
from matugen (`shroomery/colors/colors.json`) and follow one of the
wallpaper's top 3 colors or a fixed accent, built with a chosen scheme type.

## Apps and panels

`-Panel` directories hold a popout the status bar grows into; `-App` directories hold an app window (or, for the bar, dock and visualizer, something that isn't a popout).

| Panel | What it does |
|-------|--------------|
| **AudioPanel** | Output/input devices, per-app mixer, balance, and a "dynamic loudness" compressor chain (PipeWire). |
| **BatteryPanel** | The panel the bar grows into from the battery module: charge, power profile, after how long each `hypr/hypridle.conf` listener fires (dim, lock, screen off, suspend, … or Never — the block gets commented out; hypridle is restarted) and, on laptops, what closing the lid does on battery / plugged in (`/etc/systemd/logind.conf`, asks for the password). |
| **BluetoothPanel** | Adapters, power, scanning, pairing/connecting, trust/forget, battery levels, remembered devices. |
| **DashboardPanel** | The panel the bar grows into from the clock: Dash (output/input volume bubbles, clock, calendar, weather, CPU/RAM/disk, now playing with a cava spectrum), Media (full MPRIS player), Performance (CPU + temperature, memory, NVIDIA GPU, network, disks) and Weather (wttr.in). |
| **NetworkPanel** | Wi-Fi scan/connect/forget, wired profiles, connection properties (NetworkManager). |
| **NotificationPanel** | The notification daemon: popups below the bar's bell, and a history panel the status bar grows into from the bell on click (DND, actions, clear all). Replaces swaync. |
| **PowerPanel** | The panel the bar grows into from the power button (`SUPER+CTRL+P`): lock, suspend, logout, reboot, power off, with the uptime; arrow keys + Return work. Reboot and power off grow into a 5 s countdown bubble: click it (or Return) to go now; Cancel, Escape, a click elsewhere or closing the panel calls it off. |
| **QuickSettingsPanel** | The gear in the bar (`SUPER+CTRL+S`): dark/light, color picker, screenshot, GTK/Qt theme menu, volume/mic/brightness sliders, accent palette, media players, a gamemode switch and an **All settings** button that opens the SettingsApp. |

| App | What it does |
|-----|--------------|
| **DockApp** | Bottom app dock with pinned apps and running windows, optional autohide. `toggle.sh` turns it on/off. |
| **KeybindsApp** | Keybind editor in the middle of the screen, read from `hypr/keybindings.lua`: search and sections on the left (add, rename, delete — a deleted section's binds move elsewhere or go with it). Left click (or Return) edits a bind: record a new shortcut from keys, mouse buttons (incl. thumb buttons) or the wheel with modifiers, change description, command and section, unbind or delete it; **New keybind** adds one (shortcut + command + description). A shortcut already in use is flagged with Cancel / Clear other / Keep both; bare keys or clicks that would break normal input are refused. Right click (or Ctrl+Return) runs the bind. Workspace-loop binds are read-only; mouse-drag binds only take mouse buttons. |
| **LauncherApp** | Application launcher (`SUPER+E`): tabs for apps, files, windows, `$PATH` commands and emoji (category tabs, `SUPER+.` opens it there; picking copies). Apps and emoji show as a list or a grid (SettingsApp, Launcher tab); arrows move within a grid. The search field is also a calculator (`+ - * / ^ ( ) [ ]`) whose answer shows on the left, Return copies it. |
| **MonitorApp** | Drag-and-drop monitor arrangement, mode and scale, saved layout profiles; writes `hypr/monitors.lua`. |
| **OcrApp** | Text extractor (`SUPER+ALT+A`, or New capture in its window): drag a screen area, its text (tesseract OCR) is copied and shown editable in a centered window, with the OCR language picker. |
| **OverviewApp** | Workspace overview with live window previews (separate `qs` instance, `SUPER+Tab`). |
| **SettingsApp** | Settings window in the middle of the screen (opened from the QuickSettingsPanel, IPC `settings`), in tabs: Appearance (accent palette, GTK/Qt theme tools, wallpaper), Bar & Dock (status bar, expanded bar, taskbar), Launcher (grid apps/emoji), Night light (on/off, temperature, brightness, schedule: fixed times or sunset–sunrise) and System (gamemode, fastfetch, visualizer mode). |
| **StatusbarApp** | Per-monitor top bar (workspaces, taskbar, clock, tray, battery (BatteryPanel), volume, updates, …) that expands on hover or `SUPER+SPACE`. `toggle.sh` turns it on/off. |
| **VisualizerApp** | Visualizer mode: Super+Alt+V opens a setup panel (style, bars / wave / line, bar width, spacing, line thickness, minimum length, sensitivity, monitor, and the circle's position and size dragged on a live mini preview); Start hides the bar, dock and normal notification popups and draws the visualizer over the chosen monitor on the GPU (`shaders/visualizer.frag`), colored by what is on screen around it (a ring around the circle, or the screen edges, sampled by the shroomery `screen-colors.py` daemon; "Wallpaper only" samples the wallpaper instead; the setup preview shows the real sampled colors). Super+Alt+V again stops it. While it runs: Super+←/→ style, Super+↑/↓ bars/wave/line, Super+Esc exits. The SettingsApp switch opens the setup too. |
| **WallpaperApp** | Thumbnail grid of `WallpaperApp/wallpapers/` (folder configurable) in two tabs, Static and Animated (videos/GIFs in the folder's `animated/`, played by mpvpaper; Tab switches), search, arrow keys + Return pick and apply one, random pick, transitions, per-monitor set, effects (still images only). |

## How it fits together

- `shell.qml` creates every app window. Each one is built from the shared UI
  kit in `shared/ui/` (`SlidePanel`, `CenterPanel`, `PanelSurface`, `Card`,
  `AppHeader`, buttons, switches, combos, search fields, menus), so they all
  share the dashboard's look and behave the same: they open on the focused
  monitor and close on Escape or an outside click. The launcher, MonitorApp,
  WallpaperApp, OcrApp and KeybindsApp open in the middle of the screen (`CenterPanel`).
- Panels that belong to a bar button (audio, network, bluetooth, settings,
  notifications, battery, power, the taskbar's window list, the dashboard) are not windows:
  the bar (`StatusbarApp/StatusbarWindow`) grows into them as one shape
  (`BarShape`) after clicking the button (the taskbar's window list opens on
  hover), and morphs between them as the pointer moves to another button
  (`PopoutHost`). `shared/ui/PopoutState`
  tracks which one is open and owns their IPC targets; `shell.qml` registers
  them by name.
- `shared/Theme.qml` holds the palette; `shared/Paths.qml` holds every
  external path.
- Setting a wallpaper runs `shroomery/scripts/wallpaper.sh` (awww, or mpvpaper for an animated one, + matugen),
  which re-themes Quickshell, swaync (if running), kitty and the rest, and renders the
  blurred copies used by hyprlock, wlogout and LauncherApp.
- Session start: `hypr/autostart.lua` runs `shroomery/scripts/autostart.sh`,
  which starts `qs`, OverviewApp, and restores the wallpaper and theme.

## Dependencies

Quickshell 0.3+ with the Hyprland, Pipewire, Bluetooth, UPower, Mpris and
SystemTray modules. Every path below is defined once in `shared/Paths.qml`;
scripts and settings are documented in `~/.config/shroomery/README.md`.

### Shared by all apps

| File | Info | Purpose |
|------|------|---------|
| `~/.config/shroomery/colors/colors.json` | matugen Material roles, `"primary": "#rrggbb"`, … | `shared/Theme.qml` palette. Read on `qs ipc call theme-manager reload` (sent by the theme scripts and autostart), so a freshly started `qs` shows default colors until the first reload. |
| `shared/icons/*.svg` | white monochrome icons | tinted at runtime via `Paths.icon("name")` |
| FiraCode Nerd Font | Material Design glyphs | `Theme.iconFontFamily` (dashboard icons) |
| `qs` IPC | target per app | `toggle.sh` → `shared/toggle.sh` → `qs ipc call <target> <fn>` |

### Per app

| App | Reads | Writes | Runs |
|-----|-------|--------|------|
| AudioPanel | Pipewire graph | `~/.local/state/quickshell/dynamic-loudness.json` (loudness settings), `$XDG_RUNTIME_DIR/quickshell-dynamic-loudness.conf` (generated filter-chain) | `pactl`, `pw-dump`, `pw-cli`, `pipewire` (filter-chain with `lsp-plugins`) |
| BluetoothPanel | BlueZ (Quickshell.Bluetooth), `~/.local/share/bluetooth_controls/known-devices.json` (remembered devices) | same JSON | `busctl`, `rfkill`, `systemctl` (via `sudo` when unblocking/starting bluetooth — asks for the password in the panel) |
| DashboardPanel | `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`, `/proc/uptime`, `/proc/sys/kernel/hostname`, `/sys/class/hwmon/*/temp1_input` (k10temp/coretemp/zenpower), `/sys/bus/pci/drivers/nvidia/*/power/runtime_status`, `~/.face` (optional avatar), Mpris, `~/.config/shroomery/settings/weather-location` (optional, empty = by IP), `~/.cache/shroomery/weather.json` | `~/.cache/shroomery/weather.json` | `cava` with a config generated in `$XDG_RUNTIME_DIR/shroomery/` by `shared/CavaSpectrum.qml` (output spectrum around the cover art, only while Dash or Media shows), `df`, `test`, `mkdir`, `nvidia-smi` (only while the Performance tab shows and the GPU is awake), `curl` → `https://wttr.in/<location>?format=j1` (on open, at most every 30 min) |
| DockApp | `~/.config/shroomery/settings/dock.json`, desktop entries, icon theme (`QS_ICON_THEME`) | `dock.json` (pins, enabled, autohide) | the pinned apps |
| KeybindsApp | `~/.config/hypr/keybindings.lua`, `~/.config/hypr/input.lua` (parsed by `keybinds.py`), `hyprctl -j devices` + libxkbcommon (keyboard layout, to name captured keys), `hyprctl configerrors` | `keybindings.lua` (added / edited / moved / deleted binds and section headings — a section is a `-- Name` comment after a blank line; an unbound shortcut is commented out with `-- [unbound] `) | `python3`, `hyprctl reload config-only` after a change (the old file is restored if it adds config errors), `hyprctl eval` / `dispatch` (empty `qs_keybind_capture` submap while recording a shortcut, auto-reset after 20 s), the bound command / `hyprctl dispatch` |
| LauncherApp | `LauncherApp/emojis.tsv` (emoji list), `~/.config/shroomery/settings/launcher-view.json` (list/grid), desktop entries, icon theme, Hyprland toplevels, `$PATH` directories, the home folder tree, `~/.cache/shroomery/blurred_wallpaper.png` (backdrop) | `launcher-view.json` (LauncherState, set from SettingsApp) | the chosen app / command (`sh -c`), `shroomery/scripts/terminal.sh` (terminal apps), `pkexec` (run as root: right click or Alt+Return; `sudo` for terminal apps), `xdg-open` (files), `wl-copy` (calculator answer, emoji), `bash` + `find` (lists `$PATH` once) |
| OcrApp | `tesseract --list-langs` (via `ocr.sh`), `~/.config/shroomery/settings/ocr-language` | `ocr-language` | `shroomery/scripts/ocr.sh` (`hyprpicker`, `slurp`, `grim`, `magick`, `tesseract`), `wl-copy` |
| MonitorApp | `hyprctl monitors`, `~/.config/hypr/monitors.lua`, `~/.local/share/control_controls/monitor-profiles/*.json` | `monitors.lua`, profile JSONs | `hyprctl`, `python3` |
| NetworkPanel | NetworkManager (via `nm_helper.py`) | NM connections | `python3`, `nmcli`, `nm-connection-editor`, `rfkill`, `systemctl`; privileged commands via `sudo -S` (password asked in the panel) |
| NotificationPanel | D-Bus `org.freedesktop.Notifications` (Quickshell.Services.Notifications — only one daemon can own it, so swaync must not run), `~/.config/shroomery/settings/notifications.json` (`dnd`) | `notifications.json` | the notifications' actions |
| OverviewApp | `OverviewApp/config.json`, `OverviewApp/common/Appearance.colors.qml` (written by matugen), Hyprland | — | `hyprctl` — separate instance: `qs -p ~/.config/quickshell/OverviewApp` |
| BatteryPanel | UPower + power-profiles-daemon (D-Bus), `~/.config/hypr/hypridle.conf`, logind's `HandleLidSwitch*` + UPower `LidIsPresent` (via `lid-switch.sh status`) | `hypridle.conf` (listener `timeout`, or the block commented out for Never), `/etc/systemd/logind.conf` (via `lid-switch.sh set`) | `pkill`/`pgrep`/`setsid hypridle` (restart after a change), `shroomery/scripts/lid-switch.sh` (`busctl`, `pkexec`, `systemctl reload systemd-logind`) |
| PowerPanel | — | — | `shroomery/scripts/power.sh` |
| QuickSettingsPanel | `~/.config/gtk-3.0/settings.ini` (dark/light), Pipewire, Mpris, `brightnessctl`; `shroomery/settings/gamemode-enabled`, `accent`, `accent-index`, `accent-scheme`; `~/.cache/shroomery/wallpaper-colors` | (accent files through `apply-theme.sh`) | `shroomery/scripts/toggle-theme.sh`, `apply-theme.sh`, `hyprpicker`, `hypr/scripts/screenshot.sh`, `hypr/scripts/gamemode.sh`, `hypr/scripts/gtk.sh`, `nwg-look`, `qt6ct`, `brightnessctl`, `wpctl`, `qs ipc call settings open` |
| SettingsApp | `shroomery/settings/gamemode-enabled`, `hide-fastfetch`, `accent`, `accent-index`, `accent-scheme`, `night-light.json`; `~/.cache/shroomery/wallpaper-colors`; StatusbarApp and LauncherApp state | `hide-fastfetch`, `night-light.json`; statusbar JSON (through StatusbarState); `launcher-view.json` (through LauncherState); others via scripts | `shroomery/scripts/apply-theme.sh`, `editor.sh`, `hyprsunset.sh` (night light: toggle, apply, sync, status, sun-times), `hypr/scripts/gamemode.sh`, `hypr/scripts/gtk.sh`, `nwg-look`, `qt6ct`, `qs ipc call wallpaper open` |
| StatusbarApp | `~/.config/shroomery/settings/statusbar.json`, desktop entries (taskbar), Hyprland toplevels, Hyprland workspaces, UPower + power-profiles-daemon (D-Bus, battery module), tray, Pipewire, NetworkManager, BlueZ (bluetooth module) | `statusbar.json` (enabled, alwaysExpanded, taskbar enabled/pins) | `shroomery/scripts/check-updates.sh` (every 30 min), `install-updates.sh`, `terminal.sh`, `hypr/scripts/launcher.sh`, `swaync-client` (only the optional `swaync` module), `nmcli` + `ip route` (network module) |
| VisualizerApp | `~/.config/shroomery/settings/visualizer.json`, `$XDG_RUNTIME_DIR/shroomery/screen-colors.sock` (frames) | `visualizer.json`, `$XDG_RUNTIME_DIR/shroomery/visualizer-active`, `$XDG_RUNTIME_DIR/shroomery/cava-96-60.conf`, `cava-96-30.conf` (preview) | `cava`, `shroomery/scripts/screen-colors.py` (→ `grim -T`, `hyprctl`, `magick`), `notify-send`, `sh`, `rm`; build time only: `/usr/lib/qt6/bin/qsb` (`VisualizerApp/shaders/build.sh`). Reads `~/.cache/shroomery/still_wallpaper` (preview background) |
| WallpaperApp | `shroomery/settings/wallpaper-folder` (default `WallpaperApp/wallpapers/`), `wallpaper-transition-effect`, `wallpaper-effect`, `wallpaper-random.json`, `shroomery/effects/`, `~/.cache/shroomery/current_wallpaper`, `~/.cache/shroomery/still_wallpaper`, `~/.cache/shroomery/thumbnails/` | `wallpaper-folder`, `wallpaper-transition-effect`, `wallpaper-effect`, `wallpaper-random.json` | `shroomery/scripts/wallpaper.sh` (→ `animated-wallpaper.sh` → `mpvpaper` for videos/GIFs), `wallpaper-thumbnails.sh` (→ `magick`, `ffmpeg`), `clear-wallpaper-cache.sh` |

### Who calls into quickshell

- `hypr/keybindings.lua` → the apps' `toggle.sh` scripts, `qs ipc call statusbar focus|reload`, `qs ipc call dock reload`.
- `hypr/scripts/launcher.sh` (`SUPER+E`, statusbar launcher button) → `LauncherApp/toggle.sh` when `shroomery/settings/launcher` is `quickshell` (the default).
- `hypr/keybindings.lua` → `LauncherApp/toggle.sh emoji` (`SUPER+.`, IPC `launcher-mode toggle emoji`), `OcrApp/toggle.sh capture` (`SUPER+ALT+A`, IPC `ocr-capture run`).
- `hypr/scripts/killactive.sh` → closes an open panel (`isOpen`/`close`) before killing a window.
- shroomery scripts → `qs ipc call theme-manager reload`, `qs ipc call updates refresh`.
- `~/.config/matugen/config.toml` → writes `OverviewApp/common/Appearance.colors.qml`.

