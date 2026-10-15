import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Pipewire
import qs.shared
import qs.shared.ui
import "../shared/Visualizer.js" as Viz

// A round volume bubble on the Dash tab: a PipeWire node's volume % and icon,
// circled by a thin ring of ticks that ripple with its live level
// (Visualizer.js). Wheel: ±1 %, click: mute / unmute.
Item {
    id: bubble

    property PwNode node: null
    property string iconName: ""
    property string mutedIconName: ""
    property string label: ""
    // Run the level ring (the Dash tab is showing).
    property bool live: false

    readonly property bool ready: node !== null && node.ready && node.audio !== null
    readonly property bool muted: ready && node.audio.muted
    readonly property int percent: ready ? Math.round(node.audio.volume * 100) : 0
    readonly property real stepSize: 0.01

    readonly property int tickCount: 48
    readonly property real coreSize: 56
    readonly property real ringGap: 4
    readonly property real tickMax: 10
    readonly property real ringSize: coreSize + 2 * (ringGap + tickMax) + 4
    property var history: []

    implicitWidth: ringSize
    implicitHeight: ringSize + labelText.implicitHeight + 2

    // Keep the node's audio properties live and writable.
    PwObjectTracker { objects: bubble.node ? [bubble.node] : [] }

    // Costs a PipeWire stream: only while visible. Never on a muted node — the
    // capture stream wakes the device even when muted (a mic with hardware
    // sidetone would start playing back).
    PwNodePeakMonitor {
        id: peakMonitor
        node: bubble.node
        enabled: bubble.live && bubble.node !== null && !bubble.muted
    }

    Timer {
        interval: 50
        repeat: true
        running: bubble.live
        onTriggered: bubble.history = Viz.pushLevel(bubble.history,
            bubble.muted ? 0 : peakMonitor.peak, Viz.historySize(bubble.tickCount))
    }
    onLiveChanged: if (!live) history = []

    function setVolume(v: real): void {
        if (!bubble.ready)
            return;
        bubble.node.audio.muted = false;
        bubble.node.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute(): void {
        if (bubble.ready)
            bubble.node.audio.muted = !bubble.node.audio.muted;
    }

    Shape {
        width: bubble.ringSize
        height: bubble.ringSize
        preferredRendererType: Shape.CurveRenderer
        opacity: bubble.muted ? 0.2 : 0.5

        ShapePath {
            strokeColor: Theme.primary
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg {
                path: Viz.ringPath(Viz.tickLengths(bubble.history, bubble.tickCount, 1.5, bubble.tickMax),
                    bubble.ringSize / 2, bubble.ringSize / 2, bubble.coreSize / 2 + bubble.ringGap)
            }
        }
    }

    Rectangle {
        id: core
        x: (bubble.ringSize - width) / 2
        y: x
        width: bubble.coreSize
        height: width
        radius: width / 2
        color: bubble.muted ? Theme.surface_container_high
            : (mouse.containsMouse ? Theme.primary : Theme.primary_container)
        Behavior on color { ColorAnimation { duration: 200 } }

        Column {
            anchors.centerIn: parent
            spacing: 0
            ColoredIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: Paths.icon(bubble.muted ? bubble.mutedIconName : bubble.iconName)
                size: 18
                color: bubble.muted ? Theme.outline
                    : (mouse.containsMouse ? Theme.on_primary : Theme.on_primary_container)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bubble.muted ? "Muted" : bubble.percent + "%"
                color: bubble.muted ? Theme.outline
                    : (mouse.containsMouse ? Theme.on_primary : Theme.on_primary_container)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bubble.toggleMute()
            onWheel: wheel => {
                if (bubble.ready)
                    bubble.setVolume(bubble.node.audio.volume + (wheel.angleDelta.y > 0 ? 1 : -1) * bubble.stepSize);
            }
        }
    }

    Text {
        id: labelText
        y: bubble.ringSize + 2
        width: bubble.ringSize
        horizontalAlignment: Text.AlignHCenter
        text: bubble.label
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
