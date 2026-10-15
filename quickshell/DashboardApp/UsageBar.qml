import QtQuick
import QtQuick.Layouts
import qs.shared

// A labelled usage bar: label left, value text right, a filled track below.
ColumnLayout {
    id: bar

    property string label: ""
    property string valueText: ""
    property real fraction: 0

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: bar.label
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideMiddle
        }
        Text {
            text: bar.valueText
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Theme.surface_container_highest
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, bar.fraction))
            height: parent.height
            radius: 3
            color: bar.fraction > 0.9 ? Theme.error : Theme.primary
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
}
