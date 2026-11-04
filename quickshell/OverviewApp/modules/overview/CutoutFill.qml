import QtQuick
import QtQuick.Effects
import "../../common"
import "../../common/widgets"

// A workspace tile's fill with its label cut out of it: the number (or "S")
// is a hole that shows what lies under the tile, the card's blurred
// wallpaper, rather than text drawn on top. Fills its parent; inset it by the
// tile's border width so the border stays visible.
Item {
    id: fill

    property color color
    property real radius
    property string text
    property real pixelSize

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        radius: fill.radius
        color: fill.color
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: label
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: label
        anchors.fill: parent
        visible: false
        layer.enabled: true

        StyledText {
            anchors.centerIn: parent
            text: fill.text
            font {
                pixelSize: fill.pixelSize
                weight: Font.DemiBold
                family: Appearance.font.family.expressive
            }
            color: "white"
        }
    }
}
