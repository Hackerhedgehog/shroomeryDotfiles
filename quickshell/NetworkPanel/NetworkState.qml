pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Live NetworkManager state (devices, saved profiles, visible access points)
// read through nm_helper.py, plus the NetworkManager/rfkill health checks the
// panel needs to explain why nothing is working.
Singleton {
    id: root

    readonly property string helperPath: Qt.resolvedUrl("nm_helper.py").toString().replace("file://", "")

    // How many panels are currently showing network state. The NetworkPanel and
    // the QuickSettingsPanel are independent consumers, so this is a count rather
    // than a flag: closing one must not slow the other's refresh.
    property int openRequests: 0
    readonly property bool panelOpen: openRequests > 0
    property bool initialized: false
    property bool refreshing: false
    property bool refreshQueued: false

    property bool nmcliMissing: false
    property bool nmRunning: false
    property bool wifiEnabled: false
    property bool wifiHwEnabled: true
    property var devices: []
    property var profiles: []
    property var aps: []
    property var service: ({
            active: "unknown",
            enabled: "unknown"
        })
    property bool softBlocked: false
    property bool hardBlocked: false

    property bool scanning: false
    property double lastScanMs: 0

    // Wi-Fi interface used for scanning/connecting; "" lets NM choose.
    property string wifiIfname: ""

    property var busyMap: ({})
    property string errorMessage: ""
    property string bannerMessage: ""
    property string statusError: ""
    property string errorDetail: ""

    // Properties dialog contents.
    property string propertiesTitle: ""
    property bool propertiesLoading: false
    property var propertyRows: []

    // Filled when an action was denied by polkit and can be retried with sudo.
    property var pendingSudoArgv: []
    property bool sudoRunning: false
    property string sudoError: ""

    property string _sudoPassword: ""
    // Set to the SSID whose connect attempt needs a (new) password, so the
    // window can reprompt. Cleared as soon as the prompt is shown.
    property string passwordNeededSsid: ""

    property string _busyKey: ""
    property string _successMessage: ""

    // ------------------------------------------------------------ derived data

    readonly property var ethernetDevices: devices.filter(d => d.kind === "ethernet")
    readonly property var wifiDevices: devices.filter(d => d.kind === "wifi")
    readonly property var otherDevices: devices.filter(d => d.kind !== "ethernet" && d.kind !== "wifi" && d.kind !== "wifiP2p")

    readonly property bool wifiHardBlocked: !wifiHwEnabled || hardBlocked
    readonly property bool ethernetOn: ethernetDevices.some(d => d.connected)

    readonly property var wiredProfiles: {
        const list = profiles.filter(p => p.kind === "wired").slice();
        list.sort((a, b) => {
            if (a.isActive !== b.isActive)
                return a.isActive ? -1 : 1;
            return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1;
        });
        return list;
    }

    readonly property var savedWifiProfiles: profiles.filter(p => p.kind === "wifi")

    // The wired profile that wins autoconnect + routing, "" when nothing is
    // clearly preferred over the others.
    readonly property string preferredWiredUuid: {
        const wired = wiredProfiles;
        if (wired.length < 2)
            return "";
        const sorted = wired.slice().sort((a, b) => b.autoconnectPriority - a.autoconnectPriority);
        return sorted[0].autoconnectPriority > sorted[1].autoconnectPriority ? sorted[0].uuid : "";
    }

    // Visible networks grouped by SSID (the in-use BSSID always wins, then the
    // strongest), sorted: connected, then saved, then by signal.
    readonly property var visibleNetworks: {
        const bySsid = {};
        for (let i = 0; i < aps.length; i++) {
            const ap = aps[i];
            if (ap.hidden)
                continue;
            const current = bySsid[ap.ssid];
            if (!current || ap.inUse || (!current.inUse && ap.signal > current.signal))
                bySsid[ap.ssid] = ap;
        }
        const out = [];
        const keys = Object.keys(bySsid);
        for (let k = 0; k < keys.length; k++) {
            const ap = bySsid[keys[k]];
            const saved = savedProfileForSsid(ap.ssid);
            out.push({
                ap: ap,
                saved: saved,
                uuid: saved ? saved.uuid : "",
                // nmcli drops the IN-USE marker for a moment around a rescan,
                // so trust an active profile for the same SSID as well.
                isConnected: ap.inUse || (saved !== null && saved.isActive),
                isSaved: saved !== null
            });
        }
        out.sort((a, b) => {
            if (a.isConnected !== b.isConnected)
                return a.isConnected ? -1 : 1;
            if (a.isSaved !== b.isSaved)
                return a.isSaved ? -1 : 1;
            return b.ap.signal - a.ap.signal;
        });
        return out;
    }

    // Saved Wi-Fi profiles whose SSID is not currently visible.
    readonly property var savedOutOfRange: {
        const visible = {};
        for (let i = 0; i < aps.length; i++)
            visible[aps[i].ssid] = true;
        const out = savedWifiProfiles.filter(p => !visible[p.ssid !== "" ? p.ssid : p.name]);
        out.sort((a, b) => b.timestamp - a.timestamp);
        return out;
    }

    // Ethernet NICs with no profile of their own (an unused USB-tethering
    // interface, say) — shown so they can still be connected.
    readonly property var orphanEthernetDevices: {
        const wired = wiredProfiles;
        return ethernetDevices.filter(d => !wired.some(p => p.device === d.name || p.name === d.connectionName));
    }

    readonly property var connectedWifiDevice: {
        const list = wifiDevices;
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected)
                return list[i];
        }
        return null;
    }

    readonly property var wifiIfnameLabels: {
        const out = ["Auto"];
        const list = wifiDevices;
        for (let i = 0; i < list.length; i++)
            out.push(list[i].name);
        return out;
    }

    readonly property int wifiIfnameIndex: {
        const idx = wifiIfnameLabels.indexOf(wifiIfname);
        return wifiIfname === "" || idx < 0 ? 0 : idx;
    }

    readonly property int connectedCount: visibleNetworks.filter(n => n.isConnected).length + wiredProfiles.filter(p => p.isActive).length

    readonly property string statusLabel: {
        if (nmcliMissing || statusError !== "")
            return "Unavailable";
        if (!nmRunning)
            return "Offline";
        if (wifiHardBlocked)
            return "Blocked";
        if (scanning)
            return "Scanning…";
        if (connectedCount > 0)
            return "Connected";
        return "Idle";
    }

    readonly property string statusText: {
        if (errorMessage !== "")
            return errorMessage;
        if (bannerMessage !== "")
            return bannerMessage;
        if (statusError !== "")
            return statusError;
        if (!nmRunning)
            return "NetworkManager is not running.";
        if (scanning)
            return "Scanning for Wi-Fi networks…";
        if (!initialized)
            return "Loading…";
        const parts = [];
        const wired = wiredProfiles.filter(p => p.isActive);
        const wifi = visibleNetworks.filter(n => n.isConnected);
        for (let i = 0; i < wired.length; i++)
            parts.push(wired[i].name);
        for (let i = 0; i < wifi.length; i++)
            parts.push(wifi[i].ap.ssid);
        if (parts.length > 0)
            return "Connected to " + parts.join(", ") + ".";
        return "Not connected.";
    }

    readonly property var issues: {
        const out = [];
        if (nmcliMissing) {
            out.push({
                message: "nmcli was not found. Install NetworkManager to use this panel.",
                fix: "",
                command: ""
            });
            return out;
        }
        const active = service.active;
        if (active === "inactive" || active === "failed" || active === "deactivating") {
            out.push({
                message: "The NetworkManager service is not running.",
                fix: "startService",
                command: "sudo systemctl start NetworkManager.service"
            });
        } else if (!nmRunning && active !== "active") {
            out.push({
                message: "NetworkManager is not answering. Is the daemon installed and running?",
                fix: "",
                command: ""
            });
        }
        if (service.enabled === "disabled") {
            out.push({
                message: "NetworkManager is not enabled at boot.",
                fix: "enableService",
                command: "sudo systemctl enable NetworkManager.service"
            });
        }
        if (softBlocked) {
            out.push({
                message: "The Wi-Fi radio is blocked by rfkill (soft block).",
                fix: "rfkillUnblock",
                command: "rfkill unblock wifi"
            });
        }
        if (hardBlocked) {
            out.push({
                message: "Wi-Fi is hard-blocked by a hardware switch or airplane mode. Enable it physically on this machine.",
                fix: "",
                command: ""
            });
        }
        return out;
    }

    // ------------------------------------------------------------------ helpers

    function savedProfileForSsid(ssid) {
        const list = savedWifiProfiles;
        for (let i = 0; i < list.length; i++) {
            if (list[i].ssid === ssid)
                return list[i];
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].ssid === "" && list[i].name === ssid)
                return list[i];
        }
        return null;
    }

    function isBusy(key) {
        return !!busyMap[key];
    }

    // "connecting" / "disconnecting" while a row is changing link state —
    // because of an action we are running on it, or because NetworkManager
    // reports it (autoconnect, a profile coming up) — else "".
    // [state] is the profile's or device's nmcli STATE, "" when unknown.
    function transition(key, state) {
        const op = busyMap[key] || "";
        if (op === "wifiConnect" || op === "profileUp" || op === "deviceConnect"
                || state.startsWith("activating") || state.startsWith("connecting"))
            return "connecting";
        if (op === "wifiDisconnect" || op === "profileDown" || op === "deviceDisconnect"
                || state.startsWith("deactivating"))
            return "disconnecting";
        return "";
    }

    readonly property bool anythingBusy: Object.keys(busyMap).length > 0

    function describeNetwork(view) {
        const ap = view.ap;
        const parts = [ap.signal + "%", ap.secured ? ap.security : "Open"];
        if (ap.freq !== "")
            parts.push(ap.freq);
        if (ap.rate !== "")
            parts.push(ap.rate);
        return parts.join(" · ");
    }

    function describeSavedWifi(profile) {
        const parts = ["Saved"];
        if (profile.lastUsed !== "")
            parts.push("last used " + profile.lastUsed);
        if (profile.isActive)
            parts.push("active on " + profile.device);
        return parts.join(" · ");
    }

    function describeWired(profile) {
        const parts = [];
        if (profile.device !== "")
            parts.push(profile.device);
        parts.push("priority " + profile.autoconnectPriority);
        if (profile.isActive)
            parts.push("active");
        if (!profile.autoconnect)
            parts.push("autoconnect off");
        return parts.join(" · ");
    }

    function wifiProfileName(profile) {
        return profile.ssid !== "" ? profile.ssid : profile.name;
    }

    function scanAgeLabel() {
        if (lastScanMs === 0)
            return "";
        const seconds = Math.floor((Date.now() - lastScanMs) / 1000);
        if (seconds < 5)
            return "Last scan just now";
        if (seconds < 60)
            return "Last scan " + seconds + "s ago";
        return "Last scan " + Math.floor(seconds / 60) + "m ago";
    }

    function signalBars(signal) {
        if (signal >= 80)
            return 4;
        if (signal >= 55)
            return 3;
        if (signal >= 30)
            return 2;
        if (signal > 0)
            return 1;
        return 0;
    }

    function fixableIssues() {
        return issues.filter(i => i.fix !== "");
    }

    function fixCommandPreview() {
        const out = [];
        for (let i = 0; i < issues.length; i++) {
            if (issues[i].command !== "")
                out.push(issues[i].command);
        }
        return out;
    }

    // ----------------------------------------------------------------- refresh

    Process {
        id: snapshotProc
        stdout: StdioCollector {
            id: snapshotOut
            onStreamFinished: root._ingestSnapshot(text, false)
        }
        stderr: StdioCollector {}
        onExited: exitCode => {
            root.refreshing = false;
            if (exitCode !== 0 && !root.initialized) {
                root.statusError = "Could not read the network state.";
                root.initialized = true;
            }
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: root._ingestSnapshot(text, true)
        }
        stderr: StdioCollector {}
        onExited: {
            root.scanning = false;
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            id: actionOut
        }
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: exitCode => root._ingestAction(actionOut.text, actionErr.text, exitCode)
    }

    Process {
        id: propsProc
        stdout: StdioCollector {
            id: propsOut
            onStreamFinished: root._ingestProperties(text)
        }
        stderr: StdioCollector {}
        onExited: {
            root.propertiesLoading = false;
        }
    }

    Process {
        id: sudoProc
        stdinEnabled: true
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

    Timer {
        interval: 2500
        running: root.panelOpen
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 15000
        running: !root.panelOpen
        repeat: true
        onTriggered: root.refresh()
    }

    function refresh() {
        if (refreshing || scanning) {
            refreshQueued = true;
            return;
        }
        refreshing = true;
        const args = [helperPath, "snapshot"];
        if (wifiIfname !== "")
            args.push("--ifname", wifiIfname);
        snapshotProc.exec(["python3"].concat(args));
    }

    function scanNow() {
        if (scanning || !nmRunning)
            return;
        if (!wifiEnabled) {
            errorMessage = "Wi-Fi is turned off, cannot scan.";
            return;
        }
        errorMessage = "";
        bannerMessage = "";
        scanning = true;
        const args = [helperPath, "snapshot", "--rescan"];
        if (wifiIfname !== "")
            args.push("--ifname", wifiIfname);
        scanProc.exec(["python3"].concat(args));
    }

    function setWifiIfnameByIndex(index) {
        const labels = wifiIfnameLabels;
        if (index < 0 || index >= labels.length)
            return;
        wifiIfname = index === 0 ? "" : labels[index];
        scanNow();
    }

    function _ingestSnapshot(raw, fromScan) {
        let parsed;
        try {
            parsed = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            initialized = true;
            return;
        }
        nmcliMissing = !!parsed.nmcliMissing;
        nmRunning = !!parsed.running;
        statusError = parsed.statusError || "";
        if (statusError !== "" && errorMessage === "")
            errorDetail = parsed.statusDetail || "";
        wifiEnabled = !!parsed.wifiEnabled;
        wifiHwEnabled = parsed.wifiHwEnabled !== false;
        devices = parsed.devices || [];
        profiles = parsed.profiles || [];
        aps = parsed.aps || [];
        service = parsed.service || {
            active: "unknown",
            enabled: "unknown"
        };
        softBlocked = !!(parsed.rfkill && parsed.rfkill.soft);
        hardBlocked = !!(parsed.rfkill && parsed.rfkill.hard);
        if (fromScan)
            lastScanMs = Date.now();
        initialized = true;
    }

    // ----------------------------------------------------------------- actions

    function _runOp(name, args, busyKey, successMessage) {
        if (_busyKey !== "")
            return;
        errorMessage = "";
        errorDetail = "";
        bannerMessage = "";
        _busyKey = busyKey;
        _successMessage = successMessage || "";
        _setBusy(busyKey, name);
        actionProc.exec(["python3", helperPath, "op", name, JSON.stringify(args)]);
    }

    // [busy] is the running op's name (or false to clear it).
    function _setBusy(key, busy) {
        const next = Object.assign({}, busyMap);
        if (busy)
            next[key] = busy;
        else
            delete next[key];
        busyMap = next;
    }

    function _ingestAction(stdout, stderr, exitCode) {
        const key = _busyKey;
        const success = _successMessage;
        _busyKey = "";
        _successMessage = "";
        if (key !== "")
            _setBusy(key, false);

        let parsed = null;
        try {
            parsed = JSON.parse((stdout || "").trim());
        } catch (e) {
            parsed = null;
        }
        if (!parsed) {
            const err = (stderr || "").trim();
            errorMessage = err !== "" ? err : "The action failed.";
            refresh();
            return;
        }
        if (parsed.kind === "success") {
            bannerMessage = success;
            errorMessage = "";
            errorDetail = "";
            pendingSudoArgv = [];
            refresh();
            return;
        }
        errorMessage = parsed.message || "The action failed.";
        errorDetail = parsed.detail || "";
        if (parsed.kind === "wifiPassword" && key.indexOf("ap:") === 0)
            passwordNeededSsid = key.substring(3);
        if (parsed.kind === "needsAuth" && parsed.argv) {
            pendingSudoArgv = [parsed.argv];
        } else {
            pendingSudoArgv = [];
        }
        // wifiPassword errors are handled by the window, which reprompts.
        refresh();
    }

    function setWifiEnabled(enabled) {
        _runOp("wifiRadio", {
            enabled: enabled
        }, "wifi-toggle", enabled ? "Wi-Fi enabled." : "Wi-Fi disabled.");
    }

    function setEthernetEnabled(enabled) {
        _runOp("ethernet", {
            enabled: enabled,
            devices: ethernetDevices
        }, "eth-toggle", enabled ? "Ethernet connected." : "Ethernet disconnected.");
    }

    function connectDevice(name) {
        _runOp("deviceConnect", {
            device: name
        }, "dev:" + name, "Connecting " + name + "…");
    }

    function disconnectDevice(name) {
        _runOp("deviceDisconnect", {
            device: name
        }, "dev:" + name, "Disconnected " + name + ".");
    }

    function connectNetwork(view, password) {
        const ssid = view.ap.ssid;
        _runOp("wifiConnect", {
            ssid: ssid,
            uuid: view.uuid,
            password: password || "",
            ifname: wifiIfname,
            enterprise: view.ap.enterprise
        }, "ap:" + ssid, "Connected to " + ssid + ".");
    }

    function disconnectNetwork(view) {
        const device = connectedWifiDevice;
        _runOp("wifiDisconnect", {
            uuid: view.saved && view.saved.isActive ? view.uuid : "",
            device: device ? device.name : ""
        }, "ap:" + view.ap.ssid, "Disconnected from " + view.ap.ssid + ".");
    }

    function activateProfile(profile) {
        _runOp("profileUp", {
            uuid: profile.uuid
        }, "conn:" + profile.uuid, "Activated " + profile.name + ".");
    }

    function deactivateProfile(profile) {
        _runOp("profileDown", {
            uuid: profile.uuid
        }, "conn:" + profile.uuid, "Disconnected " + profile.name + ".");
    }

    function forgetProfile(profile) {
        _runOp("profileDelete", {
            uuid: profile.uuid
        }, "conn:" + profile.uuid, "Forgot " + profile.name + ".");
    }

    function setPreferredWired(profile) {
        _runOp("preferWired", {
            uuid: profile.uuid,
            wired: wiredProfiles
        }, "conn:" + profile.uuid, profile.name + " is now the preferred wired connection.");
    }

    function clearWiredPreference() {
        _runOp("clearWired", {
            wired: wiredProfiles
        }, "wired-preference", "Wired preference cleared.");
    }

    function unblockWifi() {
        _runOp("unblockWifi", {}, "wifi-unblock", "Wi-Fi radio unblocked.");
    }

    // -------------------------------------------------------------- properties

    function showDeviceProperties(device) {
        propertiesTitle = "Properties — " + device.name;
        propertiesLoading = true;
        propertyRows = [];
        propsProc.exec(["python3", helperPath, "props", "device", device.name, device.kind]);
    }

    function showProfileProperties(title, uuid) {
        propertiesTitle = "Properties — " + title;
        propertiesLoading = true;
        propertyRows = [];
        propsProc.exec(["python3", helperPath, "props", "profile", uuid]);
    }

    function showNetworkProperties(view) {
        const ap = view.ap;
        const rows = [["SSID", ap.ssid], ["BSSID", ap.bssid], ["Signal", ap.signal + "%"], ["Security", ap.secured ? ap.security : "Open"], ["Channel", ap.channel], ["Frequency", ap.freq], ["Rate", ap.rate], ["Mode", ap.mode], ["In use", ap.inUse ? "yes" : "no"], ["Saved", view.isSaved ? "yes" : "no"]];
        propertiesTitle = "Properties — " + ap.ssid;
        propertyRows = rows;
        if (view.uuid !== "") {
            propertiesLoading = true;
            _propertiesPrefix = rows;
            propsProc.exec(["python3", helperPath, "props", "profile", view.uuid]);
        } else {
            propertiesLoading = false;
            _propertiesPrefix = [];
        }
    }

    property var _propertiesPrefix: []

    function _ingestProperties(raw) {
        let parsed;
        try {
            parsed = JSON.parse((raw || "").trim() || "{}");
        } catch (e) {
            parsed = {};
        }
        if (parsed.error) {
            errorMessage = parsed.error.message || "Could not read the details.";
            errorDetail = parsed.error.detail || "";
            propertyRows = _propertiesPrefix;
            _propertiesPrefix = [];
            return;
        }
        const rows = parsed.rows || [];
        if (_propertiesPrefix.length > 0) {
            propertyRows = _propertiesPrefix.concat([["—", "—"]]).concat(rows);
            _propertiesPrefix = [];
        } else {
            propertyRows = rows;
        }
    }

    // -------------------------------------------------------------- privileged

    function sudoCommandPreview() {
        if (pendingSudoArgv.length > 0)
            return pendingSudoArgv.map(argv => "sudo " + argv.join(" "));
        return fixCommandPreview();
    }

    // Runs either the queued polkit-denied command or the fixes for the issues
    // listed at the top of the panel.
    function runPrivileged(password) {
        let commands = pendingSudoArgv;
        if (commands.length === 0) {
            commands = [];
            let hasRfkill = false;
            for (let i = 0; i < issues.length; i++) {
                if (issues[i].fix === "startService")
                    commands.push(["systemctl", "start", "NetworkManager.service"]);
                else if (issues[i].fix === "enableService")
                    commands.push(["systemctl", "enable", "NetworkManager.service"]);
                else if (issues[i].fix === "rfkillUnblock")
                    hasRfkill = true;
            }
            if (hasRfkill)
                commands.push(["rfkill", "unblock", "wifi"]);
        }
        if (commands.length === 0)
            return false;
        sudoRunning = true;
        sudoError = "";
        errorMessage = "";
        _sudoPassword = password;
        sudoProc.exec(["python3", helperPath, "sudo", JSON.stringify(commands)]);
        return true;
    }

    function _ingestSudo(stdout, stderr, exitCode) {
        sudoRunning = false;
        _sudoPassword = "";
        let parsed = null;
        try {
            parsed = JSON.parse((stdout || "").trim());
        } catch (e) {
            parsed = null;
        }
        if (parsed && parsed.kind === "wrongPassword") {
            sudoError = "Incorrect password — try again.";
            return;
        }
        if (parsed && parsed.kind === "failure") {
            sudoError = parsed.detail || "The command failed.";
            return;
        }
        if (parsed && parsed.kind === "success") {
            sudoError = "";
            errorMessage = "";
            errorDetail = "";
            pendingSudoArgv = [];
            bannerMessage = "Applied with administrator rights.";
            // Give the daemon a moment to come up before reading state back.
            settleTimer.restart();
            return;
        }
        const err = (stderr || "").trim();
        sudoError = err !== "" ? err : "Failed to run the command.";
    }

    Timer {
        id: settleTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
