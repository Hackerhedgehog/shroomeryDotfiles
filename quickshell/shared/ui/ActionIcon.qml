import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.shared

// Flat round icon button with a hover bubble. Use iconSrc for an SVG (tinted
// primary, pass an absolute URL such as Paths.icon("settings")) or iconTxt
// for a glyph (Nerd Font glyphs are drawn with Theme.iconFontFamily).
Button {
    id: control

    property string iconSrc: ""
    property string iconTxt: ""
    property color iconColor: Theme.primary
    property int iconPixelSize: 16

    // Private-use code points (Nerd Font icons), BMP or plane 15.
    readonly property bool nerdGlyph: /[-]|[\uDB80-\uDBFF]/.test(iconTxt)

    implicitWidth: 28
    implicitHeight: 28
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        radius: Math.min(width, height) / 2
        color: Theme.on_surface
        opacity: control.down ? 0.14 : (control.hovered ? 0.08 : 0)
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    contentItem: Item {
        Text {
            anchors.centerIn: parent
            text: control.iconTxt
            visible: control.iconSrc === ""
            color: control.iconColor
            font.family: control.nerdGlyph ? Theme.iconFontFamily : Theme.fontFamily
            font.pixelSize: control.iconPixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        ColoredIcon {
            anchors.centerIn: parent
            visible: control.iconSrc !== ""
            source: control.iconSrc
            color: control.iconColor
        }
    }
}
