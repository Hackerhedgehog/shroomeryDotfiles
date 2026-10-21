pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Every path outside an app's own directory that the apps read, write or run.
// Change a path here; consumers `import qs.shared` and use the property.
// The shroomery side keeps the same paths in ~/.config/shroomery/lib.sh.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // Absolute URL of a bundled icon: Paths.icon("volume") -> shared/icons/volume.svg.
    function icon(name: string): string {
        return "file://" + Quickshell.shellPath("shared/icons/" + name + ".svg");
    }

    // --- quickshell ---
    readonly property string wallpaperDefaultFolder: Quickshell.shellPath("WallpaperApp/wallpapers")

    // --- shroomery: scripts, settings and generated colors ---
    readonly property string shroomery: home + "/.config/shroomery"
    readonly property string scripts: shroomery + "/scripts"
    readonly property string settings: shroomery + "/settings"

    readonly property string colors: shroomery + "/colors/colors.json"
    readonly property string wallpaperEffectsDir: shroomery + "/effects"
    readonly property string statusbarSettings: settings + "/statusbar.json"
    readonly property string dockSettings: settings + "/dock.json"
    readonly property string notificationSettings: settings + "/notifications.json"
    readonly property string wallpaperFolderSetting: settings + "/wallpaper-folder"
    readonly property string wallpaperTransitionSetting: settings + "/wallpaper-transition-effect"
    readonly property string wallpaperEffectSetting: settings + "/wallpaper-effect"
    readonly property string wallpaperRandomSetting: settings + "/wallpaper-random.json"
    readonly property string gamemodeEnabled: settings + "/gamemode-enabled"
    readonly property string hideFastfetch: settings + "/hide-fastfetch"
    readonly property string ocrLanguageSetting: settings + "/ocr-language"
    readonly property string launcherViewSettings: settings + "/launcher-view.json"
    // Palette source, written by apply-theme.sh: "wallpaper" or #rrggbb, which
    // of the wallpaper's colors (0–2) and the matugen scheme type.
    readonly property string accentSetting: settings + "/accent"
    readonly property string accentIndexSetting: settings + "/accent-index"
    readonly property string accentSchemeSetting: settings + "/accent-scheme"
    // Visualizer settings, written by the setup panel's Start (VisualizerLogic.DEFAULTS lists the keys).
    readonly property string visualizerSettings: settings + "/visualizer.json"
    // Night light: mode (off/fixed/sun), on/off times, temperature, gamma (NightLightLogic.DEFAULTS).
    readonly property string nightLightSettings: settings + "/night-light.json"
    // Safe system update (shroomery/lib.sh has the same names): versions per package that
    // `paccache` keeps (an integer 1-20, default 3) and the protected package patterns, one per line.
    readonly property string cacheKeepFile: settings + "/cache-keep"
    readonly property string protectedFile: settings + "/recovery-protected"

    readonly property string setWallpaper: scripts + "/wallpaper.sh"
    readonly property string clearWallpaperCache: scripts + "/clear-wallpaper-cache.sh"
    readonly property string wallpaperThumbnailsScript: scripts + "/wallpaper-thumbnails.sh"
    readonly property string applyTheme: scripts + "/apply-theme.sh"
    readonly property string toggleTheme: scripts + "/toggle-theme.sh"
    readonly property string power: scripts + "/power.sh"
    readonly property string checkUpdates: scripts + "/check-updates.sh"
    readonly property string installUpdates: scripts + "/install-updates.sh"
    readonly property string terminal: scripts + "/terminal.sh"
    readonly property string uninstallApp: scripts + "/uninstall-app.sh"
    readonly property string pkgUpdate: scripts + "/pkg-update.sh"
    // The copy in the repo; the installed one (recoveryScript) exists after the first apply.
    readonly property string recoveryScriptSource: scripts + "/recovery.sh"
    readonly property string editor: scripts + "/editor.sh"
    readonly property string ocr: scripts + "/ocr.sh"
    readonly property string lidSwitch: scripts + "/lid-switch.sh"
    readonly property string conservationMode: scripts + "/conservation-mode.sh"
    readonly property string hyprsunset: scripts + "/hyprsunset.sh"
    // Screen color sampler daemon (shroomery/screencolors/README.md).
    readonly property string screenColors: scripts + "/screen-colors.py"

    // Written by shroomery/scripts/wallpaper.sh: the wallpaper (an image, or a video/GIF for an
    // animated one) and a still of it (the image, or the animated one's first frame).
    readonly property string wallpaperCache: home + "/.cache/shroomery/current_wallpaper"
    readonly property string stillWallpaper: home + "/.cache/shroomery/still_wallpaper"
    // The wallpaper's candidate accent colors, one #rrggbb per line (wallpaper.sh).
    readonly property string wallpaperColors: home + "/.cache/shroomery/wallpaper-colors"
    // Blurred copy of the wallpaper, also written by wallpaper.sh (LauncherApp backdrop).
    readonly property string blurredWallpaper: home + "/.cache/shroomery/blurred_wallpaper.png"
    // Written by shroomery/scripts/wallpaper-thumbnails.sh.
    readonly property string wallpaperThumbnails: home + "/.cache/shroomery/thumbnails"

    // --- runtime state (gone after a reboot; lib.sh SHROOMERY_RUNTIME) ---
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shroomery"
    readonly property string screenColorsSocket: runtimeDir + "/screen-colors.sock"
    // Exists while visualizer mode is on; hypr keybindings.lua reads it.
    readonly property string visualizerFlag: runtimeDir + "/visualizer-active"

    // --- hypr ---
    readonly property string hyprKeybinds: home + "/.config/hypr/keybindings.lua"
    readonly property string hyprInput: home + "/.config/hypr/input.lua"
    readonly property string hyprMonitors: home + "/.config/hypr/monitors.lua"
    readonly property string hypridleConf: home + "/.config/hypr/hypridle.conf"
    readonly property string hyprLauncher: home + "/.config/hypr/scripts/launcher.sh"
    readonly property string hyprGtk: home + "/.config/hypr/scripts/gtk.sh"
    readonly property string hyprScreenshot: home + "/.config/hypr/scripts/screenshot.sh"
    readonly property string hyprGamemode: home + "/.config/hypr/scripts/gamemode.sh"

    // --- other desktop config ---
    readonly property string gtk3Settings: home + "/.config/gtk-3.0/settings.ini"

    // --- app data ---
    readonly property string bluetoothMemory: home + "/.local/share/bluetooth_controls/known-devices.json"
    readonly property string bluetoothMemoryDir: home + "/.local/share/bluetooth_controls"
    readonly property string monitorProfiles: home + "/.local/share/control_controls/monitor-profiles"

    // --- dashboard ---
    readonly property string weatherLocation: settings + "/weather-location"
    readonly property string cacheDir: home + "/.cache/shroomery"
    readonly property string weatherCache: cacheDir + "/weather.json"
    // Optional avatar (AccountsService-style ~/.face).
    readonly property string faceImage: home + "/.face"

    // --- safe system update (root-owned, world-readable): known-good/ pending/ logs/ recovery.sh ---
    readonly property string recoveryDir: "/var/lib/shroomery/recovery"
    readonly property string recoveryScript: recoveryDir + "/recovery.sh"

    // --- system (read by DashboardPanel/SystemStats) ---
    readonly property string procDir: "/proc"
    readonly property string hwmonDir: "/sys/class/hwmon"
    // power/runtime_status of the NVIDIA card(s) bound to this driver.
    readonly property string nvidiaDriverDir: "/sys/bus/pci/drivers/nvidia"
}
