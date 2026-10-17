import Quickshell
import QtQuick
import qs.shared

// Gear: hovering it grows the bar into the QuickSettingsPanel.
BarButton {
    id: settingsButton
    popout: "quick-settings"
    iconSrc: Paths.icon("settings")
}
