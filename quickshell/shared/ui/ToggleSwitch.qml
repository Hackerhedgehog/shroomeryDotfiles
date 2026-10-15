import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared

// On/off switch: a filled primary track with a large knob when on, an
// outlined track with a small knob when off.
Switch {
    id: control

    Layout.alignment: Qt.AlignVCenter
    implicitWidth: 48
    implicitHeight: 26
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45

    indicator: Rectangle {
        implicitWidth: 48
        implicitHeight: 26
        radius: 13
        color: control.checked ? Theme.primary : Theme.surface_container_highest
        border.color: control.checked ? Theme.primary : Theme.outline
        border.width: 2
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            property int size: control.checked ? 18 : (control.hovered ? 14 : 12)
            width: size
            height: size
            radius: size / 2
            x: control.checked ? parent.width - width - 4 : (parent.height - height) / 2
            y: (parent.height - height) / 2
            color: control.checked ? Theme.on_primary : Theme.outline
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on size { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item {}
}
