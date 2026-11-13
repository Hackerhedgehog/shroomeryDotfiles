# CLAUDE.md

Personal Arch Linux + Hyprland desktop: Quickshell (QML) UI, shell scripts and
Hyprland config in one repo. This project is its own thing — no ml4w code or
paths. Do not reintroduce references to `~/.config/ml4w` or ml4w scripts.

Start with `README.md` here (how the three parts fit together); each part has
its own README with the details: `quickshell/README.md`, `shroomery/README.md`
(+ `shroomery/screencolors/README.md`).

## Rules

- Do not do anything with git (commit, branch, stash, add, mv, …) unless the
  user explicitly asks. Use plain `mv`/`cp`/`rm` for file moves.
- This repo lives at `~/shroomeryDotfiles`; `~/.config/{hypr,quickshell,shroomery,matugen}` are symlinks
  into it (made by `install.sh`, which also works from another clone location). Always use the `~/.config/...` paths in code and docs, never the resolved target.
  Nothing here may depend on `~/.mydotfiles` or `~/.config/ml4w` (both are meant to be deletable).
- `quickshell/README.md` lists every dependency (files read/written, programs run). Keep it in sync when
  adding a path to `quickshell/shared/Paths.qml` or a new external command.
- A new external command (or QML/Python module) also needs its package in `install/packages/pacman.txt`
  (or `aur.txt`), so `install.sh` installs it on a fresh system. `bash install/tests/deps.sh` checks this;
  a word it flags that isn't a real dependency (or is optional) goes in `install/tests/deps-ignore.txt` with the reason. Machine-specific state that the installer resets on a
  fresh install (monitors, keyboard layout, …) is handled in `install/steps/50-config.sh`.
- The repo is shared: no personal data in tracked files (home paths, names, emails, locations, hostnames).
  Test fixtures use neutral values (`/home/user`, …); Python bytecode is git-ignored.

## Where things live

| Directory              | Holds                                                          |
|------------------------|----------------------------------------------------------------|
| `~/.config/quickshell` | UI apps only (`quickshell/` here)                              |
| `~/.config/shroomery`  | Shell scripts, theme sync, user settings, generated colors     |
| `~/.config/hypr`       | The Hyprland desktop (keybinds, autostart, hyprlock, …)        |
| `~/.config/matugen`    | matugen config + templates (wallpaper → palette files)         |
| `install.sh`, `install/` | Installer: `install/steps/NN-name.sh` run in order, `install/lib.sh` helpers, `install/packages/*.txt` |

shroomery layout:
- `lib.sh` — shared paths/helpers every script sources (mirror of `quickshell/shared/Paths.qml`)
- `notify.sh` — `notify_user` helper sourced by hypr scripts
- `scripts/` — `wallpaper.sh`, `animated-wallpaper.sh` (mpvpaper: videos/GIFs, paused on battery/gamemode), `wallpaper-thumbnails.sh`, `apply-theme.sh`, `toggle-theme.sh`, `power.sh`,
  `check-updates.sh`, `install-updates.sh` (opens Settings → Update), `autostart.sh`,
  `terminal.sh`, `editor.sh`, `clear-wallpaper-cache.sh`, `ocr.sh`, `lid-switch.sh`, `screen-colors.py`,
  `input.sh` (keyboard layout + flat mouse speed, writes the `shroomery_input` block in `~/.config/hypr/input.lua`), `time.sh` (timedatectl/localectl/locale-gen), `lock-clock.sh` (hyprlock clock, 24/12 h from `statusbar.json`)
- `screencolors/` — the screen color sampler package (`screen-colors.py`), with its own README (protocol, LED notes)
- `effects/` — wallpaper effects (ImageMagick snippets) applied by `wallpaper.sh`
- `listeners/` + `listeners.sh` — background watchers (GTK dark/light → re-theme, low battery, AC plug → pause/resume animated wallpaper, night light schedule,
  mouse speed per monitor on Hyprland `focusedmon`, automatic timezone on network connect)
