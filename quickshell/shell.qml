//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "PowerPanel"
import "WallpaperApp"
import "StatusbarApp"
import "DashboardPanel"
import "DockApp"
import "MonitorApp"
import "AudioPanel"
import "BluetoothPanel"
import "NetworkPanel"
import "KeybindsApp"
import "LauncherApp"
import "OcrApp"
import "QuickSettingsPanel"
import "SettingsApp"
import "NotificationPanel"
import "BatteryPanel"
import "VisualizerApp"
import "InputApp"
import "TimeApp"
import "PolkitApp"
import qs.shared

ShellRoot {
    // Test IPC tools: qs ipc show

    IpcHandler {
        target: "theme-manager" 
        function reload(): void {
            Theme.reloadTheme()
        }
    }

    WallpaperWindow {}
    StatusbarBars {
        // The panels the status bar grows into, by PopoutState name.
        panels: ({
            "notifications": notificationsPanel,
            "windows": windowsPanel,
            "audio": audioPanel,
            "network": networkPanel,
            "bluetooth": bluetoothPanel,
            "battery": batteryPanel,
            "quick-settings": quickSettingsPanel,
            "dashboard": dashboardPanel,
            "power": powerPanel
        })
    }
    // Creates the dock window only while the dock is enabled in dock.json.
    DockLoader {}
    MonitorWindow {}
    KeybindsWindow {}
    LauncherWindow {}
    OcrWindow {}
    InputWindow {}
    TimeWindow {}
    SettingsWindow {}
    NotificationPopups {}
    // The visualizer overlay; exists only while visualizer mode is on.
    VisualizerWindow {}
    // Visualizer setup (Super+Alt+V); its Start runs VisualizerWindow.
    VisualizerPanel {}
    // The polkit agent (password prompts), above every other panel.
    PolkitWindow {}

    Component { id: notificationsPanel; NotificationPanel {} }
    Component { id: windowsPanel; TaskbarWindowsPanel {} }
    Component { id: audioPanel; AudioPanel {} }
    Component { id: networkPanel; NetworkPanel {} }
    Component { id: bluetoothPanel; BluetoothPanel {} }
    Component { id: batteryPanel; BatteryPanel {} }
    Component { id: quickSettingsPanel; QuickSettingsPanel {} }
    Component { id: dashboardPanel; DashboardPanel {} }
    Component { id: powerPanel; PowerPanel {} }
}
