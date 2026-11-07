// InputApp settings (shroomery/settings/input.json): defaults, validation
// and the helpers InputWindow.qml uses; tests in tests/input.test.js. The
// bash side (shroomery lib.sh input_setting) applies the same rules.

var DEFAULTS = { layout: "us", variant: "", speed: 1.0, scaleWithMonitor: false };
// The speed in the file: the multiplier on a 1080p screen at scale 1.
var SPEED = { min: 0.05, max: 4 };

var CODE = /^[A-Za-z0-9_-]+$/;

function round3(v) {
    return Math.round(v * 1000) / 1000;
}

function clampSpeed(v, fallback) {
    var n = typeof v === "number" ? v : (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v.trim()) ? Number(v) : NaN);
    if (!isFinite(n))
        return fallback;
    return round3(Math.max(SPEED.min, Math.min(SPEED.max, n)));
}

function normalize(obj) {
    var o = obj !== null && typeof obj === "object" ? obj : {};
    return {
        layout: typeof o.layout === "string" && CODE.test(o.layout) ? o.layout : DEFAULTS.layout,
        variant: typeof o.variant === "string" && CODE.test(o.variant) ? o.variant : DEFAULTS.variant,
        speed: clampSpeed(o.speed, DEFAULTS.speed),
        scaleWithMonitor: o.scaleWithMonitor === true
    };
}

// The stored speed after flipping "scale with monitor" to SCALE_ON, chosen so
// the cursor keeps its speed on the monitor it is on now (FACTOR = that
// monitor's logical height / 1080): on → speed / factor, off → speed × factor.
function rebase(speed, factor, scaleOn) {
    var f = typeof factor === "number" && factor > 0 ? factor : 1;
    return clampSpeed(scaleOn ? speed / f : speed * f, speed);
}

// "CODE<TAB>DESCRIPTION" lines (input.sh layouts / variants) → [{ code, name }].
function parseCodes(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var tab = lines[i].indexOf("\t");
        if (tab <= 0)
            continue;
        out.push({ code: lines[i].slice(0, tab), name: lines[i].slice(tab + 1).trim() });
    }
    return out;
}

// input.sh layouts → PickerList items, sorted by name.
function layoutItems(text) {
    return parseCodes(text)
        .map(function (l) { return { key: l.code, label: l.name || l.code, detail: l.code }; })
        .sort(function (a, b) { return a.label.localeCompare(b.label); });
}

function layoutName(items, code) {
    for (var i = 0; i < (items || []).length; i++)
        if (items[i].key === code)
            return items[i].label;
    return code;
}

function formatSpeed(v) {
    return (Math.round(v * 100) / 100).toFixed(2) + "×";
}

// "DP-3 · 3840×2160 at scale 1.5" for input.sh info's monitor.
function describeMonitor(info) {
    if (!info || !info.monitor)
        return "";
    return info.monitor + " · " + info.width + "×" + info.height + " at scale " + info.scale;
}

if (typeof module !== "undefined") {
    module.exports = {
        DEFAULTS: DEFAULTS, SPEED: SPEED, normalize: normalize, clampSpeed: clampSpeed,
        rebase: rebase, parseCodes: parseCodes, layoutItems: layoutItems,
        layoutName: layoutName, formatSpeed: formatSpeed, describeMonitor: describeMonitor
    };
}
