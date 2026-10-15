import QtQuick
import QtQuick.Controls
import qs.shared

// Themed drop-down menu; fill it with MenuEntry items.
Menu {
    y: parent ? parent.height + 6 : 0
    implicitWidth: 220
    padding: 6
    background: Rectangle {
        color: Theme.surface_container
        border.color: Theme.outline_variant
        border.width: 1
        radius: 14
    }
}
