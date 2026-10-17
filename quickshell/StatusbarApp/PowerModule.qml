import Quickshell
import QtQuick
import qs.shared

// Power button: clicking grows the bar into the PowerPanel panel.
BarButton {
    popout: "power"
    iconSrc: Paths.icon("power")
}
