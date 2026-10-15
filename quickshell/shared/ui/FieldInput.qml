import QtQuick
import QtQuick.Controls
import qs.shared

// Themed single-line text field; the border lights up while it has focus.
TextField {
    id: control

    implicitHeight: 36
    color: Theme.on_surface
    selectionColor: Theme.primary
    selectedTextColor: Theme.on_primary
    placeholderTextColor: Theme.on_surface_variant
    font.family: Theme.fontFamily
    font.pixelSize: 13
    leftPadding: 12
    rightPadding: 12
    selectByMouse: true
    background: Rectangle {
        radius: 10
        color: Theme.surface_container_high
        border.color: control.activeFocus ? Theme.primary : "transparent"
        border.width: 1
    }
}