- `settings/` — user state: `statusbar.json`, `dock.json`, `wallpaper-*`, `accent`, `accent-index`, `accent-scheme`, `weather-location`,
  `terminal`, `editor`, `launcher`, `launcher-view.json`, `ocr-language`, `visualizer.json`, `night-light.json`, `input.json`, `time.json`, `pip` (written by `hypr/pip.lua`), flag files (`gamemode-enabled`, `hide-fastfetch`)
- `colors/colors.json` — matugen output, read by `quickshell/shared/Theme.qml`
- Cache: `~/.cache/shroomery/` (current wallpaper, blurred/square variants for hyprlock/wlogout/LauncherApp)

A script that isn't about drawing UI belongs in shroomery, not in quickshell. `shroomery/README.md` documents
every script/setting.

## Layout of quickshell/

Paths in this section and below are relative to `quickshell/` unless they start with `~`.
Design specs and plans live in `quickshell/docs/superpowers/`.

- `<Name>Panel/` holds a popout the status bar grows into (registered in `shell.qml` `StatusbarBars.panels`);
  `<Name>App/` holds an app window (`CenterPanel`/`SlidePanel`) or something that isn't a popout (statusbar, dock,
  visualizer). Panels: Audio, Bluetooth, Network, Notification, Battery, Power, Dashboard, QuickSettings.
  `QuickSettingsPanel` (the gear, IPC `quick-settings`) has the quick actions and an "All settings" button that
  opens `SettingsApp` (IPC `settings`; tabs Appearance, Bar & Dock, Launcher, Night light, Update, System; `openTab <name>` opens a tab).
- `shell.qml` — main shell root; instantiates every app window.
- `<Name>App/` — one directory per app, each with a `toggle.sh`.
- `shared/` — code used by more than one app (`import qs.shared`):
  - `Theme.qml` (singleton) — matugen colors + `fontFamily`; reloaded via `qs ipc call theme-manager reload`.
  - `Paths.qml` (singleton) — **every** path outside an app's own dir. Add new external paths here, never inline.
  - `PowerProfileMenu.qml`, `icons/*.svg`, `toggle.sh`.
  - `CavaSpectrum.qml` (one cava process → `bars`; config generated in `Paths.runtimeDir`), `Visualizer.js` (spectrum ring helpers).
