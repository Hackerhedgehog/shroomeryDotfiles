import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared

// Network status icon: hovering it grows the bar into the NetworkApp panel.
// Shows the connection that carries the default route:
//   • wired:    lan-filled with internet, lan without
//   • wireless: wifi / wifi-medium / wifi-low by signal strength,
//               wifi-crossed without internet
//   • nothing:  wifi-crossed
// Refreshed on every `nmcli monitor` event and polled for the Wi-Fi signal.
BarButton {
    id: net
    popout: "network"

    // "ethernet", "wifi" or "" (no connection).
    property string kind: ""
    property bool internet: false
    // Signal strength (0-100) of the Wi-Fi access point in use.
    property int signal: 0

    iconSrc: {
        if (kind === "ethernet")
            return Paths.icon(internet ? "lan-filled" : "lan")
        if (kind === "wifi" && internet) {
            if (signal >= 55)
                return Paths.icon("wifi")
            if (signal >= 30)
                return Paths.icon("wifi-medium")
            return Paths.icon("wifi-low")
        }
        return Paths.icon("wifi-crossed")
    }


    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true
    }

    // Parses the sections printed by statusProc.
    function parse(text: string): void {
        let section = ""
        let connectivity = ""
        let routeDev = ""
        let routeMetric = Infinity
        let devices = {}          // device name -> type, connected devices only
        let wifiSignal = 0
        for (const line of text.split("\n")) {
            if (line.startsWith("##")) {
                section = line.substring(2)
                continue
            }
            if (line === "")
                continue
            if (section === "conn") {
                connectivity = line.trim()
            } else if (section === "route") {
                // default via 192.168.0.1 dev eno1 ... metric 100
                const f = line.trim().split(/\s+/)
                const dev = f[f.indexOf("dev") + 1]
                const mi = f.indexOf("metric")
                const metric = mi >= 0 ? parseInt(f[mi + 1]) : 0
                if (f.indexOf("dev") >= 0 && metric < routeMetric) {
                    routeDev = dev
                    routeMetric = metric
                }
            } else if (section === "dev") {
                // eno1:ethernet:connected
                const f = line.split(":")
                if (f.length >= 3 && f[2] === "connected")
                    devices[f[0]] = f[1]
            } else if (section === "wifi") {
                // *:66   (in-use marker, signal)
                const f = line.split(":")
                if (f[0] === "*")
                    wifiSignal = parseInt(f[1]) || 0
            }
        }

        const types = Object.values(devices)
        let k = devices[routeDev] || ""
        if (k !== "ethernet" && k !== "wifi")
            k = types.includes("ethernet") ? "ethernet"
              : types.includes("wifi") ? "wifi" : ""

        net.kind = k
        // "unknown" means NetworkManager's connectivity check is off; trust
        // the default route then.
        net.internet = connectivity === "full"
            || (connectivity === "unknown" && routeDev !== "")
        net.signal = wifiSignal
    }

    Process {
        id: statusProc
        command: ["sh", "-c",
            "echo '##conn'; nmcli -t -f CONNECTIVITY general;"
            + " echo '##route'; ip -o route show default;"
            + " echo '##dev'; nmcli -t -f DEVICE,TYPE,STATE device;"
            + " echo '##wifi'; nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: net.parse(text)
        }
    }

    // Any NetworkManager state change (link up/down, connectivity, …).
    Process {
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: _ => debounce.restart()
        }
    }

    // nmcli monitor emits a burst of lines per change; refresh once after it.
    Timer {
        id: debounce
        interval: 500
        onTriggered: net.refresh()
    }

    // Signal strength changes don't show up in nmcli monitor.
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: net.refresh()
    }
}
