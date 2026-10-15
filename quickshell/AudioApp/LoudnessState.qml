pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.AudioApp
import "Loudness.js" as Loudness

// Owns the dynamic loudness filter chain: the child `pipewire -c <conf>`
// process, the settings file, node discovery and live parameter pushes.
// Everything that is pure maths lives in Loudness.js; everything that touches
// the outside world lives here.
Singleton {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string confPath: root.runtimeDir + "/quickshell-dynamic-loudness.conf"
    // State belongs under XDG_STATE_HOME, not in ~/.config/quickshell — that
    // directory is a symlink to the dotfiles git repo, so writing there drops
    // an untracked file into the working tree.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string statePath: root.stateDir + "/dynamic-loudness.json"

    // The LV2 bundle has to exist before any of this can work.
    property bool available: false

    // Test tones need ffmpeg to generate and paplay to play; without them the
    // buttons are hidden rather than failing silently when pressed.
    property bool tonesAvailable: false

    property bool enabled: false
    readonly property bool running: chainProc.running
    property string errorMessage: ""

    // Set when the settings file says "enabled" but the LV2 probe has not
    // resolved `available` yet. `Component.onCompleted` fires probeProc and
    // starts the FileView load at the same time, so either can finish first;
    // whichever finishes second is the one that actually starts the chain.
    property bool _pendingRestore: false

    // The six user-facing values, always in UI units (dB, ms, ratio).
    property var values: ({
            "threshold": Loudness.PRESETS.reset.threshold,
            "ratio": Loudness.PRESETS.reset.ratio,
            "attack": Loudness.PRESETS.reset.attack,
            "release": Loudness.PRESETS.reset.release,
            "makeup": Loudness.PRESETS.reset.makeup,
            "ceiling": Loudness.PRESETS.reset.ceiling
        })

    readonly property string preset: Loudness.matchPreset(root.values)

    // The real device the chain feeds. Remembered so disabling can put the
    // default sink back where the user left it.
    property string targetSinkName: ""

    readonly property string targetSinkLabel: {
        const nodes = AudioState.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].name === root.targetSinkName)
                return AudioState.displayName(nodes[i]);
        }
        return root.targetSinkName;
    }

    // The virtual sink node, once PipeWire has published it.
    readonly property var chainNode: {
        const nodes = AudioState.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].name === Loudness.SINK_NAME)
                return nodes[i];
        }
        return null;
    }

    // PipeWire global object id. Not a pactl index — pw-cli addresses globals.
    property int nodeId: -1

    // ------------------------------------------------------------ derived

    readonly property real suggestedMakeup: Loudness.suggestedMakeup(root.values.threshold, root.values.ratio)

    readonly property var limiterOnset: Loudness.limiterOnsetDb(root.values.threshold, root.values.ratio, root.values.makeup, root.values.ceiling)

    function reductionAt(inputDb) {
        return Loudness.gainReduction(inputDb, root.values.threshold, root.values.ratio);
    }

    // ------------------------------------------------------------ mutation

    function setParam(key, value) {
        if (!Loudness.PARAMS[key])
            return;
        const next = {};
        for (const k in root.values)
            next[k] = root.values[k];
        next[key] = Loudness.clampDb(key, value);
        root.values = next;
        root._schedulePush();
        root._scheduleSave();
    }

    function applyPreset(name) {
        const preset = Loudness.PRESETS[name];
        if (!preset)
            return;
        const next = {};
        for (let i = 0; i < Loudness.PARAM_KEYS.length; i++) {
            const key = Loudness.PARAM_KEYS[i];
            next[key] = preset[key];
        }
        root.values = next;
        root._schedulePush();
        root._scheduleSave();
    }

    function applySuggestedMakeup() {
        root.setParam("makeup", root.suggestedMakeup);
    }

    function setEnabled(on) {
        if (!root.available || on === root.enabled)
            return;
        root.enabled = on;
        if (on) {
            root._start();
        } else {
            // A deferred restore must not re-fire after an explicit disable.
            root._pendingRestore = false;
            root._stop();
        }
        root._scheduleSave();
    }

    // Point the chain's playback stream at a different real device, instead of
    // changing the default sink — while the effect is on, the chain IS the
    // default sink.
    function retarget(node) {
        if (!node || node.name === Loudness.SINK_NAME)
            return;
        root.targetSinkName = node.name;
        root._scheduleSave();
        if (root.running) {
            listInputsProc.command = ["pactl", "-f", "json", "list", "sink-inputs"];
            listInputsProc.running = true;
        }
    }

    // ------------------------------------------------------------ lifecycle

    // Pick the device the chain should feed, in preference order. The
    // persisted name is only trusted when a node with that name is actually
    // present: an unsatisfiable `target.object` makes PipeWire link the
    // chain's playback end to the default sink, which _makeDefault() is about
    // to point at the chain itself — a silent self-loop.
    function _chooseTarget() {
        const def = AudioState.defaultSink;
        if (def && def.name !== Loudness.SINK_NAME)
            return def.name;
        const sinks = AudioState.sinks;
        if (root.targetSinkName !== "") {
            for (let i = 0; i < sinks.length; i++) {
                if (sinks[i].name === root.targetSinkName)
                    return root.targetSinkName;
            }
        }
        return sinks.length > 0 ? sinks[0].name : "";
    }

    function _start() {
        root.errorMessage = "";
        const target = root._chooseTarget();
        if (target === "") {
            root._fail("No output device to feed.");
            return;
        }
        root.targetSinkName = target;
        writeProc.pendingConf = Loudness.renderConf(root.values, root.targetSinkName);
        writeProc.command = ["sh", "-c", "cat > \"$1\"", "sh", root.confPath];
        writeProc.running = true;
    }

    function _stop() {
        // Abort any in-flight enable sequence first. Without this, a disable
        // issued while writeProc/idProc/discoveryTimeout are still running
        // would not prevent their continuations from firing afterwards —
        // starting the chain and hijacking the default sink even though the
        // UI already shows the effect off.
        writeProc.running = false;
        idProc.running = false;
        discoveryTimeout.stop();
        // Put the default sink back BEFORE the virtual one disappears, so
        // streams migrate rather than being orphaned.
        root._restoreDefault();
        chainProc.running = false;
        root.nodeId = -1;
    }

    function _restoreDefault() {
        const nodes = AudioState.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].name === root.targetSinkName) {
                Pipewire.preferredDefaultAudioSink = nodes[i];
                return;
            }
        }
        // The remembered device is gone. Never return having left the
        // preference on a node that is about to be destroyed: fall back to a
        // surviving real sink, or hand the choice back to the session manager.
        const alt = AudioState.sinks[0];
        Pipewire.preferredDefaultAudioSink = alt ? alt : null;
    }

    function _fail(message) {
        root.errorMessage = message;
        root.enabled = false;
        // A deferred restore must not re-fire after a failure.
        root._pendingRestore = false;
        // Tear down anything still in flight, and restore the default sink
        // BEFORE the virtual one disappears — same ordering as _stop(), for
        // the same reason: streams should migrate, not be orphaned.
        idProc.running = false;
        discoveryTimeout.stop();
        root._restoreDefault();
        chainProc.running = false;
        root.nodeId = -1;
        // Persist the off state, or the next shell start re-attempts the same
        // failing enable from a file that still says `enabled: true`.
        root._scheduleSave();
    }

    function _schedulePush() {
        if (root.running && root.nodeId >= 0)
            pushTimer.restart();
    }

    // ------------------------------------------------------------ processes

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.stateDir]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Process {
        id: probeProc
        command: ["sh", "-c", "test -d /usr/lib/lv2/lsp-plugins.lv2 || test -d /usr/local/lib/lv2/lsp-plugins.lv2"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => root.available = (exitCode === 0)
    }

    // Runs the deferred restore once the LV2 probe resolves, in case the
    // settings load finished first and left it pending.
    onAvailableChanged: {
        if (root.available && root._pendingRestore) {
            root._pendingRestore = false;
            root.setEnabled(true);
        }
    }

    Process {
        id: tonesProbeProc
        command: ["sh", "-c", "command -v ffmpeg >/dev/null && command -v paplay >/dev/null"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => root.tonesAvailable = (exitCode === 0)
    }

    Process {
        id: writeProc
        property string pendingConf: ""
        stdinEnabled: true
        onStarted: {
            writeProc.write(writeProc.pendingConf);
            writeProc.stdinEnabled = false;
        }
        onExited: exitCode => {
            // A disable that landed while this was still running already
            // tore down the sequence in _stop(); do not resurrect it.
            if (!root.enabled)
                return;
            if (exitCode !== 0) {
                root._fail("Could not write the loudness config.");
                return;
            }
            chainProc.command = ["pipewire", "-c", root.confPath];
            chainProc.running = true;
            discoveryTimeout.restart();
        }
    }

    Process {
        id: chainProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: chainErr
        }
        onExited: exitCode => {
            root.nodeId = -1;
            if (root.enabled) {
                const detail = chainErr.text.trim().split("\n")[0];
                root._fail(detail !== "" ? detail : "The loudness processor stopped unexpectedly.");
            }
        }
    }

    // Resolve the PipeWire global id once the node exists; pw-cli addresses
    // the node by global id, not by name.
    Process {
        id: idProc
        command: ["pw-dump"]
        stdout: StdioCollector {
            id: idOut
            onStreamFinished: {
                // A disable that landed while pw-dump was still running
                // already tore this sequence down in _stop(); do not switch
                // the default sink to a chain the user just turned off.
                if (!root.enabled)
                    return;
                const id = Loudness.parseNodeId(idOut.text, Loudness.SINK_NAME);
                if (id === null)
                    return;
                root.nodeId = id;
                discoveryTimeout.stop();
                root._makeDefault();
                root._schedulePush();
            }
        }
        stderr: StdioCollector {}
    }

    // One call carries all six parameters.
    Process {
        id: pushProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: pushErr
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.errorMessage = pushErr.text.trim() || "Could not apply the settings.";
            else
                root.errorMessage = "";
        }
    }

    Process {
        id: listInputsProc
        stdout: StdioCollector {
            id: listInputsOut
            onStreamFinished: {
                const index = Loudness.parseSinkInputIndex(listInputsOut.text, Loudness.PLAYBACK_NAME);
                if (index === null)
                    return;
                moveProc.command = ["pactl", "move-sink-input", String(index), root.targetSinkName];
                moveProc.running = true;
            }
        }
        stderr: StdioCollector {}
    }

    Process {
        id: moveProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: moveErr
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.errorMessage = moveErr.text.trim() || "Could not move the processor to that device.";
            else
                root.errorMessage = "";
        }
    }

    // ------------------------------------------------------------- timers

    // Coalesce a slider drag into a few writes rather than one per pixel.
    Timer {
        id: pushTimer
        interval: 60
        onTriggered: {
            if (root.nodeId < 0 || !root.running)
                return;
            pushProc.command = Loudness.setParamsArgs(root.nodeId, root.values);
            pushProc.running = true;
        }
    }

    Timer {
        id: discoveryTimeout
        interval: 5000
        onTriggered: {
            if (root.nodeId < 0)
                root._fail("The loudness processor did not start.");
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: root._save()
    }

    function _scheduleSave() {
        saveTimer.restart();
    }

    function _makeDefault() {
        if (root.chainNode)
            Pipewire.preferredDefaultAudioSink = root.chainNode;
    }

    // The node appearing is the signal that the chain is up.
    onChainNodeChanged: {
        if (root.chainNode && root.nodeId < 0)
            idProc.running = true;
    }

    // A SUSPENDED filter-chain node reports stale control values, and a write
    // made while suspended is not observable. Re-push the whole set whenever
    // playback starts, so the graph and the UI cannot drift apart.
    Connections {
        target: AudioState
        function onOutputStreamsChanged() {
            root._schedulePush();
        }
    }

    // --------------------------------------------------------- persistence

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        atomicWrites: true
        onLoaded: root._load(stateFile.text())
        onLoadFailed: root._load("")
    }

    function _load(text) {
        let parsed = {};
        try {
            parsed = JSON.parse(text) || {};
        } catch (e) {
            parsed = {};
        }
        const next = {};
        for (let i = 0; i < Loudness.PARAM_KEYS.length; i++) {
            const key = Loudness.PARAM_KEYS[i];
            const raw = parsed[key];
            // A missing or out-of-range value degrades to the safe default
            // rather than failing the whole load.
            next[key] = (typeof raw === "number" && isFinite(raw)) ? Loudness.clampDb(key, raw) : Loudness.PRESETS.reset[key];
        }
        root.values = next;
        root.targetSinkName = typeof parsed.restoreSink === "string" ? parsed.restoreSink : "";
        if (parsed.enabled === true) {
            // probeProc (sets `available`) and this load both start from
            // Component.onCompleted, so either can finish first. If the
            // probe has not resolved yet, defer the restore instead of
            // letting setEnabled's availability guard silently drop it.
            if (root.available)
                root.setEnabled(true);
            else
                root._pendingRestore = true;
        }
    }

    function _save() {
        const payload = {
            "enabled": root.enabled,
            "preset": root.preset,
            "restoreSink": root.targetSinkName
        };
        for (let i = 0; i < Loudness.PARAM_KEYS.length; i++) {
            const key = Loudness.PARAM_KEYS[i];
            payload[key] = root.values[key];
        }
        stateFile.setText(JSON.stringify(payload, null, 2));
    }

    // On shell quit or a QML reload the chain process dies with this object,
    // destroying the virtual sink while preferredDefaultAudioSink still names
    // it. Put the real device back first.
    Component.onDestruction: {
        if (root.running)
            root._restoreDefault();
    }

    Component.onCompleted: {
        mkdirProc.running = true;
        probeProc.running = true;
        tonesProbeProc.running = true;
    }

    // Losing the target device while running would leave the chain feeding
    // nothing; follow the new default instead.
    Connections {
        target: AudioState
        function onSinksChanged() {
            if (!root.running || root.targetSinkName === "")
                return;
            const nodes = AudioState.allNodes;
            for (let i = 0; i < nodes.length; i++) {
                if (nodes[i].name === root.targetSinkName)
                    return;
            }
            // While the effect runs, AudioState.defaultSink IS the virtual
            // node, so it can never be the replacement. AudioState.sinks
            // already excludes the virtual node, so its first entry is a real
            // surviving device.
            const alt = AudioState.sinks[0];
            if (alt)
                root.retarget(alt);
            else
                root._fail("The output device went away.");
        }
    }
}
