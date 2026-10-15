import QtQuick
import QtQuick.Controls
import qs.shared

// Pill-shaped text button. Neutral by default; `filled` for the primary
// action, `tonal` for a secondary emphasis. `compact` is the smaller size
// used in dense rows; `glyph` puts a Nerd Font icon before the text.
Button {
    id: control

    property bool filled: false
    property bool tonal: false
    property bool compact: false
    property string glyph: ""

    readonly property color foreground: filled ? Theme.on_primary
        : (tonal ? Theme.on_primary_container : Theme.on_surface)

    implicitHeight: compact ? 30 : 36
    leftPadding: compact ? 12 : 16
    rightPadding: compact ? 12 : 16
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45

    background: Rectangle {
        radius: height / 2
        color: control.filled ? Theme.primary
            : (control.tonal ? Theme.primary_container : Theme.surface_container_high)

        // Hover / press state layer.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: control.foreground
            opacity: control.down ? 0.16 : (control.hovered ? 0.08 : 0)
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Text {
                visible: control.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: control.glyph
                color: control.foreground
                font.family: Theme.iconFontFamily
                font.pixelSize: control.compact ? 14 : 16
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                color: control.foreground
                font.family: Theme.fontFamily
                font.pixelSize: control.compact ? 12 : 13
                font.bold: control.filled
            }
        }
    }
}
