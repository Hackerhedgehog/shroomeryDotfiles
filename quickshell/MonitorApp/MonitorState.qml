pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared
// Live Hyprland geometry, the draft the user is editing, the managed block in
// monitors.lua, and layout profiles shared with the Flutter control_controls app.
Singleton {
    id: root

    readonly property string configPath: Paths.hyprMonitors
    readonly property string profilesDir: Paths.monitorProfiles
    readonly property var scalePresets: [1, 1.25, 1.5, 1.75, 2]
    readonly property var defaultModePresets: ["preferred", "highres", "highrr", "highres highrr"]
    readonly property var defaultPositionPresets: ["auto"]
    readonly property var defaultScalePresets: ["1", "1.25", "1.5", "1.75", "2"]
    readonly property var transformLabels: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]

    property var draft: []
    property var baseline: []
    property var defaultRule: ({
        mode: "highres highrr",
        position: "auto",
        scale: "1"
    })
    property var baselineDefault: ({
        mode: "highres highrr",
        position: "auto",
        scale: "1"
    })
    property var profiles: []
    property string selectedName: ""
    property bool defaultRuleSelected: false
    property bool busy: false
    property bool initialized: false
    property bool liveAheadOfConfig: false
    property bool awaitingConfigPersist: false
    property bool configMissing: false
    property string errorMessage: ""
    property string bannerMessage: ""
    property string activeProfileId: ""
    // Monitor pinned at 0,0. The X primary output (xrandr --output NAME
    // --primary) when there is one, so the anchor is a deliberate user choice
    // rather than whatever output happens to be focused.
    property string anchorName: ""
    property string primaryName: ""
    // The primary the user has picked but not applied yet. Staged like every
    // other control on the panel: nothing runs until Apply. Seeded from
    // primaryName on every refresh, so Revert drops the choice.
    property string draftPrimary: ""
    // The output named by the managed xrandr line in monitors.lua, if any.
    property string configPrimary: ""

    property string _afterApply: ""
    property string _profileWritePending: ""
    property string _profileWritePath: ""
    property string _applyStderr: ""
    property string _configText: ""

    readonly property var selected: {
        const name = selectedName;
        const list = draft;
        if (defaultRuleSelected || name === "")
            return null;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        return null;
    }

    readonly property bool isDirty: {
        const _d = draft;
        const _b = baseline;
        const _r = defaultRule;
        const _br = baselineDefault;
        if (awaitingConfigPersist)
            return true;
        if (draftPrimary !== primaryName)
            return true;
        if (_r.mode !== _br.mode || _r.position !== _br.position || _r.scale !== _br.scale)
            return true;
        if (_d.length !== _b.length)
            return true;
        for (let i = 0; i < _d.length; i++) {
            let match = null;
            for (let j = 0; j < _b.length; j++) {
                if (_b[j].name === _d[i].name) {
                    match = _b[j];
                    break;
                }
            }
            if (!match || fingerprint(_d[i]) !== fingerprint(match))
                return true;
        }
        return false;
    }

    readonly property bool canSave: isDirty || liveAheadOfConfig

    // The config pins a primary the session is not actually using — usually
    // because XWayland was not up yet when Hyprland ran the startup command.
    // Silent when the config pins nothing, so it cannot nag about a primary
    // that was set outside the panel and never meant to be persisted.
    readonly property bool primaryOutOfSync: configPrimary !== "" && primaryName !== "" && configPrimary !== primaryName

    // Disabled outputs have no place on the arrangement canvas (Hyprland gives
    // them no size or position), so they get their own list in the panel.
    readonly property var enabledMonitors: draft.filter(m => !m.disabled)
    readonly property var disabledMonitors: draft.filter(m => m.disabled)

    // The staged primary, but only while it names an output that is actually
    // on: xrandr cannot make a switched-off display primary.
    readonly property string applicablePrimary: {
        const name = draftPrimary;
        const list = draft;
        if (name === "")
            return "";
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i].disabled ? "" : name;
        }
        return "";
    }

    readonly property string statusText: {
        if (busy)
            return "Working…";
        if (errorMessage !== "")
            return errorMessage;
        if (isDirty)
            return "Unapplied changes.";
        if (liveAheadOfConfig)
            return "Applied to Hyprland but not written to the config yet.";
        if (primaryOutOfSync)
            return "Primary is " + primaryName + ", but the config asks for " + configPrimary + ".";
        if (bannerMessage !== "")
            return bannerMessage;
        return "In sync with Hyprland.";
    }

    readonly property var resolutionModel: {
        const m = selected;
        if (!m)
            return [];
        const seen = {};
        const out = [];
        const modes = m.availableModes || [];
        for (let i = 0; i < modes.length; i++) {
            const key = modes[i].width + "x" + modes[i].height;
            if (!seen[key]) {
                seen[key] = true;
                out.push(key);
            }
        }
        const current = m.width + "x" + m.height;
        if (!seen[current])
            out.push(current);
        return out;
    }

    readonly property int resolutionIndex: {
        const m = selected;
        const model = resolutionModel;
        if (!m)
            return -1;
        const key = m.width + "x" + m.height;
        return model.indexOf(key);
    }

    readonly property var refreshModel: {
        const m = selected;
        if (!m)
            return [];
        return refreshModesFor(m, m.width, m.height);
    }

    readonly property var refreshLabels: {
        const model = refreshModel;
        const out = [];
        for (let i = 0; i < model.length; i++)
            out.push(formatHz(model[i]));
        return out;
    }

    readonly property var defaultModeModel: {
        const rule = defaultRule;
        return _presetModel(defaultModePresets, rule.mode);
    }
    readonly property int defaultModeIndex: {
        const rule = defaultRule;
        return _presetIndex(defaultModePresets, rule.mode);
    }
    readonly property var defaultPositionModel: {
        const rule = defaultRule;
        return _presetModel(defaultPositionPresets, rule.position);
    }
    readonly property int defaultPositionIndex: {
        const rule = defaultRule;
        return _presetIndex(defaultPositionPresets, rule.position);
    }
    readonly property var defaultScaleModel: {
        const rule = defaultRule;
        return _presetModel(defaultScalePresets, String(rule.scale));
    }
    readonly property int defaultScaleIndex: {
        const rule = defaultRule;
        return _presetIndex(defaultScalePresets, String(rule.scale));
    }

    readonly property int refreshIndex: {
        const m = selected;
        const model = refreshModel;
        if (!m || model.length === 0)
            return -1;
        for (let i = 0; i < model.length; i++) {
            if (Math.abs(model[i] - m.refreshRate) < 0.01)
                return i;
        }
        return 0;
    }

    readonly property var scaleModel: {
        const m = selected;
        const labels = [];
        for (let i = 0; i < scalePresets.length; i++)
            labels.push(formatScale(scalePresets[i]));
        if (m) {
            let found = false;
            for (let i = 0; i < scalePresets.length; i++) {
                if (Math.abs(scalePresets[i] - m.scale) < 0.001) {
                    found = true;
                    break;
                }
            }
            if (!found)
                labels.push(formatScale(m.scale));
        }
        labels.push("Custom…");
        return labels;
    }

    readonly property int scaleIndex: {
        const m = selected;
        const model = scaleModel;
        if (!m)
            return -1;
        const label = formatScale(m.scale);
        const idx = model.indexOf(label);
        return idx >= 0 ? idx : 0;
    }

    readonly property var mirrorModel: {
        const m = selected;
        const list = draft;
        const out = [{
                text: "None",
                value: ""
            }];
        if (!m)
            return out;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name !== m.name) {
                out.push({
                    text: list[i].name,
                    value: list[i].name
                });
            }
        }
        return out;
    }

    readonly property var mirrorLabels: {
        const model = mirrorModel;
        const out = [];
        for (let i = 0; i < model.length; i++)
            out.push(model[i].text);
        return out;
    }

    readonly property int mirrorIndex: {
        const m = selected;
        const model = mirrorModel;
        if (!m)
            return 0;
        for (let i = 0; i < model.length; i++) {
            if (model[i].value === m.mirrorOf)
                return i;
        }
        return 0;
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            root.configMissing = false;
            root._configText = text();
        }
        onLoadFailed: {
            root.configMissing = true;
            root._configText = "";
        }
        onSaved: {
            root.liveAheadOfConfig = false;
            root.awaitingConfigPersist = false;
            root.configMissing = false;
            root.errorMessage = "";
            root.busy = false;
            reload();
        }
        onSaveFailed: {
            root.awaitingConfigPersist = true;
            root.errorMessage = "The monitors config is not writable by your user.";
            root.busy = false;
        }
    }

    FileView {
        id: profileFile
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (root._profileWritePending !== "") {
                const pending = root._profileWritePending;
                root._profileWritePending = "";
                setText(pending);
            }
        }
        onLoadFailed: {
            if (root._profileWritePending !== "") {
                const pending = root._profileWritePending;
                root._profileWritePending = "";
                setText(pending);
            }
        }
        onSaved: {
            root._profileWritePending = "";
            root.reloadProfiles();
            root.busy = false;
        }
        onSaveFailed: {
            root._profileWritePending = "";
            root.errorMessage = "Failed to save the layout profile.";
            root.busy = false;
        }
    }

    Process {
        id: listProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: root._ingestMonitors(text)
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.errorMessage = "Hyprland is not answering: monitors could not be listed.";
                root.busy = false;
            }
        }
    }

    Process {
        id: applyProc
        stderr: StdioCollector {
            id: applyErr
            onStreamFinished: root._applyStderr = text
        }
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                const detail = root._applyStderr.trim();
                root.errorMessage = detail !== "" ? detail : "Failed to apply the layout to Hyprland.";
                root.busy = false;
                root._afterApply = "";
                return;
            }
            root.errorMessage = "";
            // A new scale changes the per-monitor mouse speed (InputApp); Hyprland
            // sends no event for it.
            Quickshell.execDetached([Paths.inputScript, "speed"]);
            if (root._afterApply === "writeConfig")
                root.liveAheadOfConfig = true;
            else
                root.liveAheadOfConfig = true;
            listProc.running = false;
            listProc.running = true;
            primaryProc.running = false;
            primaryProc.running = true;
        }
    }

    Process {
        id: profilesProc
        stdout: StdioCollector {
            id: profilesOut
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "[]");
                    root.profiles = parsed;
                } catch (e) {
                    root.profiles = [];
                }
            }
        }
    }

    Process {
        id: mkdirProc
        onExited: {
            if (root._profileWritePath !== "" && root._profileWritePending !== "") {
                profileFile.path = root._profileWritePath;
            }
        }
    }

    Process {
        id: deleteProc
        onExited: root.reloadProfiles()
    }

    Process {
        id: primaryProc
        command: ["xrandr", "--query"]
        stdout: StdioCollector {
            onStreamFinished: root._ingestPrimary(text)
        }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.primaryName = "";
                root.draftPrimary = "";
            }
        }
    }

    function refresh() {
        busy = true;
        errorMessage = "";
        _afterApply = "refresh";
        configFile.reload();
        listProc.running = false;
        listProc.running = true;
        primaryProc.running = false;
        primaryProc.running = true;
        reloadProfiles();
    }

    function _ingestPrimary(text) {
        const lines = String(text).split("\n");
        let found = "";
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf(" connected primary") < 0)
                continue;
            found = lines[i].split(" ")[0];
            break;
        }
        primaryName = found;
        // xrandr is the truth for what is primary right now, so a fresh read
        // is also the new starting point for the draft.
        draftPrimary = found;
    }

    // Stage a primary. Applied by Apply (xrandr --output NAME --primary) and
    // persisted by Save; until then it only moves the arrangement anchor.
    function setPrimary(name) {
        if (busy || name === "" || name === draftPrimary)
            return;
        const m = monitorNamed(name);
        if (!m || m.disabled)
            return;
        draftPrimary = name;
    }

    // The primary output can arrive after the monitor list; re-anchor both the
    // draft and the baseline by the same offset so nothing looks dirty just
    // because the origin moved.
    function _reanchor() {
        const next = _resolveAnchor(draft.length ? draft : baseline);
        if (next === anchorName)
            return;
        anchorName = next;
        if (baseline.length)
            baseline = _normalize(baseline);
        if (draft.length)
            draft = _normalize(draft);
    }

    onPrimaryNameChanged: _reanchor()
    onDraftPrimaryChanged: _reanchor()

    function reloadProfiles() {
        profilesProc.exec(["python3", "-c", "import json, glob, os\n" + "d = " + JSON.stringify(Paths.monitorProfiles) + "\n" + "os.makedirs(d, exist_ok=True)\n" + "out = []\n" + "for p in glob.glob(os.path.join(d, '*.json')):\n" + "    try:\n" + "        with open(p) as f:\n" + "            out.append(json.load(f))\n" + "    except Exception:\n" + "        pass\n" + "out.sort(key=lambda x: (0 if x.get('id')=='default' else 1, str(x.get('name','')).lower()))\n" + "print(json.dumps(out))\n"]);
    }

    function select(name) {
        selectedName = name;
        defaultRuleSelected = false;
    }

    function selectDefaultRule() {
        selectedName = "";
        defaultRuleSelected = true;
    }

    function setEnabled(enabled) {
        _updateSelected(m => {
            const n = cloneMonitor(m);
            n.disabled = !enabled;
            // A switched-off output is reported as 0x0 with no refresh rate.
            // Seed it from its first advertised mode so re-enabling asks for a
            // real mode instead of "0x0@0".
            if (enabled && (n.width <= 0 || n.height <= 0)) {
                const modes = n.availableModes || [];
                if (modes.length > 0) {
                    n.width = modes[0].width;
                    n.height = modes[0].height;
                    n.refreshRate = modes[0].refreshRate;
                }
            }
            return n;
        }, true);
    }

    function setResolution(resKey) {
        const m = selected;
        if (!m || !resKey)
            return;
        const parts = resKey.split("x");
        const w = parseInt(parts[0]);
        const h = parseInt(parts[1]);
        const matching = (m.availableModes || []).filter(mode => mode.width === w && mode.height === h);
        let mode = matching.find(item => Math.abs(item.refreshRate - m.refreshRate) < 0.01);
        if (!mode)
            mode = matching.length ? matching[0] : {
                width: w,
                height: h,
                refreshRate: m.refreshRate
            };
        setMode(mode.width, mode.height, mode.refreshRate);
    }

    function setRefreshByIndex(index) {
        const model = refreshModel;
        if (index < 0 || index >= model.length)
            return;
        const m = selected;
        if (!m)
            return;
        setMode(m.width, m.height, model[index]);
    }

    function setScaleByIndex(index) {
        const model = scaleModel;
        if (index < 0 || index >= model.length)
            return;
        if (model[index] === "Custom…")
            return false;
        setScale(parseFloat(model[index]));
        return true;
    }

    function setScale(value) {
        const n = Number(value);
        if (!(n > 0))
            return;
        _updateSelected(m => {
            const c = cloneMonitor(m);
            const swaps = _swapsAxes(c);
            c.scale = validScale(swaps ? c.height : c.width, swaps ? c.width : c.height, n);
            return c;
        }, true);
    }

    function setTransform(value) {
        _updateSelected(m => {
            const c = cloneMonitor(m);
            c.transform = value;
            return c;
        }, true);
    }

    function setMirrorByIndex(index) {
        const model = mirrorModel;
        if (index < 0 || index >= model.length)
            return;
        _updateSelected(m => {
            const c = cloneMonitor(m);
            c.mirrorOf = model[index].value;
            return c;
        }, true);
    }

    function setMode(width, height, refreshRate) {
        _updateSelected(m => {
            const c = cloneMonitor(m);
            c.width = width;
            c.height = height;
            c.refreshRate = refreshRate;
            return c;
        }, true);
    }

    function moveMonitor(name, x, y) {
        const next = draft.map(m => {
            if (m.name !== name)
                return m;
            const c = cloneMonitor(m);
            c.x = Math.round(x);
            c.y = Math.round(y);
            return c;
        });
        draft = _normalize(next);
    }

    // Called once when a drag ends: weld the monitor to its nearest neighbour
    // and re-anchor the layout. Nothing touches the draft while the drag is in
    // flight, so the canvas delegates survive the whole gesture.
    function dropMonitor(name, x, y) {
        const p = weldPosition(draft, name, x, y);
        moveMonitor(name, p.x, p.y);
    }

    function setDefaultRuleField(field, value) {
        const next = {
            mode: defaultRule.mode,
            position: defaultRule.position,
            scale: defaultRule.scale
        };
        next[field] = value;
        defaultRule = next;
    }

    function revert() {
        refresh();
    }

    function apply() {
        if (busy)
            return;
        busy = true;
        errorMessage = "";
        _afterApply = "markLive";
        _startApply();
    }

    function save() {
        if (busy)
            return;
        busy = true;
        errorMessage = "";
        _afterApply = "writeConfig";
        _startApply();
    }

    function saveProfileAs(name) {
        const trimmed = (name || "").trim();
        if (trimmed === "")
            return;
        busy = true;
        const profile = {
            id: Date.now().toString(),
            name: trimmed,
            updatedAt: new Date().toISOString(),
            defaultRule: {
                mode: defaultRule.mode,
                position: defaultRule.position,
                scale: defaultRule.scale
            },
            monitors: draft.map(m => ({
                    name: m.name,
                    width: m.width,
                    height: m.height,
                    refreshRate: m.refreshRate,
                    x: m.x,
                    y: m.y,
                    scale: m.scale,
                    transform: m.transform,
                    mirrorOf: m.mirrorOf || "",
                    disabled: !!m.disabled
                }))
        };
        _profileWritePending = JSON.stringify(profile, null, 2) + "\n";
        _profileWritePath = profilesDir + "/" + profile.id + ".json";
        mkdirProc.exec(["mkdir", "-p", profilesDir]);
    }

    function applyProfile(id) {
        let profile = null;
        for (let i = 0; i < profiles.length; i++) {
            if (profiles[i].id === id) {
                profile = profiles[i];
                break;
            }
        }
        if (!profile)
            return;
        const next = draft.map(live => {
            const c = cloneMonitor(live);
            const list = profile.monitors || [];
            for (let i = 0; i < list.length; i++) {
                if (list[i].name === live.name) {
                    const pm = list[i];
                    c.width = pm.width;
                    c.height = pm.height;
                    c.refreshRate = pm.refreshRate;
                    c.x = pm.x;
                    c.y = pm.y;
                    c.scale = pm.scale;
                    c.transform = pm.transform;
                    c.mirrorOf = pm.mirrorOf || "";
                    c.disabled = !!pm.disabled;
                    break;
                }
            }
            return c;
        });
        draft = _normalize(next);
        if (profile.defaultRule) {
            defaultRule = {
                mode: profile.defaultRule.mode || "preferred",
                position: profile.defaultRule.position || "auto",
                scale: String(profile.defaultRule.scale || "1")
            };
        }
        activeProfileId = id;
        apply();
    }

    function deleteProfile(id) {
        if (id === "default") {
            errorMessage = "The Default profile cannot be deleted.";
            return;
        }
        deleteProc.exec(["rm", "-f", profilesDir + "/" + id + ".json"]);
        if (activeProfileId === id)
            activeProfileId = "";
    }

    // Hyprland quantises scale to 1/120 steps and then nudges it until the
    // logical size (pixels / scale) lands on a whole number. The layout maths
    // has to use that corrected value: with the raw requested scale every
    // position is a pixel or two off, which is exactly what makes Hyprland
    // reject an arrangement that looked flush in the canvas.
    function _isWhole(v) {
        return Math.abs(v - Math.round(v)) < 1e-6;
    }

    function _scaleFits(pw, ph, steps) {
        if (steps <= 0)
            return false;
        return _isWhole(pw * 120 / steps) && _isWhole(ph * 120 / steps);
    }

    function validScale(pw, ph, requested) {
        const n = Number(requested);
        if (!(n > 0))
            return 1;
        const wanted = Math.round(n * 120);
        if (pw <= 0 || ph <= 0 || _scaleFits(pw, ph, wanted))
            return wanted / 120;
        for (let i = 1; i <= 90; i++) {
            if (_scaleFits(pw, ph, wanted + i))
                return (wanted + i) / 120;
            if (_scaleFits(pw, ph, wanted - i))
                return (wanted - i) / 120;
        }
        return wanted / 120;
    }

    function _swapsAxes(m) {
        return m.transform === 1 || m.transform === 3 || m.transform === 5 || m.transform === 7;
    }

    // The scale Hyprland will actually use for this monitor. Stored back into
    // the draft on every change so the app never shows a scale Hyprland would
    // silently replace.
    function effectiveScale(m) {
        const swaps = _swapsAxes(m);
        return validScale(swaps ? m.height : m.width, swaps ? m.width : m.height, m.scale);
    }

    function layoutWidth(m) {
        const px = _swapsAxes(m) ? m.height : m.width;
        return Math.max(1, Math.round(px / effectiveScale(m)));
    }

    function layoutHeight(m) {
        const px = _swapsAxes(m) ? m.width : m.height;
        return Math.max(1, Math.round(px / effectiveScale(m)));
    }

    function formatRefresh(r) {
        if (r === Math.round(r))
            return String(Math.round(r));
        return Number(r).toFixed(2);
    }

    function formatScale(s) {
        const n = Number(s);
        if (n === Math.round(n))
            return String(Math.round(n));
        return String(Number(n.toFixed(6)));
    }

    function formatHz(r) {
        return formatRefresh(r) + " Hz";
    }

    function describeMonitor(m) {
        const geo = m.width + "x" + m.height + " @ " + formatHz(m.refreshRate);
        return m.disabled ? "Disabled · " + geo : geo;
    }

    function _presetModel(presets, current) {
        const out = presets.slice();
        if (out.indexOf(current) < 0)
            out.push(current);
        out.push("Custom…");
        return out;
    }

    function _presetIndex(presets, current) {
        const out = presets.slice();
        if (out.indexOf(current) < 0)
            out.push(current);
        return out.indexOf(current);
    }

    function refreshModesFor(m, w, h) {
        const matching = (m.availableModes || []).filter(mode => mode.width === w && mode.height === h);
        const seen = {};
        const unique = [];
        for (let i = 0; i < matching.length; i++) {
            const key = Math.round(matching[i].refreshRate * 100);
            if (!seen[key]) {
                seen[key] = true;
                unique.push(matching[i].refreshRate);
            }
        }
        unique.sort((a, b) => a - b);
        if (unique.length === 0)
            unique.push(m.refreshRate);
        return unique;
    }

    function fingerprint(m) {
        return [m.name, m.width, m.height, m.refreshRate, m.x, m.y, m.scale, m.transform, m.mirrorOf || "", !!m.disabled].join("|");
    }

    function cloneMonitor(m) {
        return {
            name: m.name,
            make: m.make || "",
            model: m.model || "",
            serial: m.serial || "",
            description: m.description || "",
            width: m.width,
            height: m.height,
            refreshRate: m.refreshRate,
            x: m.x,
            y: m.y,
            scale: m.scale,
            transform: m.transform,
            disabled: !!m.disabled,
            mirrorOf: m.mirrorOf || "",
            dpmsStatus: m.dpmsStatus !== false,
            vrr: !!m.vrr,
            focused: !!m.focused,
            availableModes: (m.availableModes || []).map(mode => ({
                    width: mode.width,
                    height: mode.height,
                    refreshRate: mode.refreshRate
                })),
            extra: m.extra ? Object.assign({}, m.extra) : {}
        };
    }

    function parseMode(raw) {
        const cleaned = String(raw).trim().replace(/Hz$/i, "");
        const match = cleaned.match(/^(\d+)x(\d+)@([\d.]+)$/);
        if (!match)
            return null;
        return {
            width: parseInt(match[1]),
            height: parseInt(match[2]),
            refreshRate: parseFloat(match[3])
        };
    }

    function luaString(value) {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function luaScaleLiteral(scale) {
        const n = parseFloat(scale);
        if (isNaN(n))
            return luaString(scale);
        return formatScale(n);
    }

    function toHyprSpec(m) {
        const output = luaString(m.name);
        if (m.disabled)
            return "hl.monitor({ output = " + output + ", disabled = true })";
        if (m.width <= 0 || m.height <= 0)
            return "hl.monitor({ output = " + output + ", mode = \"preferred\", position = \"auto\", scale = " + formatScale(m.scale) + ", disabled = false })";
        return "hl.monitor({ output = " + output + ", mode = " + luaString(m.width + "x" + m.height + "@" + formatRefresh(m.refreshRate)) + ", position = " + luaString(m.x + "x" + m.y) + ", scale = " + formatScale(m.scale) + ", transform = " + m.transform + ", mirror = " + luaString(m.mirrorOf || "") + ", disabled = false })";
    }

    function toConfigLine(m) {
        const output = luaString(m.name);
        if (m.disabled) {
            return "hl.monitor({\n  output = " + output + ",\n  disabled = true,\n})";
        }
        if (m.width <= 0 || m.height <= 0) {
            return "hl.monitor({\n  output = " + output + ",\n  mode = \"preferred\",\n  position = \"auto\",\n  scale = " + formatScale(m.scale) + ",\n  disabled = false,\n})";
        }
        return "hl.monitor({\n  output = " + output + ",\n  mode = " + luaString(m.width + "x" + m.height + "@" + formatRefresh(m.refreshRate)) + ",\n  position = " + luaString(m.x + "x" + m.y) + ",\n  scale = " + formatScale(m.scale) + ",\n  transform = " + m.transform + ",\n  mirror = " + luaString(m.mirrorOf || "") + ",\n  disabled = false,\n})";
    }

    function defaultRuleSpec(rule) {
        const r = rule || defaultRule;
        return "hl.monitor({ output = \"\", mode = " + luaString(r.mode) + ", position = " + luaString(r.position) + ", scale = " + luaScaleLiteral(r.scale) + " })";
    }

    function defaultRuleConfig(rule) {
        const r = rule || defaultRule;
        return "hl.monitor({\n  output = \"\",\n  mode = " + luaString(r.mode) + ",\n  position = " + luaString(r.position) + ",\n  scale = " + luaScaleLiteral(r.scale) + ",\n})";
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // hl.monitor() has no notion of a primary — it is an X concept — so the
    // managed block persists it the way conf/autostart.lua runs anything else
    // at startup. XWayland is often not up yet when Hyprland gets here, so the
    // command retries for a few seconds rather than failing silently.
    function primaryConfigLine(name) {
        return "hl.exec_cmd(" + luaString("for _ in 1 2 3 4 5 6 7 8 9 10; do xrandr --output " + shellQuote(name) + " --primary 2>/dev/null && break; sleep 1; done") + ")";
    }

    // --- Layout rules -------------------------------------------------
    //
    // The anchor monitor sits at 0,0 and everything else is expressed
    // relative to it. Every monitor is welded flush against a neighbour, so
    // the desktop can never end up with a gap or an overlap.

    function monitorNamed(name) {
        const list = draft;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        return null;
    }

    function _rect(m) {
        return {
            name: m.name,
            x: m.x,
            y: m.y,
            w: layoutWidth(m),
            h: layoutHeight(m)
        };
    }

    function _participates(m) {
        return !m.disabled && !(m.mirrorOf || "");
    }

    function _neighbours(list, name) {
        const out = [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].name !== name && _participates(list[i]))
                out.push(_rect(list[i]));
        }
        return out;
    }

    function _hits(x, y, w, h, o) {
        return x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
    }

    function _overlapsAny(x, y, w, h, others) {
        for (let i = 0; i < others.length; i++) {
            if (_hits(x, y, w, h, others[i]))
                return true;
        }
        return false;
    }

    function _clamp(v, lo, hi) {
        if (lo > hi)
            return Math.round((lo + hi) / 2);
        return Math.max(lo, Math.min(hi, v));
    }

    // Last resort for a drop that cannot be welded anywhere without a clash:
    // shove the monitor out of each collision along its shallowest axis.
    function _pushFree(x, y, w, h, others) {
        for (let guard = 0; guard < 64; guard++) {
            let hit = null;
            for (let i = 0; i < others.length; i++) {
                if (_hits(x, y, w, h, others[i])) {
                    hit = others[i];
                    break;
                }
            }
            if (!hit)
                break;
            const left = hit.x - w - x;
            const right = hit.x + hit.w - x;
            const up = hit.y - h - y;
            const down = hit.y + hit.h - y;
            const dx = Math.abs(left) <= Math.abs(right) ? left : right;
            const dy = Math.abs(up) <= Math.abs(down) ? up : down;
            if (Math.abs(dx) <= Math.abs(dy))
                x += dx;
            else
                y += dy;
        }
        return ({
                x: Math.round(x),
                y: Math.round(y)
            });
    }

    // Snap a dropped monitor flush against the nearest edge of the closest
    // neighbour. The offset along that shared edge is kept exactly where the
    // user let go (only clamped so the two edges still touch), so monitors
    // can still be slid up and down a shared border.
    function weldPosition(list, name, x, y) {
        const me = list.find(item => item.name === name);
        if (!me)
            return ({
                    x: Math.round(x),
                    y: Math.round(y)
                });
        const w = layoutWidth(me);
        const h = layoutHeight(me);
        const others = _neighbours(list, name);
        if (others.length === 0)
            return ({
                    x: 0,
                    y: 0
                });

        const dropX = Math.round(x);
        const dropY = Math.round(y);
        const candidates = [];
        for (let i = 0; i < others.length; i++) {
            const o = others[i];
            // Sliding along a shared border is free, but a drop that lands well
            // past the end of the border is pulled back until the two screens
            // still share a quarter of their shorter edge. Without that floor a
            // far drop welds on a one pixel sliver, which is technically
            // connected and useless in practice.
            const minTouchY = Math.max(1, Math.round(Math.min(h, o.h) * 0.25));
            const minTouchX = Math.max(1, Math.round(Math.min(w, o.w) * 0.25));
            const slideY = _clamp(dropY, o.y - h + minTouchY, o.y + o.h - minTouchY);
            candidates.push({
                x: o.x - w,
                y: slideY
            });
            candidates.push({
                x: o.x + o.w,
                y: slideY
            });
            const slideX = _clamp(dropX, o.x - w + minTouchX, o.x + o.w - minTouchX);
            candidates.push({
                x: slideX,
                y: o.y - h
            });
            candidates.push({
                x: slideX,
                y: o.y + o.h
            });
        }

        let best = null;
        let bestDist = Infinity;
        let fallback = null;
        let fallbackDist = Infinity;
        for (let i = 0; i < candidates.length; i++) {
            const c = candidates[i];
            const dx = c.x - dropX;
            const dy = c.y - dropY;
            const dist = dx * dx + dy * dy;
            if (dist < fallbackDist) {
                fallbackDist = dist;
                fallback = c;
            }
            if (_overlapsAny(c.x, c.y, w, h, others))
                continue;
            if (dist < bestDist) {
                bestDist = dist;
                best = c;
            }
        }
        if (best)
            return ({
                    x: Math.round(best.x),
                    y: Math.round(best.y)
                });
        return _pushFree(fallback.x, fallback.y, w, h, others);
    }

    // Re-weld one monitor in place. Used after a change that alters its
    // logical size (scale, resolution, rotation) so the arrangement stays
    // gap- and overlap-free without moving anything else.
    function _reweld(list, name) {
        const m = list.find(item => item.name === name);
        if (!m || !_participates(m))
            return list;
        const p = weldPosition(list, name, m.x, m.y);
        if (p.x === m.x && p.y === m.y)
            return list;
        return list.map(item => {
            if (item.name !== name)
                return item;
            const c = cloneMonitor(item);
            c.x = p.x;
            c.y = p.y;
            return c;
        });
    }

    function _resolveAnchor(list) {
        // The staged primary first, so picking one previews the arrangement
        // Apply would produce instead of waiting for xrandr to confirm it.
        const wanted = draftPrimary !== "" ? draftPrimary : primaryName;
        if (wanted !== "") {
            for (let i = 0; i < list.length; i++) {
                if (list[i].name === wanted && _participates(list[i]))
                    return wanted;
            }
        }
        if (anchorName !== "") {
            for (let i = 0; i < list.length; i++) {
                if (list[i].name === anchorName && _participates(list[i]))
                    return anchorName;
            }
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].focused && _participates(list[i]))
                return list[i].name;
        }
        for (let i = 0; i < list.length; i++) {
            if (_participates(list[i]))
                return list[i].name;
        }
        return list.length ? list[0].name : "";
    }

    // Put the anchor monitor at 0,0 and express every other monitor relative
    // to it, so the coordinates written to monitors.lua stay small and stable
    // instead of drifting with whatever origin Hyprland happens to report.
    function _normalize(list) {
        const anchor = _resolveAnchor(list);
        if (anchor === "")
            return list;
        let a = null;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === anchor) {
                a = list[i];
                break;
            }
        }
        if (!a || (a.x === 0 && a.y === 0))
            return list;
        const dx = a.x;
        const dy = a.y;
        return list.map(m => {
            const c = cloneMonitor(m);
            c.x = m.x - dx;
            c.y = m.y - dy;
            return c;
        });
    }

    function _updateSelected(updateFn, rearrange) {
        if (defaultRuleSelected || selectedName === "")
            return;
        const name = selectedName;
        let next = draft.map(m => m.name === name ? updateFn(m) : m);
        if (rearrange)
            next = _reweld(next, name);
        draft = _normalize(next);
    }

    function _startApply() {
        _applyStderr = "";
        const parts = [];
        for (let i = 0; i < draft.length; i++)
            parts.push("hyprctl eval " + shellQuote(toHyprSpec(draft[i])));
        parts.push("hyprctl eval " + shellQuote(defaultRuleSpec(defaultRule)));
        // Last in the chain: an X problem must not stop the Hyprland layout
        // from being applied, but it still has to surface as an error.
        if (applicablePrimary !== "" && applicablePrimary !== primaryName)
            parts.push("xrandr --output " + shellQuote(applicablePrimary) + " --primary");
        applyProc.exec(["bash", "-c", "set -euo pipefail; " + parts.join(" && ")]);
    }

    function _ingestMonitors(raw) {
        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (e) {
            errorMessage = "Hyprland returned unreadable monitor data.";
            busy = false;
            return;
        }
        if (!(parsed instanceof Array)) {
            errorMessage = "Hyprland returned unreadable monitor data.";
            busy = false;
            return;
        }

        const nameById = {};
        for (let i = 0; i < parsed.length; i++) {
            if (parsed[i] && parsed[i].name)
                nameById[parsed[i].id] = parsed[i].name;
        }

        let live = [];
        for (let i = 0; i < parsed.length; i++) {
            const rawMon = parsed[i];
            if (!rawMon || !rawMon.name)
                continue;
            const modes = [];
            const rawModes = rawMon.availableModes || [];
            for (let j = 0; j < rawModes.length; j++) {
                const mode = parseMode(rawModes[j]);
                if (mode)
                    modes.push(mode);
            }
            let mirrorOf = rawMon.mirrorOf === undefined || rawMon.mirrorOf === null ? "" : String(rawMon.mirrorOf);
            if (mirrorOf === "none")
                mirrorOf = "";
            else if (/^\d+$/.test(mirrorOf))
                mirrorOf = nameById[parseInt(mirrorOf)] || "";

            live.push({
                name: rawMon.name,
                make: rawMon.make || "",
                model: rawMon.model || "",
                serial: rawMon.serial || "",
                description: rawMon.description || "",
                width: rawMon.width || 0,
                height: rawMon.height || 0,
                refreshRate: rawMon.refreshRate || 0,
                x: rawMon.x || 0,
                y: rawMon.y || 0,
                scale: rawMon.scale || 1,
                transform: rawMon.transform || 0,
                disabled: !!rawMon.disabled,
                mirrorOf: mirrorOf,
                dpmsStatus: rawMon.dpmsStatus !== false,
                vrr: !!rawMon.vrr,
                focused: !!rawMon.focused,
                availableModes: modes,
                extra: {}
            });
        }

        const parsedConfig = _parseManagedBlock(_configText);
        configPrimary = parsedConfig.primary;
        live = _preserveDisabledGeometry(live, draft);
        live = _preserveDisabledGeometry(live, parsedConfig.monitors);
        anchorName = _resolveAnchor(live);
        live = _normalize(live);

        const prevSelected = selectedName;
        const wasDefault = defaultRuleSelected;
        const prevDraft = draft;
        baseline = live.map(cloneMonitor);

        // After an apply, what the user asked for stays on screen. Only the
        // hardware facts are refreshed from Hyprland, so a rule Hyprland
        // silently altered or rejected shows up as an unapplied change instead
        // of quietly resetting the panel to the old settings.
        const keepDraft = (_afterApply === "markLive" || _afterApply === "writeConfig") && prevDraft.length > 0;
        if (keepDraft) {
            draft = live.map(l => {
                let d = null;
                for (let i = 0; i < prevDraft.length; i++) {
                    if (prevDraft[i].name === l.name) {
                        d = prevDraft[i];
                        break;
                    }
                }
                if (!d)
                    return cloneMonitor(l);
                const c = cloneMonitor(d);
                c.make = l.make;
                c.model = l.model;
                c.serial = l.serial;
                c.description = l.description;
                c.availableModes = l.availableModes.map(mode => ({
                            width: mode.width,
                            height: mode.height,
                            refreshRate: mode.refreshRate
                        }));
                c.dpmsStatus = l.dpmsStatus;
                c.vrr = l.vrr;
                c.focused = l.focused;
                return c;
            });
        } else {
            draft = live.map(cloneMonitor);
        }

        if (parsedConfig.defaultRule)
            defaultRule = parsedConfig.defaultRule;
        if (_afterApply === "refresh" || _afterApply === "")
            baselineDefault = {
                mode: defaultRule.mode,
                position: defaultRule.position,
                scale: defaultRule.scale
            };

        if (wasDefault) {
            defaultRuleSelected = true;
            selectedName = "";
        } else if (prevSelected && live.some(m => m.name === prevSelected)) {
            selectedName = prevSelected;
            defaultRuleSelected = false;
        } else {
            const focused = live.find(m => m.focused);
            selectedName = focused ? focused.name : (live.length ? live[0].name : "");
            defaultRuleSelected = false;
        }

        if (_afterApply === "writeConfig") {
            _writeConfig();
        } else if (_afterApply === "refresh") {
            liveAheadOfConfig = false;
            awaitingConfigPersist = false;
            busy = false;
        } else {
            busy = false;
        }
        _afterApply = "";
        initialized = true;

        if (configMissing && bannerMessage === "")
            bannerMessage = "No monitors config yet. Saving will create it.";
    }

    function _preserveDisabledGeometry(live, prior) {
        if (!prior || prior.length === 0)
            return live;
        return live.map(m => {
            if (!m.disabled)
                return m;
            const p = prior.find(item => item.name === m.name);
            if (!p)
                return m;
            const c = cloneMonitor(m);
            c.width = p.width;
            c.height = p.height;
            c.refreshRate = p.refreshRate;
            c.x = p.x;
            c.y = p.y;
            c.scale = p.scale;
            c.transform = p.transform;
            c.mirrorOf = p.mirrorOf;
            return c;
        });
    }

    function _markerPairs() {
        return [["-- BEGIN control_controls", "-- END control_controls"], ["-- BEGIN monitor_controls", "-- END monitor_controls"], ["# BEGIN monitor_controls", "# END monitor_controls"]];
    }

    function _findManagedRange(text) {
        const pairs = _markerPairs();
        for (let i = 0; i < pairs.length; i++) {
            const start = text.indexOf(pairs[i][0]);
            if (start < 0)
                continue;
            const endToken = pairs[i][1];
            const end = text.indexOf(endToken, start);
            if (end < 0)
                return null;
            let endPos = end + endToken.length;
            if (text[endPos] === "\n")
                endPos++;
            return ({
                    start: start,
                    end: endPos
                });
        }
        return null;
    }

    function _parseManagedBlock(text) {
        const empty = {
            defaultRule: null,
            monitors: [],
            primary: ""
        };
        if (!text)
            return empty;
        const range = _findManagedRange(text);
        if (!range)
            return empty;
        const block = text.substring(range.start, range.end);
        const re = /hl\.monitor\(\s*\{([\s\S]*?)\}\s*\)/g;
        let match;
        let rule = null;
        const monitors = [];
        while ((match = re.exec(block)) !== null) {
            const fields = _parseLuaFields(match[1]);
            const output = fields.output || "";
            if (output === "") {
                rule = {
                    mode: fields.mode || "preferred",
                    position: fields.position || "auto",
                    scale: String(fields.scale || "1")
                };
                continue;
            }
            if (fields.disabled === true) {
                monitors.push({
                    name: output,
                    width: 0,
                    height: 0,
                    refreshRate: 0,
                    x: 0,
                    y: 0,
                    scale: 1,
                    transform: 0,
                    mirrorOf: "",
                    disabled: true
                });
                continue;
            }
            const mode = parseMode(fields.mode || "");
            const pos = String(fields.position || "0x0").match(/^(-?\d+)x(-?\d+)$/);
            if (!mode || !pos)
                continue;
            monitors.push({
                name: output,
                width: mode.width,
                height: mode.height,
                refreshRate: mode.refreshRate,
                x: parseInt(pos[1]),
                y: parseInt(pos[2]),
                scale: parseFloat(fields.scale || 1),
                transform: parseInt(fields.transform || 0),
                mirrorOf: fields.mirror || "",
                disabled: false
            });
        }
        const primaryMatch = /hl\.exec_cmd\(\s*"[^"]*xrandr\s+--output\s+'?([^'"\s]+)'?\s+--primary/.exec(block);
        return {
            defaultRule: rule,
            monitors: monitors,
            primary: primaryMatch ? primaryMatch[1] : ""
        };
    }

    function _parseLuaFields(body) {
        const fields = {};
        const re = /(\w+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?)|(true|false))/g;
        let match;
        while ((match = re.exec(body)) !== null) {
            const key = match[1];
            if (match[2] !== undefined)
                fields[key] = match[2];
            else if (match[4] !== undefined)
                fields[key] = match[4] === "true";
            else if (match[3] !== undefined) {
                fields[key] = match[3];
            }
        }
        return fields;
    }

    function _writeConfig() {
        let original = _configText || "";
        const rangeCheck = original !== "" ? _findManagedRange(original) : null;
        if (original.indexOf("-- BEGIN control_controls") >= 0 && original.indexOf("-- END control_controls") < 0 && !rangeCheck) {
            errorMessage = "Monitors config has an unmatched begin marker.";
            busy = false;
            return;
        }
        let block = "-- BEGIN control_controls\n";
        block += defaultRuleConfig(defaultRule) + "\n";
        for (let i = 0; i < draft.length; i++)
            block += toConfigLine(draft[i]) + "\n";
        if (applicablePrimary !== "")
            block += primaryConfigLine(applicablePrimary) + "\n";
        block += "-- END control_controls\n";

        const range = _findManagedRange(original);
        let next;
        if (range)
            next = original.substring(0, range.start) + block + original.substring(range.end);
        else {
            if (original !== "" && !original.endsWith("\n"))
                original += "\n";
            next = original + block;
        }
        configFile.setText(next);
    }

    Component.onCompleted: refresh()
}
