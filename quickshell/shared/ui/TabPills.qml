import QtQuick
import QtQuick.Layouts
import qs.shared

// A row of pill tabs, the current one filled (like the dashboard's). Set `model` to the
// labels and bind `currentIndex`; a click emits activated(index).
RowLayout {
    id: root

    property var model: []
    property int currentIndex: 0
    signal activated(int index)

    spacing: 4

    Repeater {
        model: root.model
        delegate: Rectangle {
            id: pill
            required property string modelData
            required property int index
            readonly property bool current: root.currentIndex === index

            implicitWidth: label.implicitWidth + 28
            implicitHeight: 32
            radius: 16
            color: current ? Theme.primary_container : (hover.hovered ? Theme.surface_container_high : "transparent")
            Behavior on color { ColorAnimation { duration: 200 } }

            Text {
                id: label
                anchors.centerIn: parent
                text: pill.modelData
                color: pill.current ? Theme.on_primary_container : Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: pill.current
            }
            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.activated(pill.index)
            }
        }
    }
}
