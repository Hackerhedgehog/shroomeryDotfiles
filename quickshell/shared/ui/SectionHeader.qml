import QtQuick
import QtQuick.Layouts
import qs.shared

// Bold primary heading for a group of rows. Extra children (e.g. an
// ActionIcon) are laid out to the right of the label.
// With `collapsible` a chevron follows the label and a click on the label
// flips `expanded`; the caller hides its rows while it is false.
RowLayout {
    id: header
    property string label: ""
    property bool collapsible: false
    property bool expanded: true

    Layout.fillWidth: true
    Layout.topMargin: 6

    Text {
        text: header.collapsible ? header.label + "  " + (header.expanded ? "▾" : "▸") : header.label
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        Layout.fillWidth: true
        wrapMode: Text.Wrap

        MouseArea {
            anchors.fill: parent
            enabled: header.collapsible
            cursorShape: Qt.PointingHandCursor
            onClicked: header.expanded = !header.expanded
        }
    }
}
