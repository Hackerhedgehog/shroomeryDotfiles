import Quickshell
import QtQuick
import qs.shared
// Logo -> toggles the Settings app via IPC.
BarButton {
    iconSrc: Paths.icon("logo")
    onClicked: {
        Quickshell.execDetached(["qs", "ipc", "call", "settings", "toggle"])
    }
}
