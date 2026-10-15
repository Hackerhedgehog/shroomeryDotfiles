import QtQuick
import QtQuick.Shapes
import qs.shared

// A 270° ring for a 0–1 value with the value text in the middle and a label
// below (CPU / RAM / Disk on the Dash tab).
Item {
    id: gauge

    property real value: 0
    property string centerText: ""
    property string label: ""
    property real shown: Math.max(0, Math.min(1, value))
    Behavior on shown {
        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
    }

    implicitWidth: 64
    implicitHeight: 64 + labelText.implicitHeight + 4

    Shape {
        width: 64
        height: 64
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.surface_container_highest
            strokeWidth: 6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 32; centerY: 32; radiusX: 28; radiusY: 28; startAngle: 135; sweepAngle: 270 }
        }
        ShapePath {
            strokeColor: Theme.primary
            strokeWidth: 6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 32; centerY: 32; radiusX: 28; radiusY: 28; startAngle: 135; sweepAngle: 270 * gauge.shown }
        }
    }

    Text {
        x: 0
        width: 64
        y: 22
        horizontalAlignment: Text.AlignHCenter
        text: gauge.centerText
        color: Theme.on_surface
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
    }

    Text {
        id: labelText
        y: 68
        width: 64
        horizontalAlignment: Text.AlignHCenter
        text: gauge.label
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
