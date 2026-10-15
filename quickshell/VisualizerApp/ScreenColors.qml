import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "VisualizerLogic.js" as Logic

// Client of the shroomery screen-colors daemon, protocol v2
// (screencolors/README.md): subscribes to `regions` on `monitor` from
// `source` ("screen" or "wallpaper"), and exposes region "viz". Starts the
// daemon when needed (with backoff) and keeps the last colors while the
// connection is down.
Scope {
    id: root

    property string monitor: ""
    property string source: "screen"
    property var regions: []

    property var colors: []
    property string average: ""
    readonly property string shape: regions.length > 0 ? regions[0].shape : ""
    readonly property var edges: shape === "edges" ? regions[0] : ({})
    readonly property bool connected: link.item ? link.item.connected : false
    property bool warned: false
    property string lastError: ""

    // The subscription; sent on connect, and 150 ms after it last changed
    // (so dragging the circle doesn't flood the daemon).
    readonly property string wanted: JSON.stringify({ v: 2, type: "subscribe", monitor: monitor,
        source: source, regions: regions })
    property string sent: ""
    onWantedChanged: debounce.restart()
    // `from`: the socket calling in from its own onConnectedChanged, where
    // link.item isn't set yet (the loader publishes it afterwards).
    function sendSubscription(from: var): void {
        const sock = from || link.item;
        if (!sock || !sock.connected || monitor === "" || regions.length === 0 || wanted === sent)
            return;
        sock.write(wanted + "\n");
        sock.flush();
        sent = wanted;
    }
    Timer {
        id: debounce
        interval: 150
        onTriggered: root.sendSubscription(null)
    }

    // The daemon is started detached, so no client owns it: closing the
    // setup preview must not take the overlay's daemon down with it. A
    // second copy exits at once while one is running, so starting it is
    // always safe.
    function startDaemon(): void {
        Quickshell.execDetached([Paths.screenColors]);
    }
    Component.onCompleted: startDaemon()

    // After an error (an invalid or refused subscription, "monitor gone",
    // hyprctl briefly unavailable) subscribe again a little later.
    Timer {
        id: resubscribe
        interval: 3000
        onTriggered: root.sendSubscription(null)
    }

    // A Socket makes one connection attempt: after a refusal (the daemon not
    // listening yet) it never tries again, so every retry gets a new one.
    LazyLoader {
        id: link
        active: false

        Socket {
            id: socket
            path: Paths.screenColorsSocket
            connected: true
            onConnectedChanged: {
                if (!connected)
                    return;
                root.sent = "";
                root.sendSubscription(socket);
            }
            parser: SplitParser {
                onRead: line => {
                    let f;
                    try {
                        f = JSON.parse(line);
                    } catch (e) {
                        return;
                    }
                    if (f.type === "error") {
                        if (f.message !== root.lastError)
                            console.warn("visualizer: screen-colors: " + f.message);
                        root.lastError = f.message;
                        root.sent = "";
                        resubscribe.restart();
                        return;
                    }
                    const r = f.type === "frame" && f.regions ? f.regions.viz : null;
                    if (!r || !Array.isArray(r.colors))
                        return;
                    root.colors = r.colors;
                    root.average = r.average || "";
                }
            }
        }
    }

    // (Re)connect every 500 ms, restarting the daemon (with backoff) if it is gone.
    Timer {
        interval: 500
        repeat: true
        running: !root.connected
        property int attempts: 0
        onTriggered: {
            attempts++;
            if (attempts === 7 && !root.warned) {
                root.warned = true;
                console.warn("visualizer: no screen-colors daemon at " + Paths.screenColorsSocket + "; using theme colors");
            }
            if (Logic.restartDue(attempts))
                root.startDaemon();
            link.active = false;
            link.active = true;
        }
        onRunningChanged: if (!running) attempts = 0
    }
}