- `shared/ui/` — the UI kit (`import qs.shared.ui`). All apps must use it so they look and behave the same:
  - `SlidePanel` — window frame: slides from `edge` left/right/top on the focused monitor, outside-click
    and Escape close, IPC `toggle/open/close/isOpen` on `ipcTarget`. Options: `panelWidth`, `fullHeight`,
    `topMargin`, `bottomMargin`, `escapeHandler` (return true when it consumed Escape), `focusGrabEnabled`,
    `ipcEnabled` (false when the app declares its own `IpcHandler` for `ipcTarget`: a target takes one handler only, SettingsWindow does this for `openTab`).
  - `PopoutPanel` — root of a panel the status bar grows into (not a window): lay content out at
    `implicitWidth` (use `standardWidth`, shared by all bar-button panels) × `implicitHeight` (cap with `maxHeight`); `active` replaces "is open", `closeRequested()`
    closes, `escapeHandler` returns true when it used Escape, `holdOpen` while a child popup holds a focus grab.
    Register it by name in `shell.qml` (`StatusbarBars.panels`) and give it an IPC target with
    `PanelIpc { target: "<name>" }` in `PopoutState`. A bar button opens it with `BarButton { popout: "<name>" }`
    (a click opens it pinned and a second click closes it; while one is pinned, hovering another button
    moves it there; Return opens it pinned). Only the taskbar's `windows` list also opens on hover (after 150 ms). Used by notifications, audio,
    network, bluetooth, settings, battery (`BatteryPanel/BatteryPanel`: charge, power profile, hypridle timeouts, lid action), the taskbar's window list (`windows`, `StatusbarApp/TaskbarWindowsPanel`)
    the dashboard (the clock) and the power menu (`PowerPanel/PowerPanel`).
  - `PopoutState` (singleton) — which panel is open, on which monitor, from which button, pinned or not
    (rules + tests: `PopoutLogic.js`). One panel at a time; it closes 300 ms after the pointer leaves pill and
    panel unless a press inside pinned it. Each bar's `StatusbarApp/PopoutHost` draws it and morphs between
    panels; `StatusbarApp/BarShape` draws pill + panel as one outline (`BarGeometry.js`).
  - `CenterPanel` — a `SlidePanel` for an app window in the middle of the screen (drops in from the top like
    the launcher), on a `PanelSurface`. Set `cardWidth`/`cardHeight`; children go on the card, with
    `anchors.margins: 20`. Used by MonitorApp, WallpaperApp, OcrApp, KeybindsApp, InputApp (Super+I), TimeApp (Super+T) and PolkitApp
    (the session's polkit agent / password prompt, opened by polkit itself; `shared/PolkitState.qml` adds its window to every SlidePanel's focus grab).
  - `PanelSurface` — shadow + gradient-border card; put a `ColumnLayout { anchors.fill: parent; anchors.margins: 18 }` in it.
  - The look follows DashboardPanel: content sits in `Card`s (rounded surface_container tiles), controls are
    pills with tonal fills rather than outlines, no divider lines. `AppHeader` (glyph badge + title +
    subtitle, extra children on the right) heads an app window; `StatusChip` (`tone`: normal/good/busy/error),
    `SearchField` (pill with magnifier), `FieldInput` (text field), `SettingRow` (label + hint left, control right).
    Icons in text are Nerd Font glyphs (`Theme.iconFontFamily`, `String.fromCodePoint(0xF0…)`).
  - `TabPills` (a row of pill tabs: `model` labels, `currentIndex`, `activated(index)`), `PanelTitle`, `ParamRow` (label + slider + typed value, `moved(value)`), `SectionHeader` (`collapsible` + `expanded` for a click-to-expand group), `FieldLabel`, `PanelButton` (`filled`/`tonal`/`compact`, `glyph`), `ActionIcon`
    (`iconSrc` or `iconTxt`), `ColoredIcon`, `ToggleSwitch`, `FieldCombo` (use `boundIndex` when the
    selection comes from state), `PanelMenu` + `MenuEntry`, `AppButton` (dock/taskbar app icon),
    `InlineMenu` (context menu drawn inside the caller's window), `WindowList` (an app's windows by title:
    click focuses, middle click closes), `PickerList` (SearchField + list of `{ key, label, detail }`, `currentKey`, `picked(key)`;
    search in `PickerLogic.js`).
  - Qt 6.10's QtQuick.Controls has its own `SearchField`: a `shared/ui` file that uses ours and imports
    Controls must import it `as QQC` (sibling types lose to explicit imports).
  - `AccentState.qml` (singleton) — accent palette state/actions (QuickSettingsPanel and SettingsApp); its picker is `shared/ui/AccentPicker.qml`.
  - `AppList.qml` (singleton) — desktop-entry lookup and "pinned + running apps" list for DockApp and the taskbar.
- `VisualizerApp/` — visualizer mode (`VisualizerState` singleton, IPC `visualizer`, Super+Alt+V); colors come from the shroomery
  `screen-colors.py` daemon (`~/.config/shroomery/screencolors/README.md`). The bar, dock and notifications read
  `VisualizerState.active` to get out of the way — never write their settings for it. `VisualizerPanel` (setup, a
  `CenterPanel`) + `MiniScreen` (live preview, circle drag); `VisualizerRenderer` draws with `shaders/visualizer.frag`
  — run `shaders/build.sh` after editing the shader (the `.qsb` is kept in the repo), then **restart** qs: Qt caches
  compiled shaders per process, so a hot reload keeps the old one.
  The same can happen to a `.js` file imported by components that load late (VisualizerApp): if behavior doesn't
  match the code after a save, restart qs before debugging further. The renderer's data textures are Canvases
  filled with one gradient each: per-pixel `ImageData` writes don't reach the texture, and a `visible: false` Canvas never paints.
