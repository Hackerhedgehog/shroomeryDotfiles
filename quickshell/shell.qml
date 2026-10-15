//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "PowerApp"
import "WallpaperApp"
import "StatusbarApp"
import "DashboardApp"
import "DockApp"
import "MonitorApp"
import "AudioApp"
import "BluetoothApp"
import "NetworkApp"
import "KeybindsApp"
import "LauncherApp"
import "OcrApp"
import "SettingsApp"
import "NotificationApp"
import "PerformanceApp"
import "VisualizerApp"
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
            "settings": settingsPanel,
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
    NotificationPopups {}
    // The visualizer overlay; exists only while visualizer mode is on.
    VisualizerWindow {}
    // Visualizer setup (Super+Alt+V); its Start runs VisualizerWindow.
    VisualizerPanel {}

    Component { id: notificationsPanel; NotificationPanel {} }
    Component { id: windowsPanel; TaskbarWindowsPanel {} }
    Component { id: audioPanel; AudioPanel {} }
    Component { id: networkPanel; NetworkPanel {} }
    Component { id: bluetoothPanel; BluetoothPanel {} }
    Component { id: batteryPanel; BatteryPanel {} }
    Component { id: settingsPanel; SettingsPanel {} }
    Component { id: dashboardPanel; DashboardPanel {} }
    Component { id: powerPanel; PowerPanel {} }
}
