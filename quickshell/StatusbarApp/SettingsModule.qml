import Quickshell
import QtQuick
import qs.shared

// Gear: hovering it grows the bar into the SettingsApp panel.
BarButton {
    id: settingsButton
    popout: "settings"
    iconSrc: Paths.icon("settings")
}