- `OverviewApp/` — workspace overview; a **separate** Quickshell instance (`qs -p ~/.config/quickshell/OverviewApp`)
  with its own `shell.qml` and `common/` modules. Its `common/Appearance.colors.qml` is generated by matugen.
  Address it with the `~/.config/...` path, not the resolved symlink target — qs keys instances by launch path.

## Conventions

- New popout: `FooPanel/FooPanel.qml` on `PopoutPanel`, a `Component` in `shell.qml` and a `StatusbarBars.panels` entry.
- New app: `FooApp/FooWindow.qml` built on `CenterPanel` (or `SlidePanel` + `PanelSurface` for an edge panel), add `FooWindow {}` to `shell.qml`,
  add `FooApp/toggle.sh`:
  ```bash
  #!/usr/bin/env bash
  # Show/hide the foo panel.
  # Usage: toggle.sh [toggle|open|close|status]
  exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" foo "$@"
  ```
- Don't copy a widget into an app. If it is needed twice, it goes in `shared/ui/`.
- Icons: `Paths.icon("name")` (absolute URL). Never use relative `"../shared/icons/…"` strings — they
  resolve against the file that finally loads them, which breaks inside `shared/ui` components.
- Colors only from `Theme.*`; font `Theme.fontFamily`.
- App state that must persist goes in `~/.config/shroomery/settings/` via a `Paths` property.
  `StatusbarApp/statusbar.json` and `DockApp/dock.json` are reference docs of defaults, not the live files.
- Statusbar, dock and visualizer aren't panels: their `toggle.sh` open/close map to IPC `enable`/`disable`.

## Verifying changes

Run the commands below from `~/.config/quickshell`.

- The running `qs` hot-reloads on save. Read its log with `qs log` (or `qs -p ~/.config/quickshell/OverviewApp log`).
  Strip colors with `sed 's/\x1b\[[0-9;]*m//g'` and look for `WARN`/`ERROR` after the last `Configuration Loaded`.
  A file that is only loaded later (inside a `LazyLoader`, a popout panel) may not trigger the reload when saved:
  `touch shell.qml` forces one. `console.log` lines show with `qs log -r "*.debug=true"`.
- `qs ipc show` lists targets; open/close panels with the app's `toggle.sh` to exercise them.
- Pure JS unit tests: `node --test shared/ui/tests/ shared/tests/ VisualizerApp/tests/ StatusbarApp/tests/ DashboardPanel/tests/ AudioPanel/tests/ LauncherApp/tests/ KeybindsApp/tests/ BatteryPanel/tests/ SettingsApp/tests/ InputApp/tests/ TimeApp/tests/`.
- Hyprland Lua helpers: `lua ~/.config/hypr/tests/piplogic.lua` (picture-in-picture geometry), `lua ~/.config/hypr/tests/unitylogic.lua` (Unity asset picker placement). Hyprland Lua can be run live
  with `hyprctl eval '<lua>'` (or `hyprctl repl '<lua>'` to print a returned value).
- Shroomery bash helpers: `bash ~/.config/shroomery/tests/night-light.sh`, `bash ~/.config/shroomery/tests/input.sh`, `bash ~/.config/shroomery/tests/time.sh`, `bash ~/.config/shroomery/tests/pkg-update.sh`, `bash ~/.config/shroomery/tests/recovery.sh`.
  Run them capped, in the foreground: `systemd-run --user --scope -p TasksMax=1000 -q bash <test>` (a runaway
  test once used up the terminal's process limit and crashed Claude Code). Not under `nohup` or `&`: the
  ignored SIGHUP/SIGINT they pass on makes the signal tests fail falsely. A PATH stub calls the real binary by
  absolute path, never `command <name>` (that finds the stub itself).
- Shell scripts: `bash -n` at least.
- Dependencies: `bash install/tests/deps.sh` (`-v` lists what covers each command); run it after adding
  an external command, a QML import or a Python import.
- Installer: `./install.sh --dry-run --yes` prints every change without making it. To run steps for real
  without touching this machine, copy the repo into the scratchpad and run it with `HOME=<scratch>/home`
  (`--only link,config` needs no sudo).
