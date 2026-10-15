import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.shared
import qs.StatusbarApp
import "BarGeometry.js" as Geo

// The status bar's background: the pill and the open popout panel as one
// outline (BarGeometry.barPath) — a vertical gradient border from
// statusbar.json (border.*, empty = theme primary → on_primary), the
// background fill inside it, and the drop shadow. Covers only the shape's
// bounding box so the shadow layer stays small.
Item {
    id: shape

    required property Item pill
    required property Item host
    // statusbar.json opacity.collapsed / opacity.expanded, set by the bar.
    property real fillOpacity: 1

    readonly property real borderWidth: StatusbarState.settings.border.width
    readonly property bool panelShown: host.panelH > 0.5
    readonly property real shapeLeft: Math.min(pill.x, panelShown ? host.panelX : pill.x)
    readonly property real shapeRight: Math.max(pill.x + pill.width, panelShown ? host.panelX + host.panelW : 0)

    x: shapeLeft
    y: pill.y
    width: shapeRight - shapeLeft
    height: pill.height + host.panelH

    readonly property var geometry: ({
        pillX: pill.x - shapeLeft,
        pillY: 0,
        pillW: pill.width,
        pillH: pill.height,
        pillR: StatusbarState.settings.pill.radius,
        panelX: host.panelX - shapeLeft,
        panelW: host.panelW,
        panelH: host.panelH,
        joinR: 12,
        bottomR: 16
    })

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 1.0
        blurMax: 15
        shadowColor: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
        autoPaddingEnabled: true
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: shape.fillOpacity

        // Border: the whole outline in the gradient...
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: shape.height
                GradientStop {
                    position: 0.0
                    color: StatusbarState.settings.border.colorTop !== ""
                        ? StatusbarState.settings.border.colorTop : Theme.primary
                }
                GradientStop {
                    position: 1.0
                    color: StatusbarState.settings.border.colorBottom !== ""
                        ? StatusbarState.settings.border.colorBottom : Theme.on_primary
                }
            }
            PathSvg { path: Geo.barPath(shape.geometry, 0) }
        }

        // ...and the fill inside it, inset by the border width.
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: Theme.background
            PathSvg { path: Geo.barPath(shape.geometry, shape.borderWidth) }
        }
    }
}
