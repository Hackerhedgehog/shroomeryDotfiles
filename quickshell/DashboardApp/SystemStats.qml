pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "Stats.js" as Stats

// CPU, memory, disks, network, CPU temperature and uptime for the dashboard,
// read every 2 s while something uses them (`consumers` > 0; the open
// dashboard counts itself in). The NVIDIA GPU is read only while
// `gpuConsumers` > 0 (Performance tab showing) and the card is already awake:
// nvidia-smi would wake a runtime-suspended laptop dGPU and drain the battery.
Singleton {
    id: root

    property int consumers: 0
    property int gpuConsumers: 0

    property real cpuPercent: 0
    // Last 60 samples (2 min), oldest first.
    property var cpuHistory: []
    property real cpuTempC: NaN
    property real memTotalKb: 0
    property real memUsedKb: 0
    property real swapTotalKb: 0
    property real swapUsedKb: 0
    // [{ mount, sizeKb, usedKb, percent }]
    property var disks: []
    readonly property var rootDisk: {
        for (let i = 0; i < disks.length; i++)
            if (disks[i].mount === "/")
                return disks[i];
        return disks.length > 0 ? disks[0] : null;
    }
    // Bytes per second over all physical interfaces.
    property real netRxRate: 0
    property real netTxRate: 0
    property real uptimeSeconds: 0
    // "active" (gpu filled in), "asleep" (runtime-suspended, not polled),
    // "none" (no NVIDIA card or nvidia-smi failed).
    property string gpuState: "none"
    // { util, memUsedMb, memTotalMb, tempC } or null
    property var gpu: null

    property var _prevCpu: null
    property var _prevNet: null
    property double _prevNetAt: 0

    // Rates must not span the time nothing was sampled.
    onConsumersChanged: if (consumers === 0) { _prevCpu = null; _prevNet = null; }

    function ingest(text: string): void {
        const s = Stats.parseSnapshot(text);
        const now = Date.now();
        if (s.cpu) {
            if (root._prevCpu) {
                root.cpuPercent = Stats.cpuPercent(root._prevCpu, s.cpu);
                root.cpuHistory = root.cpuHistory.concat([root.cpuPercent]).slice(-60);
            }
            root._prevCpu = s.cpu;
        }
        if (s.mem) {
            root.memTotalKb = s.mem.totalKb;
            root.memUsedKb = s.mem.totalKb - s.mem.availableKb;
            root.swapTotalKb = s.mem.swapTotalKb;
            root.swapUsedKb = s.mem.swapTotalKb - s.mem.swapFreeKb;
        }
        if (s.net) {
            if (root._prevNet) {
                const dt = (now - root._prevNetAt) / 1000;
                root.netRxRate = Stats.rate(root._prevNet.rx, s.net.rx, dt);
                root.netTxRate = Stats.rate(root._prevNet.tx, s.net.tx, dt);
            }
            root._prevNet = s.net;
            root._prevNetAt = now;
        }
        root.cpuTempC = s.tempC;
        if (s.disks)
            root.disks = s.disks;
        if (s.uptime > 0)
            root.uptimeSeconds = s.uptime;
    }

    Process {
        id: snapshot
        command: ["sh", "-c", Stats.snapshotScript({ procDir: Paths.procDir, hwmonDir: Paths.hwmonDir })]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    Process {
        id: gpuStatus
        command: ["sh", "-c", "cat " + Paths.nvidiaDriverDir + "/0000:*/power/runtime_status 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim();
                if (s === "") {
                    root.gpuState = "none";
                    root.gpu = null;
                } else if (s !== "active") {
                    root.gpuState = "asleep";
                } else if (!gpuQuery.running) {
                    gpuQuery.running = true;
                }
            }
        }
    }

    Process {
        id: gpuQuery
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
                  "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = Stats.parseNvidia(text);
                root.gpu = g;
                root.gpuState = g ? "active" : "none";
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.consumers > 0
        onTriggered: {
            if (!snapshot.running)
                snapshot.running = true;
            if (root.gpuConsumers > 0 && !gpuStatus.running && !gpuQuery.running)
                gpuStatus.running = true;
        }
    }
}
