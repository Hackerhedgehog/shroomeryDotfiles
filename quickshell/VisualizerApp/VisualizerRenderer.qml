import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "VisualizerLogic.js" as Logic

// The visualizer, drawn on the GPU (shaders/visualizer.frag): the mirrored
// spectrum (`bars`, 0–1 per band, bass first) in cfg.style / cfg.draw,
// colored by the sampled region (`colors`: ring sectors or edge zones) as seen
// from the circle's center. Full size in the overlay; the setup panel's
// preview sets pxScale so every px setting shrinks with it.
Item {
    id: root

    property var cfg: Logic.normalizeSettings({})
    property var bars: []
    // Protocol v2 region "viz": ring sector colors, or edge zone colors.
    property var colors: []
    property string shape: ""
    property var edges: ({})
    property real pxScale: 1

    readonly property real screenW: width / pxScale
    readonly property real screenH: height / pxScale
    readonly property var geo: Logic.circleGeometry(cfg.style, cfg, screenW, screenH)
    // Read straight from the inputs: inside onColorsChanged a binding on
    // them may not have caught up yet (closing the preview empties colors).
    function hasColors(): bool {
        return colors.length > 0
            && (shape === "ring" || (shape === "edges" && colors.length === Logic.zoneCount(edges)));
    }
    // One half, bass first, smoothed across bands: the shader mirrors it
    // around the circle / edge.
    readonly property var spectrumValues: Logic.smoothSpectrum(bars, cfg.smoothness)
    onSpectrumValuesChanged: spectrumCanvas.requestPaint()

    // The color ring is rebuilt only when its inputs change: the daemon sends
    // 30 frames a second, but a still picture repeats the same colors.
    property var ringStops: []
    property string ringKey: ""
    readonly property string themeKey: Theme.primary.toString() + Theme.tertiary.toString()
    function updateRing() {
        const key = (hasColors() ? colors.join("") + shape : themeKey) + "|" + Math.round(geo.cx) + ","
            + Math.round(geo.cy) + "|" + Math.round(screenW) + "x" + Math.round(screenH);
        if (key === ringKey)
            return;
        ringKey = key;
        ringStops = !hasColors()
            ? Logic.fallbackStops(Theme.primary.toString(), Theme.tertiary.toString())
            : shape === "ring"
                ? Logic.ringStopsFromSectors(colors.map(c => Logic.readable(c)))
                : Logic.gradientStops(edges, colors.map(c => Logic.readable(c)), screenW, screenH, geo.cx, geo.cy);
        ringCanvas.requestPaint();
    }
    onColorsChanged: updateRing()
    onShapeChanged: updateRing()
    onGeoChanged: updateRing()
    onThemeKeyChanged: updateRing()
    Component.onCompleted: updateRing()

    // Fill a 1-px-high canvas with gradient stops in one call: Canvas
    // interpolates between them in C++ (per-pixel ImageData writes from JS
    // don't reach the texture in Quickshell's Canvas, and fillRect per texel
    // costs too much at 30–60 Hz).
    function fillStops(canvas, stops) {
        const ctx = canvas.getContext("2d");
        const g = ctx.createLinearGradient(0, 0, canvas.width, 0);
        for (let i = 0; i < stops.length; i++)
            g.addColorStop(stops[i].position, stops[i].color);
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, canvas.width, 1);
    }

    // Data textures, drawn by JS and sampled by the shader (linear filtering
    // blends neighbours). They must stay visible: hideSource keeps them off
    // screen, and a hidden Canvas never paints.
    Canvas {
        id: spectrumCanvas
        width: Math.max(2, root.spectrumValues.length)
        height: 1
        renderStrategy: Canvas.Immediate
        onPaint: root.fillStops(spectrumCanvas, Logic.spectrumStops(root.spectrumValues))
    }

    Canvas {
        id: ringCanvas
        width: 360
        height: 1
        renderStrategy: Canvas.Immediate
        onPaint: root.fillStops(ringCanvas, root.ringStops)
    }

    ShaderEffectSource { id: spectrumSource; sourceItem: spectrumCanvas; hideSource: true; live: true; smooth: true; visible: false }
    ShaderEffectSource { id: ringSource; sourceItem: ringCanvas; hideSource: true; live: true; smooth: true; visible: false }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        // Without its .qsb the effect falls back to Qt's default shader.
        visible: !root.shaderMissing
        property var spectrum: spectrumSource
        property var ring: ringSource
        property real itemW: width
        property real itemH: height
        property real style: Logic.STYLES.indexOf(root.cfg.style)
        property real drawMode: Logic.DRAWS.indexOf(root.cfg.draw)
        property real cx: root.geo.cx * root.pxScale
        property real cy: root.geo.cy * root.pxScale
        property real radius: root.geo.radius * root.pxScale
        property real maxLen: root.geo.maxLen * root.pxScale
        property real minLen: root.cfg.minLength * root.pxScale
        property real barWidth: root.cfg.barWidth * root.pxScale
        property real barSpacing: root.cfg.barSpacing * root.pxScale
        property real lineWidth: root.cfg.lineWidth * root.pxScale
        property real sensitivity: root.cfg.sensitivity
        property real bands: Math.max(2, root.spectrumValues.length)
        property real outline: root.cfg.outline * root.pxScale
        fragmentShader: Qt.resolvedUrl("shaders/visualizer.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("visualizer shader: " + log)
    }

    // A missing .qsb leaves the effect Uncompiled rather than in Error, so
    // check the file itself.
    property bool shaderMissing: false
    FileView {
        path: Quickshell.shellPath("VisualizerApp/shaders/visualizer.frag.qsb")
        printErrors: false
        onLoaded: root.shaderMissing = false
        onLoadFailed: {
            root.shaderMissing = true;
            console.warn("visualizer shader: " + path + " is missing; run VisualizerApp/shaders/build.sh");
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.shaderMissing || shader.status === ShaderEffect.Error
        text: "Visualizer shader missing — run VisualizerApp/shaders/build.sh"
        color: Theme.on_surface
        font.family: Theme.fontFamily
        font.pixelSize: 14
    }
}
