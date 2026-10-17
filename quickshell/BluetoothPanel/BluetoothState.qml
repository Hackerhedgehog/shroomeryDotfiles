pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.shared
// Live BlueZ adapters/devices (Quickshell.Bluetooth), remembered connections
// shared with the Flutter bluetooth_controls app, and systemctl/rfkill health.

Singleton {
    id: root

    readonly property string memoryPath: Paths.bluetoothMemory
    readonly property int scanDurationMs: 30000
    readonly property int pairTimeoutMs: 60000
    readonly property int connectTimeoutMs: 20000

    // How many panels are currently showing bluetooth state. See
    // NetworkState.openRequests for why this is a count.
    property int openRequests: 0
    readonly property bool panelOpen: openRequests > 0
    property string selectedAdapterId: ""
    property var remembered: []
    property var rssiByPath: ({})
    property var adapterExtras: ({})
    property var busyMap: ({})
    property var ops: ({})
    property var issues: []
    property bool available: false
    property bool fixing: false
    property bool powerBusy: false
    property bool initialized: false
    property int liveRevision: 0
    property string errorMessage: ""
    property string bannerMessage: ""
    property string _sudoPassword: ""
    property string _pendingAlias: ""
    property string _pendingMemory: ""
    property string _statusActive: "unknown"
    property string _statusEnabled: "unknown"
    property bool _softBlocked: false
    property bool _hardBlocked: false
    property bool _statusReady: false

    readonly property var selectedAdapter: {
        const _r = liveRevision;
        const id = selectedAdapterId;
        const adapters = Bluetooth.adapters ? Bluetooth.adapters.values : [];
        if (!adapters || adapters.length === 0)
            return null;
        if (id) {
            for (let i = 0; i < adapters.length; i++) {
                if (adapters[i].adapterId === id)
                    return adapters[i];
            }
        }
        return Bluetooth.defaultAdapter || adapters[0];
    }

    readonly property var adapterModel: {
        const _r = liveRevision;
        const adapters = Bluetooth.adapters ? Bluetooth.adapters.values : [];
        const out = [];
        for (let i = 0; i < adapters.length; i++)
            out.push(adapterDisplayName(adapters[i]));
        return out;
    }

    readonly property int adapterIndex: {
        const _r = liveRevision;
        const adapters = Bluetooth.adapters ? Bluetooth.adapters.values : [];
        const selected = selectedAdapter;
        if (!selected)
            return -1;
        for (let i = 0; i < adapters.length; i++) {
            if (adapters[i].adapterId === selected.adapterId)
                return i;
        }
        return 0;
    }

    readonly property bool scanning: selectedAdapter ? selectedAdapter.discovering : false
    readonly property bool powered: selectedAdapter ? selectedAdapter.enabled : false
    readonly property bool blocked: selectedAdapter ? selectedAdapter.state === BluetoothAdapterState.Blocked : _softBlocked

    readonly property string statusLabel: {
        const _r = liveRevision;
        if (!available)
            return "Unavailable";
        if (!selectedAdapter)
            return "No adapter";
        if (blocked)
            return "Blocked";
        if (!selectedAdapter.enabled)
            return "Off";
        if (selectedAdapter.discovering)
            return "Scanning…";
        return "On";
    }

    readonly property string statusText: {
        if (fixing)
            return "Applying system fixes…";
        if (powerBusy)
            return "Toggling Bluetooth…";
        if (errorMessage !== "")
            return errorMessage;
        if (bannerMessage !== "")
            return bannerMessage;
        if (scanning)
            return "Searching for nearby devices…";
        if (!available)
            return "Cannot reach BlueZ. Fix the issues above, then the list will load.";
        if (!selectedAdapter)
            return "No Bluetooth adapter found.";
        if (!powered)
            return "Bluetooth is off.";
        return "Ready.";
    }

    readonly property int connectedCount: _countDevices(d => d.connected)
    readonly property int savedCount: _countDevices(d => isSaved(d)) + memoryOnly.length
    readonly property int nearbyCount: _countDevices(d => isNearby(d))

    readonly property var memoryOnly: {
        const _r = liveRevision;
        const adapter = selectedAdapter;
        const mem = remembered;
        const seen = {};
        if (adapter && adapter.devices) {
            const vals = adapter.devices.values;
            for (let i = 0; i < vals.length; i++)
                seen[vals[i].address] = true;
        }
        const out = [];
        for (let i = 0; i < mem.length; i++) {
            if (!seen[mem[i].address])
                out.push(mem[i]);
        }
        return out;
    }

    readonly property var timeoutLabels: ["1 min", "3 min", "5 min", "Forever"]
    readonly property var timeoutValues: [60, 180, 300, 0]

    readonly property int timeoutIndex: {
        const adapter = selectedAdapter;
        const extrasTick = liveRevision;
        if (!adapter)
            return 1;
        const t = adapter.discoverableTimeout;
        const idx = timeoutValues.indexOf(t);
        return idx >= 0 ? idx : 1;
    }

    FileView {
        id: memoryFile
        path: root.memoryPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onLoaded: root._ingestMemory(text())
        onLoadFailed: {
            if (!root.initialized)
                root.initialized = true;
        }
        onSaved: root.initialized = true
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: root._ingestStatus(text)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: extrasProc
        stdout: StdioCollector {
            id: extrasOut
            onStreamFinished: root._ingestExtras(text)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: sudoProc
        stdinEnabled: true
        environment: ({
                "LC_ALL": "C"
            })
        stdout: StdioCollector {
            id: sudoOut
        }
        stderr: StdioCollector {
            id: sudoErr
        }
        onStarted: {
            if (root._sudoPassword !== "") {
                sudoProc.write(root._sudoPassword + "\n");
                root._sudoPassword = "";
            }
        }
        onExited: exitCode => root._ingestSudo(sudoOut.text, sudoErr.text, exitCode)
    }

    Process {
        id: aliasProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: aliasErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                const detail = aliasErr.text.trim();
                root.errorMessage = detail !== "" ? detail : "Could not rename the adapter.";
            } else {
                root.errorMessage = "";
                root.bannerMessage = "Adapter name updated to \"" + root._pendingAlias + "\".";
            }
            root._pendingAlias = "";
            root.refreshExtras();
        }
    }

    Process {
        id: mkdirProc
        onExited: {
            if (root._pendingMemory !== "") {
                memoryFile.setText(root._pendingMemory);
                root._pendingMemory = "";
            }
        }
    }

    Timer {
        interval: 400
        running: root.panelOpen
        repeat: true
        onTriggered: {
            root.liveRevision++;
            root._tickOps();
            root.available = Bluetooth.defaultAdapter !== null || (Bluetooth.adapters && Bluetooth.adapters.values.length > 0);
        }
    }

    Timer {
        interval: 2000
        running: root.panelOpen
        repeat: true
        onTriggered: {
            root.refreshExtras();
            root.refreshStatus();
        }
    }

    Timer {
        interval: 5000
        running: !root.panelOpen
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: scanTimer
        interval: root.scanDurationMs
        repeat: false
        onTriggered: root.stopScan()
    }

    function refresh() {
        errorMessage = "";
        available = Bluetooth.defaultAdapter !== null || (Bluetooth.adapters && Bluetooth.adapters.values.length > 0);
        liveRevision++;
        memoryFile.reload();
        refreshStatus();
        refreshExtras();
        initialized = true;
    }

    function refreshStatus() {
        statusProc.exec(["python3", "-c", "import json,os,subprocess\n" + "env=dict(os.environ); env['LC_ALL']='C'\n" + "def run(cmd):\n" + "    return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout.strip()\n" + "active=run(['systemctl','is-active','bluetooth.service'])\n" + "enabled=run(['systemctl','is-enabled','bluetooth.service'])\n" + "soft=False; hard=False\n" + "rf='/sys/class/rfkill'\n" + "if os.path.isdir(rf):\n" + "    for name in os.listdir(rf):\n" + "        p=os.path.join(rf,name)\n" + "        try:\n" + "            if open(os.path.join(p,'type')).read().strip()!='bluetooth':\n" + "                continue\n" + "            if open(os.path.join(p,'soft')).read().strip()=='1': soft=True\n" + "            if open(os.path.join(p,'hard')).read().strip()=='1': hard=True\n" + "        except Exception:\n" + "            pass\n" + "print(json.dumps({'active':active,'enabled':enabled,'softBlocked':soft,'hardBlocked':hard}))\n"]);
    }

    function refreshExtras() {
        const adapters = Bluetooth.adapters ? Bluetooth.adapters.values : [];
        const adapterPaths = [];
        const devicePaths = [];
        for (let i = 0; i < adapters.length; i++) {
            adapterPaths.push(adapters[i].dbusPath);
            const devices = adapters[i].devices ? adapters[i].devices.values : [];
            for (let j = 0; j < devices.length; j++)
                devicePaths.push(devices[j].dbusPath);
        }
        extrasProc.exec(["python3", "-c", "import json,subprocess,sys\n" + "def get(path, iface, prop):\n" + "    r=subprocess.run(['busctl','--system','get-property','org.bluez',path,iface,prop], capture_output=True, text=True)\n" + "    if r.returncode!=0: return None\n" + "    parts=r.stdout.strip().split(None,1)\n" + "    if len(parts)<2: return None\n" + "    val=parts[1]\n" + "    if len(val)>=2 and val[0]=='\"' and val[-1]=='\"': return val[1:-1]\n" + "    try: return int(val)\n" + "    except Exception: return val\n" + "payload=json.loads(sys.argv[1])\n" + "out={'adapters':{},'rssi':{}}\n" + "for p in payload.get('adapters',[]):\n" + "    out['adapters'][p]={'address':get(p,'org.bluez.Adapter1','Address') or '','alias':get(p,'org.bluez.Adapter1','Alias') or ''}\n" + "for p in payload.get('devices',[]):\n" + "    rssi=get(p,'org.bluez.Device1','RSSI')\n" + "    if rssi not in (None,0): out['rssi'][p]=rssi\n" + "print(json.dumps(out))\n", JSON.stringify({
                    adapters: adapterPaths,
                    devices: devicePaths
                })]);
    }

    function selectAdapterByIndex(index) {
        const adapters = Bluetooth.adapters ? Bluetooth.adapters.values : [];
        if (index < 0 || index >= adapters.length)
            return;
        selectedAdapterId = adapters[index].adapterId;
        _persistMemory();
    }

    function setPowered(powered) {
        const adapter = selectedAdapter;
        if (!adapter)
            return;
        powerBusy = true;
        errorMessage = "";
        adapter.enabled = powered;
        Qt.callLater(() => {
            powerBusy = false;
            liveRevision++;
        });
    }

    function startScan() {
        const adapter = selectedAdapter;
        if (!adapter || !adapter.enabled)
            return;
        errorMessage = "";
        adapter.discovering = true;
        scanTimer.restart();
        liveRevision++;
    }

    function stopScan() {
        scanTimer.stop();
        const adapter = selectedAdapter;
        if (adapter && adapter.discovering)
            adapter.discovering = false;
        liveRevision++;
    }

    function setDiscoverable(value, timeoutSeconds) {
        const adapter = selectedAdapter;
        if (!adapter)
            return;
        errorMessage = "";
        adapter.discoverableTimeout = timeoutSeconds;
        adapter.discoverable = value;
        liveRevision++;
    }

    function setTimeoutByIndex(index) {
        if (index < 0 || index >= timeoutValues.length)
            return;
        const adapter = selectedAdapter;
        if (!adapter)
            return;
        const seconds = timeoutValues[index];
        adapter.discoverableTimeout = seconds;
        if (adapter.discoverable)
            adapter.discoverable = true;
        liveRevision++;
    }

    function setAdapterAlias(alias) {
        const adapter = selectedAdapter;
        const trimmed = (alias || "").trim();
        if (!adapter || trimmed === "")
            return;
        _pendingAlias = trimmed;
        aliasProc.exec(["busctl", "--system", "set-property", "org.bluez", adapter.dbusPath, "org.bluez.Adapter1", "Alias", "s", trimmed]);
    }

    function connectDevice(dev) {
        if (!dev) {
            errorMessage = "Device no longer available.";
            return;
        }
        const addr = dev.address;
        errorMessage = "";
        bannerMessage = "";
        _setBusy(addr, true);
        const next = Object.assign({}, ops);
        next[addr] = {
            stage: dev.paired ? "connect" : "pair",
            started: Date.now()
        };
        ops = next;
        if (!dev.paired) {
            dev.pair();
        } else {
            dev.trusted = true;
            dev.connect();
            recordConnection(addr, displayName(dev));
        }
    }

    function disconnectDevice(dev) {
        if (!dev)
            return;
        errorMessage = "";
        _setBusy(dev.address, true);
        const next = Object.assign({}, ops);
        next[dev.address] = {
            stage: "disconnect",
            started: Date.now()
        };
        ops = next;
        dev.disconnect();
    }

    function setTrusted(dev, trusted) {
        if (!dev)
            return;
        dev.trusted = trusted;
        liveRevision++;
    }

    function forgetDevice(dev) {
        if (!dev)
            return;
        const addr = dev.address;
        try {
            dev.forget();
        } catch (e) {
        }
        _removeRemembered(addr);
        _clearOp(addr);
        bannerMessage = "Forgot " + displayName(dev) + ".";
    }

    function forgetAddress(address) {
        _removeRemembered(address);
        bannerMessage = "Forgot remembered device.";
    }

    function isBusy(address) {
        return !!busyMap[address];
    }

    function isSaved(dev) {
        if (!dev || dev.connected)
            return false;
        return dev.paired || dev.trusted || _memoryContains(dev.address);
    }

    function isNearby(dev) {
        return !!dev && !dev.connected && !isSaved(dev);
    }

    function displayName(dev) {
        if (!dev)
            return "";
        const n = (dev.name || "").trim();
        if (n !== "")
            return n;
        const d = (dev.deviceName || "").trim();
        return d !== "" ? d : dev.address;
    }

    function adapterDisplayName(adapter) {
        if (!adapter)
            return "";
        const extra = adapterExtras[adapter.dbusPath] || {};
        const alias = (extra.alias || "").trim();
        if (alias !== "")
            return alias;
        const n = (adapter.name || "").trim();
        return n !== "" ? n : adapter.adapterId;
    }

    function adapterAddress(adapter) {
        if (!adapter)
            return "";
        const extra = adapterExtras[adapter.dbusPath] || {};
        return extra.address || "";
    }

    function describeDevice(dev) {
        if (!dev)
            return "";
        const state = dev.connected ? "Connected" : (dev.pairing ? "Pairing" : (dev.paired ? "Paired" : (dev.trusted ? "Trusted" : "")));
        return state === "" ? dev.address : (dev.address + " · " + state);
    }

    function batteryPercent(dev) {
        if (!dev || !dev.batteryAvailable)
            return null;
        return Math.round(dev.battery * 100);
    }

    function rssiFor(dev) {
        if (!dev)
            return null;
        const v = rssiByPath[dev.dbusPath];
        return (v === undefined || v === 0) ? null : v;
    }

    function signalLabel(rssi) {
        if (rssi === null || rssi === undefined)
            return "";
        if (rssi >= -60)
            return "Strong · " + rssi + " dBm";
        if (rssi >= -75)
            return "Medium · " + rssi + " dBm";
        return "Weak · " + rssi + " dBm";
    }

    function iconPathFor(dev) {
        const icon = dev && dev.icon ? dev.icon : "bluetooth";
        return Quickshell.iconPath(icon, "bluetooth");
    }

    readonly property bool hasFixableIssues: {
        const list = issues;
        for (let i = 0; i < list.length; i++) {
            if (list[i].fix)
                return true;
        }
        return false;
    }

    readonly property var fixCommands: {
        const list = issues;
        const lines = [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].command)
                lines.push(list[i].command);
        }
        return lines;
    }

    function applyFixes(password) {
        const commands = [];
        let hasRfkill = false;
        for (let i = 0; i < issues.length; i++) {
            if (issues[i].fix === "startService")
                commands.push(["systemctl", "start", "bluetooth.service"]);
            else if (issues[i].fix === "enableService")
                commands.push(["systemctl", "enable", "bluetooth.service"]);
            else if (issues[i].fix === "rfkillUnblock")
                hasRfkill = true;
        }
        if (hasRfkill)
            commands.push(["rfkill", "unblock", "bluetooth"]);
        if (commands.length === 0)
            return false;
        fixing = true;
        errorMessage = "";
        _sudoPassword = password;
        sudoProc.exec(["python3", "-c", "import json,os,sys,subprocess\n" + "os.environ['LC_ALL']='C'\n" + "pw=sys.stdin.readline()\n" + "if pw.endswith('\\n'): pw=pw[:-1]\n" + "cmds=json.loads(sys.argv[1])\n" + "env=dict(os.environ); env['LC_ALL']='C'\n" + "for cmd in cmds:\n" + "    if cmd and cmd[0]=='rfkill':\n" + "        p=subprocess.run(cmd, capture_output=True, text=True, env=env)\n" + "        if p.returncode==0: continue\n" + "    p=subprocess.run(['sudo','-S','-k']+cmd, input=pw+'\\n', capture_output=True, text=True, env=env)\n" + "    err=(p.stderr or '')+(p.stdout or '')\n" + "    low=err.lower()\n" + "    if p.returncode!=0 and ('sorry' in low or 'try again' in low or 'incorrect password' in low or 'authentication failure' in low):\n" + "        print(json.dumps({'kind':'wrongPassword'})); sys.exit(0)\n" + "    if p.returncode!=0:\n" + "        print(json.dumps({'kind':'failure','detail':err.strip()[:500]})); sys.exit(0)\n" + "print(json.dumps({'kind':'success'}))\n", JSON.stringify(commands)]);
        return true;
    }

    function recordConnection(address, name) {
        const now = Date.now();
        const rest = remembered.filter(d => d.address !== address);
        remembered = [{
                address: address,
                name: name || address,
                lastConnectedMs: now
            }].concat(rest);
        _persistMemory();
    }

    function _removeRemembered(address) {
        remembered = remembered.filter(d => d.address !== address);
        _persistMemory();
    }

    function _memoryContains(address) {
        for (let i = 0; i < remembered.length; i++) {
            if (remembered[i].address === address)
                return true;
        }
        return false;
    }

    function _countDevices(pred) {
        const _r = liveRevision;
        const adapter = selectedAdapter;
        if (!adapter || !adapter.devices)
            return 0;
        const vals = adapter.devices.values;
        let n = 0;
        for (let i = 0; i < vals.length; i++) {
            if (pred(vals[i]))
                n++;
        }
        return n;
    }

    function _setBusy(address, busy) {
        const next = Object.assign({}, busyMap);
        if (busy)
            next[address] = true;
        else
            delete next[address];
        busyMap = next;
        liveRevision++;
    }

    function _clearOp(address) {
        const next = Object.assign({}, ops);
        delete next[address];
        ops = next;
        _setBusy(address, false);
    }

    function _tickOps() {
        const current = ops;
        const addresses = Object.keys(current);
        if (addresses.length === 0)
            return;
        const adapter = selectedAdapter;
        const now = Date.now();
        for (let i = 0; i < addresses.length; i++) {
            const addr = addresses[i];
            const op = current[addr];
            const dev = _findDevice(adapter, addr);
            if (!dev) {
                errorMessage = "Device no longer available.";
                _clearOp(addr);
                continue;
            }
            if (op.stage === "pair") {
                if (dev.paired) {
                    dev.trusted = true;
                    dev.connect();
                    recordConnection(addr, displayName(dev));
                    const next = Object.assign({}, ops);
                    next[addr] = {
                        stage: "connect",
                        started: now
                    };
                    ops = next;
                } else if (!dev.pairing && now - op.started > 2500) {
                    errorMessage = "Pairing failed. Make sure the device is in pairing mode and try again.";
                    _clearOp(addr);
                } else if (now - op.started > pairTimeoutMs) {
                    errorMessage = "Pairing timed out.";
                    try {
                        dev.cancelPair();
                    } catch (e) {
                    }
                    _clearOp(addr);
                }
            } else if (op.stage === "connect") {
                if (dev.connected) {
                    bannerMessage = "Connected to " + displayName(dev) + ".";
                    recordConnection(addr, displayName(dev));
                    _clearOp(addr);
                } else if (dev.state !== BluetoothDeviceState.Connecting && now - op.started > 4000) {
                    errorMessage = "Device not in range or not accepting connections.";
                    _clearOp(addr);
                } else if (now - op.started > connectTimeoutMs) {
                    errorMessage = "Device not in range or not accepting connections.";
                    _clearOp(addr);
                }
            } else if (op.stage === "disconnect") {
                if (!dev.connected) {
                    bannerMessage = "Disconnected from " + displayName(dev) + ".";
                    _clearOp(addr);
                } else if (now - op.started > 8000) {
                    errorMessage = "Could not disconnect.";
                    _clearOp(addr);
                }
            }
        }
    }

    function _findDevice(adapter, address) {
        if (!adapter || !adapter.devices)
            return null;
        const vals = adapter.devices.values;
        for (let i = 0; i < vals.length; i++) {
            if (vals[i].address === address)
                return vals[i];
        }
        return null;
    }

    function _ingestStatus(raw) {
        let parsed;
        try {
            parsed = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            return;
        }
        _statusActive = parsed.active || "unknown";
        _statusEnabled = parsed.enabled || "unknown";
        _softBlocked = !!parsed.softBlocked;
        _hardBlocked = !!parsed.hardBlocked;
        _statusReady = true;
        issues = _computeIssues();
        available = Bluetooth.defaultAdapter !== null || (Bluetooth.adapters && Bluetooth.adapters.values.length > 0) || _statusActive === "active";
        liveRevision++;
    }

    function _computeIssues() {
        const out = [];
        if (!_statusReady)
            return out;
        const active = _statusActive;
        if (active === "inactive" || active === "failed" || active === "deactivating") {
            out.push({
                message: "The Bluetooth service (bluetooth.service) is not running.",
                fix: "startService",
                command: "sudo systemctl start bluetooth.service"
            });
        } else if (active !== "active") {
            out.push({
                message: "Could not determine the state of bluetooth.service. Is systemd available?",
                fix: "",
                command: ""
            });
        }
        if (_statusEnabled === "disabled") {
            out.push({
                message: "The Bluetooth service is not enabled at boot.",
                fix: "enableService",
                command: "sudo systemctl enable bluetooth.service"
            });
        }
        if (_softBlocked || blocked) {
            out.push({
                message: "Bluetooth is blocked by rfkill (soft block).",
                fix: "rfkillUnblock",
                command: "rfkill unblock bluetooth"
            });
        }
        if (_hardBlocked) {
            out.push({
                message: "Bluetooth is disabled by a hardware switch. Enable it physically on this machine.",
                fix: "",
                command: ""
            });
        }
        return out;
    }

    function _ingestExtras(raw) {
        let parsed;
        try {
            parsed = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            return;
        }
        adapterExtras = parsed.adapters || {};
        rssiByPath = parsed.rssi || {};
        liveRevision++;
    }

    function _ingestSudo(stdout, stderr, exitCode) {
        fixing = false;
        _sudoPassword = "";
        let parsed = null;
        try {
            parsed = JSON.parse((stdout || "").trim());
        } catch (e) {
            parsed = null;
        }
        if (parsed && parsed.kind === "wrongPassword") {
            errorMessage = "Incorrect password — try again.";
            return;
        }
        if (parsed && parsed.kind === "failure") {
            errorMessage = parsed.detail || "Command failed.";
            return;
        }
        if (parsed && parsed.kind === "success") {
            errorMessage = "";
            bannerMessage = "System fixes applied.";
            refreshStatus();
            refresh();
            return;
        }
        const err = (stderr || "").trim();
        errorMessage = err !== "" ? err : "Failed to apply system fixes.";
    }

    function _ingestMemory(raw) {
        let parsed;
        try {
            parsed = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            remembered = [];
            initialized = true;
            return;
        }
        if (parsed.selectedAdapterId && selectedAdapterId === "")
            selectedAdapterId = parsed.selectedAdapterId;
        const list = parsed.devices || [];
        const out = [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].address) {
                out.push({
                    address: list[i].address,
                    name: list[i].name || list[i].address,
                    lastConnectedMs: list[i].lastConnectedMs || 0
                });
            }
        }
        out.sort((a, b) => b.lastConnectedMs - a.lastConnectedMs);
        remembered = out;
        initialized = true;
    }

    function _persistMemory() {
        const payload = JSON.stringify({
            selectedAdapterId: selectedAdapterId,
            devices: remembered
        }, null, 2) + "\n";
        root._pendingMemory = payload;
        mkdirProc.exec(["mkdir", "-p", Paths.bluetoothMemoryDir]);
    }

    Component.onCompleted: refresh()
}
