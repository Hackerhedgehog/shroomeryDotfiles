import QtQuick
import QtQuick.Effects
import qs.shared

// A monochrome SVG tinted with one theme color. Pass an absolute source URL
// (Paths.icon("name")) — a relative one would resolve against this file.
Image {
    id: icon

    property color color: Theme.primary
    property int size: 18

    width: size
    height: size
    sourceSize.width: size
    sourceSize.height: size
    fillMode: Image.PreserveAspectFit
    layer.enabled: source != ""
    layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: icon.color
    }
}
