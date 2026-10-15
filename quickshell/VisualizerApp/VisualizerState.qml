pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.shared
import qs.shared.ui
import "VisualizerLogic.js" as Logic

// Visualizer mode: on/off (never saved; off after a reboot), the setup panel
// (Super+Alt+V), the monitor it runs on and the saved look (visualizer.json,
// normalized into `cfg`). While `active`, the status bar, dock and normal
// notification popups hide — they read this flag; nothing is written to
// their settings. The runtime flag file lets the Hyprland Super+arrow binds
// drive the visualizer.
Singleton {
    id: root

    property bool active: false
    property bool setupOpen: false
    property string monitorName: ""

    readonly property var cfg: Logic.normalizeSettings({
        style: saved.style, draw: saved.draw, monitor: saved.monitor,
        sensitivity: saved.sensitivity, barWidth: saved.barWidth,
        barSpacing: saved.barSpacing, lineWidth: saved.lineWidth,
        minLength: saved.minLength, outX: saved.outX, outY: saved.outY,
        outDiameter: saved.outDiameter, inX: saved.inX, inY: saved.inY,
        inDiameter: saved.inDiameter, smoothness: saved.smoothness, outline: saved.outline,
        wallpaperOnly: saved.wallpaperOnly
    })
    readonly property string style: cfg.style
    readonly property string draw: cfg.draw

    function focusedName(): string {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    function enable(): void {
        if (active)
            return;
        monitorName = Logic.pickMonitor(cfg.monitor,
            Array.from(Quickshell.screens).map(s => s.name), focusedName());
        setupOpen = false;
        PopoutState.close();
        active = true;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && : > "$2"', "sh",
            Paths.runtimeDir, Paths.visualizerFlag]);
    }

    function disable(): void {
        if (!active)
            return;
        active = false;
        Quickshell.execDetached(["rm", "-f", Paths.visualizerFlag]);
    }

    function openSetup(): void {
        if (active)
            return;
        PopoutState.close();
        setupOpen = true;
    }

    // Super+Alt+V: stop a running visualizer, else close or open the setup.
    function toggle(): void {
        const action = Logic.nextAction(active, setupOpen);
        if (action === "stop")
            disable();
        else if (action === "close")
            setupOpen = false;
        else
            openSetup();
    }

    // The setup panel's Start: save its working copy, then run.
    function start(work: var): void {
        const c = Logic.normalizeSettings(work);
        for (const key in c)
            saved[key] = c[key];
        settingsFile.writeAdapter();
        enable();
    }

    function cycleStyle(step: int): void {
        saved.style = Logic.cycle(Logic.STYLES, style, step);
        settingsFile.writeAdapter();
    }

    function cycleDraw(step: int): void {
        saved.draw = Logic.cycle(Logic.DRAWS, draw, step);
        settingsFile.writeAdapter();
    }

    // A flag left by a crash or reload must not keep Super+arrows captured.
    Component.onCompleted: Quickshell.execDetached(["rm", "-f", Paths.visualizerFlag])

    // Leave the mode when its monitor is unplugged.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.active && !Array.from(Quickshell.screens).some(s => s.name === root.monitorName))
                root.disable();
        }
    }

    FileView {
        id: settingsFile
        path: Paths.visualizerSettings
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: saved
            property string style: "center-out"
            property string draw: "bars"
            property string monitor: ""
            property real sensitivity: 1.0
            property real barWidth: 3
            property real barSpacing: 2
            property real lineWidth: 3
            property real minLength: 4
            property real outX: 0.5
            property real outY: 0.5
            property real outDiameter: 0.24
            property real inX: 0.5
            property real inY: 0.5
            property real inDiameter: 0.9
            property real smoothness: 0.5
            property real outline: 1.5
            property bool wallpaperOnly: false
        }
    }

    IpcHandler {
        target: "visualizer"
        function toggle(): void { root.toggle(); }
        function enable(): void { root.enable(); }
        function disable(): void { root.disable(); }
        function isActive(): bool { return root.active; }
        function setup(): void { root.openSetup(); }
        function nextStyle(): void { root.cycleStyle(1); }
        function prevStyle(): void { root.cycleStyle(-1); }
        function nextMode(): void { root.cycleDraw(1); }
        function prevMode(): void { root.cycleDraw(-1); }
    }
}
