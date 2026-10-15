import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared

// Pill-shaped search box with a magnifier, like the launcher's.
Rectangle {
    id: search

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    readonly property alias field: field

    // Every key press, before the text field handles it; set event.accepted to keep it from the field
    // (e.g. arrows that move a result selection).
    signal keyPressed(var event)

    function focusField() {
        field.forceActiveFocus();
    }

    implicitWidth: 260
    implicitHeight: 40
    radius: height / 2
    color: Theme.surface_container_high
    border.color: field.activeFocus ? Theme.primary : "transparent"
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 10
        spacing: 10

        Text {
            text: String.fromCodePoint(0xF0349)   // magnify
            color: Theme.on_surface_variant
            font.family: Theme.iconFontFamily
            font.pixelSize: 16
        }

        TextField {
            id: field
            Layout.fillWidth: true
            color: Theme.on_surface
            selectionColor: Theme.primary
            selectedTextColor: Theme.on_primary
            placeholderTextColor: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 13
            selectByMouse: true
            leftPadding: 0
            rightPadding: 0
            background: Item {}
            Keys.onPressed: event => search.keyPressed(event)
        }

        // Clear.
        Text {
            visible: field.text !== ""
            text: String.fromCodePoint(0xF0156)   // close
            color: clearHover.hovered ? Theme.on_surface : Theme.on_surface_variant
            font.family: Theme.iconFontFamily
            font.pixelSize: 14
            HoverHandler {
                id: clearHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: {
                    field.text = "";
                    field.forceActiveFocus();
                }
            }
        }
    }
}
