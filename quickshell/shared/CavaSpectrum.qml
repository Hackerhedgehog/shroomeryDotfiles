import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "Visualizer.js" as Viz

// The output audio spectrum from cava: `bars` holds barCount values 0–1,
// bass first, while `active`. Each instance runs its own cava on a config
// generated in Paths.runtimeDir (one file per bar count and framerate).
// `failed` fires when cava can't start or quits within 2 s (not installed,
// no PipeWire).
Scope {
    id: root

    property int barCount: 24
    property int framerate: 30
    property bool active: false
    property var bars: []
    signal failed()

    readonly property string configPath: Paths.runtimeDir + "/cava-" + barCount + "-" + framerate + ".conf"
    readonly property string config: [
        "[general]", "bars = " + barCount, "framerate = " + framerate,
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10", "channels = mono"
    ].join("\n")
    property real startedAt: 0

    onActiveChanged: {
        if (active) {
            writer.running = true;
        } else {
            cava.running = false;
        }
    }
    Component.onCompleted: if (active) writer.running = true

    // Write the config (the runtime dir may not exist yet), then start cava.
    Process {
        id: writer
        command: ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$3"',
            "sh", Paths.runtimeDir, root.config, root.configPath]
        onExited: exitCode => {
            if (exitCode === 0 && root.active) {
                root.startedAt = Date.now();
                cava.running = true;
            }
        }
    }

    Process {
        id: cava
        command: ["cava", "-p", root.configPath]
        onRunningChanged: {
            if (running)
                return;
            root.bars = [];
            if (root.active && Date.now() - root.startedAt < 2000)
                root.failed();
        }
        stdout: SplitParser {
            onRead: data => root.bars = Viz.parseCavaFrame(data, 100)
        }
    }
}
