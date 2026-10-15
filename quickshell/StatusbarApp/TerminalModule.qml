import Quickshell
import QtQuick
import qs.shared
// Opens the configured terminal.
BarButton {
    iconSrc: Paths.icon("terminal")
    onClicked: {
        Quickshell.execDetached([Paths.terminal])
    }
}
