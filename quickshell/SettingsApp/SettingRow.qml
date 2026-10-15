import QtQuick
import QtQuick.Layouts
import qs.shared

// One labelled settings row. Extra children (a ToggleSwitch, an ActionIcon
// with a menu) are laid out to the right of the label.
RowLayout {
    property string label: ""

    Layout.fillWidth: true

    Text {
        text: parent.label
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 16
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
}
