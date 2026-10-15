import QtQuick
import QtQuick.Controls
import qs.shared

// One row of a PanelMenu.
MenuItem {
    id: control

    contentItem: Text {
        leftPadding: 4
        text: control.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: control.highlighted ? Theme.on_primary_container : Theme.on_surface
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 36
        color: control.highlighted ? Theme.primary_container : "transparent"
        radius: 10
    }
}
