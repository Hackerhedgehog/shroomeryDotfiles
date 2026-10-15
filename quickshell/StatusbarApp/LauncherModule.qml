import Quickshell
import QtQuick
import qs.shared
// Opens the application launcher.
BarButton {
    iconSrc: Paths.icon("launcher")
    onClicked: {
        Quickshell.execDetached(["bash", "-c",
            Paths.hyprLauncher])
    }
}
