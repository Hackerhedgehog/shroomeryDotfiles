import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.shared
import qs.DashboardPanel
import "../shared/Visualizer.js" as Viz

// Cover art cut to a circle with a thin ring around it, and a music note
// when there is none (the Dash media card and the Media tab). Around it, the
// output audio spectrum (Cava) while `live`.
Item {
    id: art

    property string source: ""
    // Diameter of the art; the spectrum ring takes `ringRoom` more each side.
    property int size: 120
    // Show the spectrum (the tab is showing).
    property bool live: false

    readonly property real ringGap: 5
    readonly property real barMax: 16
    readonly property real ringRoom: ringGap + barMax

    implicitWidth: size + 2 * ringRoom
    implicitHeight: implicitWidth

    onLiveChanged: Cava.consumers = Math.max(0, Cava.consumers + (live ? 1 : -1))
    Component.onDestruction: if (live) Cava.consumers = Math.max(0, Cava.consumers - 1)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: art.live ? 0.85 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        ShapePath {
            strokeColor: Theme.primary
            strokeWidth: 3
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg {
                path: Viz.ringPath(Viz.mirrorBars(Cava.bars, 2, art.barMax),
                    art.width / 2, art.height / 2, art.size / 2 + art.ringGap)
            }
        }
    }

    Item {
        id: disc
        x: art.ringRoom
        y: art.ringRoom
        width: art.size
        height: art.size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.surface_container_high

            Text {
                anchors.centerIn: parent
                visible: image.status !== Image.Ready
                text: String.fromCodePoint(0xF0387)   // md-music_note
                color: Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: Math.round(art.size / 3)
            }
        }

        Image {
            id: image
            anchors.fill: parent
            source: art.source
            sourceSize.width: art.size * 2
            sourceSize.height: art.size * 2
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        // Thin primary ring around the art.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Theme.primary
            border.width: 2
        }

        Rectangle {
            id: mask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }
    }
}
