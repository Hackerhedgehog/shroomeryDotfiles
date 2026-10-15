import QtQuick
import QtQuick.Layouts
import qs.shared

// One setting: its label (and an optional hint under it) on the left, its
// control(s) on the right. Give a FieldCombo Layout.preferredWidth.
RowLayout {
    id: row

    property string label: ""
    property string hint: ""

    default property alias controls: controlRow.data

    Layout.fillWidth: true
    spacing: 12

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
            Layout.fillWidth: true
            text: row.label
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: row.hint
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }

    RowLayout {
        id: controlRow
        spacing: 8
    }
}
