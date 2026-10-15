import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.shared
import qs.VisualizerApp
import "VisualizerLogic.js" as Logic

// The visualizer overlay: transparent, click-through, above fullscreen
// windows, on the monitor visualizer mode started on. Created only while the
// mode is on, so cava and the screen-colors client run only then.
LazyLoader {
    active: VisualizerState.active

    PanelWindow {
        id: win

        screen: Array.from(Quickshell.screens).find(s => s.name === VisualizerState.monitorName) ?? null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:visualizer"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        CavaSpectrum {
            id: spectrum
            barCount: 96
            framerate: 60
            active: true
            onFailed: {
                Quickshell.execDetached(["notify-send", "-a", "Visualizer", "Visualizer mode",
                    "cava is not installed or could not start."]);
                VisualizerState.disable();
            }
        }

        ScreenColors {
            id: colors
            monitor: VisualizerState.monitorName
            source: VisualizerState.cfg.wallpaperOnly ? "wallpaper" : "screen"
            regions: Logic.visualizerRegions(VisualizerState.cfg, win.width, win.height)
        }

        VisualizerRenderer {
            anchors.fill: parent
            cfg: VisualizerState.cfg
            bars: spectrum.bars
            colors: colors.colors
            shape: colors.shape
            edges: colors.edges
        }
    }
}
