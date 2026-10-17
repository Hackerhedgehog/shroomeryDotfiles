pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.shared.ui

// Live audio state. Devices, streams, volumes and mutes come from the
// PipeWire service (reactive, no polling). Card profiles and ports are not
// exposed by that API, so they are read and written through `pactl -f json`.

Singleton {
    id: root

    readonly property real maxVolume: 1.5

    // The dynamic-loudness chain's own node names. Kept here as literals
    // rather than imported from Loudness.js: a singleton that the whole shell
    // depends on should not pull in the loudness feature's code. They are
    // declared once so the two filters below cannot drift apart.
    readonly property string _loudnessSinkName: "dynamic_loudness"
    readonly property string _loudnessStreamName: "output.dynamic_loudness"

    // Whether the audio panel is open in the status bar (one flag for all
    // monitors' panel instances, so moving between monitors can't race it).
    readonly property bool panelOpen: PopoutState.currentName === "audio"
    property string errorMessage: ""

    // pactl-derived data, keyed so it can be joined back onto PipeWire nodes.
    property var cards: []
    property var deviceInfo: ({})
    property bool pactlLoaded: false

    readonly property bool ready: Pipewire.ready
    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []

    // A node only publishes volume/mute while something holds it, so keep the
    // whole set bound for as long as the shell runs.
    PwObjectTracker {
        objects: root.allNodes
    }

    // The dynamic-loudness virtual sink is plumbing, not a device anyone picks
    // from this list — the Loudness card owns it and names the real device it
    // feeds. Showing it here would put a phantom device next to real ones.
    readonly property var sinks: root.allNodes.filter(n => n.audio && n.isSink && !n.isStream && n.name !== root._loudnessSinkName)
    readonly property var sources: root.allNodes.filter(n => n.audio && !n.isSink && !n.isStream)
    // The chain's playback stream is plumbing too: left in, it would appear
    // in the Mixer tab as a phantom app whose slider scales everything.
    readonly property var outputStreams: root.allNodes.filter(n => n.audio && n.isStream && n.isSink && !root.isMonitorStream(n) && n.name !== root._loudnessStreamName)
    readonly property var inputStreams: root.allNodes.filter(n => n.audio && n.isStream && !n.isSink && !root.isMonitorStream(n))

    // Level meters (ours included) attach as monitor capture streams. They are
    // plumbing, not something anyone wants a volume slider for.
    function isMonitorStream(node) {
        const props = node.properties || {};
        return props["stream.monitor"] === "true" || props["media.category"] === "Monitor";
    }

    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property var defaultSource: Pipewire.defaultAudioSource

    // ---------------------------------------------------------------- naming

    function displayName(node) {
        if (!node)
            return "";
        if (node.isStream) {
            const props = node.properties || {};
            return props["application.name"] || props["media.name"] || node.description || node.name || "Unknown app";
        }
        return node.description || node.nickname || node.name || "";
    }

    function streamDetail(node) {
        if (!node)
            return "";
        const props = node.properties || {};
        const media = props["media.name"] || "";
        const binary = props["application.process.binary"] || "";
        if (media !== "" && media !== root.displayName(node))
            return media;
        return binary;
    }

    function describeDevice(node) {
        if (!node)
            return "";
        const parts = [];
        const info = root.deviceInfo[node.name];
        if (info && info.activePortDescription)
            parts.push(info.activePortDescription);
        else if (node.nickname && node.nickname !== node.description)
            parts.push(node.nickname);
        const channels = node.audio ? node.audio.channels.length : 0;
        if (channels === 1)
            parts.push("Mono");
        else if (channels === 2)
            parts.push("Stereo");
        else if (channels > 2)
            parts.push(channels + " channels");
        return parts.join(" · ");
    }

    function isDefaultSink(node) {
        return !!node && !!root.defaultSink && node.id === root.defaultSink.id;
    }

    function isDefaultSource(node) {
        return !!node && !!root.defaultSource && node.id === root.defaultSource.id;
    }

    // --------------------------------------------------------------- volumes

    function volumeOf(node) {
        return node && node.audio ? node.audio.volume : 0;
    }

    function setVolume(node, value) {
        if (!node || !node.audio)
            return;
        node.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function isMuted(node) {
        return !!(node && node.audio && node.audio.muted);
    }

    function setMuted(node, muted) {
        if (node && node.audio)
            node.audio.muted = muted;
    }

    function toggleMute(node) {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    function volumePercent(node) {
        return Math.round(root.volumeOf(node) * 100);
    }

    // ---------------------------------------------------------------- balance

    // Index of the front-left/front-right channels, or null when the node is
    // not a plain stereo node (mono and surround have no meaningful balance).
    function stereoIndices(node) {
        if (!node || !node.audio)
            return null;
        const channels = node.audio.channels;
        if (!channels || channels.length !== 2)
            return null;
        const left = channels.indexOf(PwAudioChannel.FrontLeft);
        const right = channels.indexOf(PwAudioChannel.FrontRight);
        if (left < 0 || right < 0)
            return null;
        return {
            "left": left,
            "right": right
        };
    }

    function supportsBalance(node) {
        return root.stereoIndices(node) !== null;
    }

    // -1 is hard left, 0 centered, 1 hard right.
    function balanceOf(node) {
        const idx = root.stereoIndices(node);
        if (!idx)
            return 0;
        const volumes = node.audio.volumes;
        const left = volumes[idx.left];
        const right = volumes[idx.right];
        const peak = Math.max(left, right);
        if (peak <= 0)
            return 0;
        return (right - left) / peak;
    }

    function setBalance(node, balance) {
        const idx = root.stereoIndices(node);
        if (!idx)
            return;
        const volumes = node.audio.volumes.slice();
        const peak = Math.max(volumes[idx.left], volumes[idx.right]);
        volumes[idx.left] = peak * (balance <= 0 ? 1 : 1 - balance);
        volumes[idx.right] = peak * (balance >= 0 ? 1 : 1 + balance);
        node.audio.volumes = volumes;
    }

    // -------------------------------------------------------- default device

    function selectSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    function selectSource(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }

    // ------------------------------------------------------ profiles & ports

    function cardForNode(node) {
        if (!node)
            return null;
        const info = root.deviceInfo[node.name];
        if (!info)
            return null;
        for (let i = 0; i < root.cards.length; i++) {
            const card = root.cards[i];
            if (info.deviceId !== "" && card.objectId === info.deviceId)
                return card;
        }
        // Bluetooth and some virtual devices do not carry device.id; fall back
        // to the ALSA card number, which is unique per physical card.
        for (let j = 0; j < root.cards.length; j++) {
            const card = root.cards[j];
            if (info.alsaCard !== "" && card.alsaCard === info.alsaCard)
                return card;
        }
        return null;
    }

    function profilesForNode(node) {
        const card = root.cardForNode(node);
        return card ? card.profiles : [];
    }

    function activeProfileForNode(node) {
        const card = root.cardForNode(node);
        return card ? card.activeProfile : "";
    }

    function portsForNode(node) {
        const info = root.deviceInfo[node ? node.name : ""];
        return info ? info.ports : [];
    }

    function activePortForNode(node) {
        const info = root.deviceInfo[node ? node.name : ""];
        return info ? info.activePort : "";
    }

    function setCardProfile(node, profile) {
        const card = root.cardForNode(node);
        if (!card || profile === "")
            return;
        root._runAction(["pactl", "set-card-profile", card.name, profile], "Could not switch the card profile.");
    }

    function setPort(node, port) {
        if (!node || port === "")
            return;
        const verb = node.isSink ? "set-sink-port" : "set-source-port";
        root._runAction(["pactl", verb, node.name, port], "Could not switch the port.");
    }

    // ------------------------------------------------------------- refreshing

    function refresh() {
        root._loadCards();
        root._loadDevices(true);
        root._loadDevices(false);
    }

    function _loadCards() {
        if (cardsProc.running)
            return;
        cardsProc.command = ["pactl", "-f", "json", "list", "cards"];
        cardsProc.running = true;
    }

    function _loadDevices(isSink) {
        const proc = isSink ? sinksProc : sourcesProc;
        if (proc.running)
            return;
        proc.command = ["pactl", "-f", "json", "list", isSink ? "sinks" : "sources"];
        proc.running = true;
    }

    function _runAction(command, failureMessage) {
        actionProc.pendingMessage = failureMessage;
        actionProc.command = command;
        actionProc.running = true;
    }

    function _ingestCards(text) {
        let parsed = [];
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            root.errorMessage = "Could not read card list from pactl.";
            return;
        }
        const list = [];
        for (let i = 0; i < parsed.length; i++) {
            const card = parsed[i];
            const props = card.properties || {};
            const profiles = [];
            for (const key in card.profiles) {
                const profile = card.profiles[key];
                if (profile.available === false)
                    continue;
                profiles.push({
                    "name": key,
                    "description": profile.description || key
                });
            }
            list.push({
                "index": card.index,
                "name": card.name,
                "description": props["device.description"] || card.name,
                "objectId": String(props["object.id"] || ""),
                "alsaCard": String(props["api.alsa.card"] || ""),
                "activeProfile": card.active_profile || "",
                "profiles": profiles
            });
        }
        root.cards = list;
        root.pactlLoaded = true;
    }

    function _ingestDevices(text, isSink) {
        let parsed = [];
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            root.errorMessage = "Could not read device list from pactl.";
            return;
        }
        // Rebuild into a fresh object so bindings on deviceInfo re-evaluate.
        const map = {};
        for (const existing in root.deviceInfo) {
            map[existing] = root.deviceInfo[existing];
        }
        for (let i = 0; i < parsed.length; i++) {
            const device = parsed[i];
            const props = device.properties || {};
            const ports = [];
            let activeDescription = "";
            const rawPorts = device.ports || [];
            for (let p = 0; p < rawPorts.length; p++) {
                const port = rawPorts[p];
                if (port.availability === "not available")
                    continue;
                ports.push({
                    "name": port.name,
                    "description": port.description || port.name
                });
                if (port.name === device.active_port)
                    activeDescription = port.description || port.name;
            }
            map[device.name] = {
                "isSink": isSink,
                "deviceId": String(props["device.id"] || ""),
                "alsaCard": String(props["alsa.card"] || ""),
                "ports": ports,
                "activePort": device.active_port || "",
                "activePortDescription": activeDescription
            };
        }
        root.deviceInfo = map;
    }

    Process {
        id: cardsProc
        stdout: StdioCollector {
            id: cardsOut
            onStreamFinished: root._ingestCards(cardsOut.text)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: sinksProc
        stdout: StdioCollector {
            id: sinksOut
            onStreamFinished: root._ingestDevices(sinksOut.text, true)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: sourcesProc
        stdout: StdioCollector {
            id: sourcesOut
            onStreamFinished: root._ingestDevices(sourcesOut.text, false)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: actionProc
        property string pendingMessage: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                const detail = actionErr.text.trim();
                root.errorMessage = detail !== "" ? detail : actionProc.pendingMessage;
            } else {
                root.errorMessage = "";
            }
            root.refresh();
        }
    }

    // Profiles and ports can change underneath us (docking, plugging in
    // headphones), and pactl gives us no change signal, so poll while visible.
    Timer {
        running: root.panelOpen
        interval: 3000
        repeat: true
        onTriggered: root.refresh()
    }

    onPanelOpenChanged: {
        if (root.panelOpen) {
            root.errorMessage = "";
            root.refresh();
        }
    }

    // A device appearing or disappearing changes the pactl picture too.
    onSinksChanged: {
        if (root.panelOpen)
            root.refresh();
    }

    onSourcesChanged: {
        if (root.panelOpen)
            root.refresh();
    }
}
