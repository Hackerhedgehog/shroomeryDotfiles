import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import qs.shared.ui
import qs.VisualizerApp
import "VisualizerLogic.js" as Logic

// The chosen monitor in miniature: its wallpaper and the live visualizer at
// scale (a demo spectrum while nothing plays). In the circle styles, drag the
// circle to move it and its edge to resize it; Center snaps it back.
Item {
    id: root

    property var cfg: Logic.normalizeSettings({})
    property real screenW: 1920
    property real screenH: 1080
    property var bars: []
    // While true (the setup panel is open), sample the real colors for the
    // preview from `monitor` with the working copy's regions and source.
    property bool live: false
    property string monitor: ""
    // A map of settings keys to new values (from dragging or Center).
    signal edited(var changes)

    implicitWidth: 480
    implicitHeight: Math.round(implicitWidth * screenH / screenW)

    readonly property real pxScale: width / screenW
    readonly property bool circle: cfg.style !== "border"
    readonly property string prefix: cfg.style === "center-in" ? "in" : "out"
    readonly property var geo: Logic.circleGeometry(cfg.style, cfg, screenW, screenH)

    property real t: 0
    Timer {
        interval: 33
        repeat: true
        running: root.visible && Logic.isSilent(root.bars)
        onTriggered: root.t += 0.033
    }

    // A still of the wallpaper (an animated one's first frame).
    FileView {
        id: wallpaperFile
        path: Paths.stillWallpaper
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    LazyLoader {
        id: previewColors
        active: root.live && root.monitor !== ""
        ScreenColors {
            monitor: root.monitor
            source: root.cfg.wallpaperOnly ? "wallpaper" : "screen"
            regions: Logic.visualizerRegions(root.cfg, root.screenW, root.screenH)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.surface_container_highest
        clip: true

        Image {
            anchors.fill: parent
            source: wallpaperFile.text().trim() !== "" ? "file://" + wallpaperFile.text().trim() : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 960
        }

        VisualizerRenderer {
            anchors.fill: parent
            cfg: root.cfg
            pxScale: root.pxScale
            bars: Logic.isSilent(root.bars) ? Logic.demoSpectrum(root.t, 96) : root.bars
            colors: previewColors.item ? previewColors.item.colors : []
            shape: previewColors.item ? previewColors.item.shape : ""
            edges: previewColors.item ? previewColors.item.edges : ({})
        }

        // The circle's outline and resize knob (circle styles only).
        Rectangle {
            visible: root.circle
            x: (root.geo.cx - root.geo.radius) * root.pxScale
            y: (root.geo.cy - root.geo.radius) * root.pxScale
            width: 2 * root.geo.radius * root.pxScale
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Theme.primary
            border.width: 1
            opacity: 0.7
        }
        Rectangle {
            visible: root.circle
            width: 12
            height: 12
            radius: 6
            x: (root.geo.cx + root.geo.radius) * root.pxScale - 6
            y: root.geo.cy * root.pxScale - 6
            color: Theme.primary
            border.color: Theme.on_primary
            border.width: 1
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.circle
        property string mode: ""
        property var grab: ({})
        cursorShape: mode !== "" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => {
            const x = mouse.x / root.pxScale, y = mouse.y / root.pxScale;
            mode = Logic.hitCircle(x, y, root.geo, 10 / root.pxScale);
            if (mode === "outside")
                mode = "";
            grab = mode === "inside"
                ? { dx: root.geo.cx - x, dy: root.geo.cy - y }
                : { cx: root.geo.cx, cy: root.geo.cy };
        }
        onPositionChanged: mouse => {
            if (mode !== "")
                root.edited(Logic.dragUpdate(mode, root.prefix, mouse.x / root.pxScale,
                    mouse.y / root.pxScale, grab, root.screenW, root.screenH));
        }
        onReleased: mode = ""
    }

    PanelButton {
        visible: root.circle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        compact: true
        text: "Center"
        onClicked: {
            const c = {};
            c[root.prefix + "X"] = 0.5;
            c[root.prefix + "Y"] = 0.5;
            root.edited(c);
        }
    }
}
