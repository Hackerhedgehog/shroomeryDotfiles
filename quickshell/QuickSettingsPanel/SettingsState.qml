pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared
import qs.shared.ui
// Shared state for the QuickSettingsPanel: the shell-outs that no existing
// Quickshell service covers (GTK dark/light, matugen accents, brightness).
// Wi-Fi, Bluetooth, audio and do-not-disturb are read from the NetworkState /
// BluetoothState / Pipewire / NotificationState singletons instead.
QtObject {
    id: root

    // True while the QuickSettingsPanel is open in the status bar. Gates the
    // polling timers so nothing is polled while the panel is closed. Derived
    // from PopoutState: one flag for all monitors' panel instances.
    readonly property bool panelOpen: PopoutState.currentName === "quick-settings"

    // --- BRIGHTNESS (brightnessctl) ---
    // Never allow a fully dark screen; 10% is the slider floor.
    readonly property int minBrightness: 10
    property int brightness: 100
    // The value to return to when the icon is clicked while at 100%.
    property int lastBrightness: 100
    // False on machines with no backlight device (a desktop).
    property bool hasBacklight: true

    property Process brightnessReader: Process {
        id: brightnessReader
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(\"%\",\"\",$4); print $4}' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(this.text.trim())
                if (isNaN(val)) {
                    root.hasBacklight = false
                    return
                }
                root.hasBacklight = true
                root.brightness = Math.max(root.minBrightness, val)
            }
        }
    }

    function refreshBrightness(): void {
        brightnessReader.running = false
        brightnessReader.running = true
    }

    function setBrightness(pct: int): void {
        const clamped = Math.max(root.minBrightness, Math.min(100, Math.round(pct)))
        if (root.brightness < 100)
            root.lastBrightness = root.brightness
        root.brightness = clamped
        Quickshell.execDetached(["bash", "-c", "brightnessctl set " + clamped + "%"])
    }

    // Icon click: jump to full brightness, or back to the last non-full value.
    function toggleBrightness(): void {
        root.setBrightness(root.brightness >= 100
            ? Math.max(root.minBrightness, root.lastBrightness)
            : 100)
    }

    // Poll while the panel is open so the tiles track changes made elsewhere
    // (a keybinding, brightness keys). triggeredOnStart
    // gives the initial read the moment the panel opens.
    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        running: root.panelOpen
        triggeredOnStart: true
        onTriggered: {
            root.refreshBrightness()
            root.refreshDarkMode()
        }
    }

    // --- DARK / LIGHT ---
    // The GTK boolean is legitimately written as 1/0 or true/false.
    property bool darkMode: true

    property Process darkModeReader: Process {
        id: darkModeReader
        command: ["bash", "-c",
            "grep -E '^gtk-application-prefer-dark-theme=' " + Paths.gtk3Settings
            + " | awk -F'=' '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = this.text.trim()
                root.darkMode = (v === "1" || v === "true")
            }
        }
    }

    function refreshDarkMode(): void {
        darkModeReader.running = false
        darkModeReader.running = true
    }

    // Flip GTK's preference. toggle-theme.sh (or the shroomery gtk-theme
    // listener it defers to) re-applies the recorded accent source in the new
    // mode, so the shell's palette follows straight away.
    function toggleDarkLight(): void {
        Quickshell.execDetached([Paths.toggleTheme])
        // The chain takes a few seconds; re-read once it has had time to land.
        darkModeSettle.restart()
    }

    property Timer darkModeSettle: Timer {
        id: darkModeSettle
        interval: 1500
        repeat: false
        onTriggered: root.refreshDarkMode()
    }
}
