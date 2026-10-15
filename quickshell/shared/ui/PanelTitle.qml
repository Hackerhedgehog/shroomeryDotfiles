import QtQuick
import QtQuick.Layouts
import qs.shared

// Panel heading: a large title with an optional one-line subtitle.
ColumnLayout {
    property string title: ""
    property string subtitle: ""

    Layout.fillWidth: true
    spacing: 2

    Text {
        text: parent.title
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.bold: true
    }
    Text {
        visible: text !== ""
        text: parent.subtitle
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
