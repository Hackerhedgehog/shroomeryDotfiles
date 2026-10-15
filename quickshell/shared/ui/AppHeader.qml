import QtQuick
import QtQuick.Layouts
import qs.shared

// Heading of an app window: a round badge with a Nerd Font glyph, the title
// and a one-line subtitle. Extra children (a StatusChip, ActionIcons, a
// SearchField) are laid out on the right.
RowLayout {
    id: header

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property color subtitleColor: Theme.on_surface_variant

    default property alias trailing: trailingRow.data

    Layout.fillWidth: true
    spacing: 14

    Rectangle {
        visible: header.glyph !== ""
        implicitWidth: 44
        implicitHeight: 44
        radius: 22
        color: Theme.primary_container

        Text {
            anchors.centerIn: parent
            text: header.glyph
            color: Theme.on_primary_container
            font.family: Theme.iconFontFamily
            font.pixelSize: 22
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
            Layout.fillWidth: true
            text: header.title
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: header.subtitle
            color: header.subtitleColor
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailingRow
        spacing: 8
    }
}
