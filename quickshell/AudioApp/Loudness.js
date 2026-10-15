//
// Pure logic for the dynamic loudness processor. Deliberately free of QML
// imports and of the `.pragma library` directive so the same file loads in
// QML (`import "Loudness.js" as Loudness`) and in Node for the unit tests.

var COMPRESSOR_URI = "http://lsp-plug.in/plugins/lv2/compressor_stereo";
var LIMITER_URI = "http://lsp-plug.in/plugins/lv2/limiter_stereo";

// Knee is fixed at the plugin default (0.50118 linear = -6 dB), so the soft
// knee spans 12 dB centred on the threshold.
var KNEE_LINEAR = 0.50118;
var KNEE_WIDTH_DB = 12.0;

// UI ranges, and the plugin control each maps to. `linear` marks the ports
// that take gain rather than dB/ms; `nativeMin`/`nativeMax` are the plugin's
// own strict bounds, which reject out-of-range writes outright.
var PARAMS = {
    threshold: { min: -60, max: 0, step: 0.5, unit: "dB", control: "comp:al", linear: true, nativeMin: 0.001, nativeMax: 1.0 },
    ratio: { min: 1, max: 20, step: 0.1, unit: ":1", control: "comp:cr", linear: false, nativeMin: 1.0, nativeMax: 100.0 },
    attack: { min: 0.1, max: 100, step: 0.1, unit: "ms", control: "comp:at", linear: false, nativeMin: 0.0, nativeMax: 2000.0 },
    release: { min: 10, max: 1000, step: 1, unit: "ms", control: "comp:rt", linear: false, nativeMin: 0.0, nativeMax: 5000.0 },
    makeup: { min: 0, max: 24, step: 0.5, unit: "dB", control: "comp:mk", linear: true, nativeMin: 0.001, nativeMax: 1000.0 },
    ceiling: { min: -12, max: 0, step: 0.1, unit: "dB", control: "lim:th", linear: true, nativeMin: 0.003981, nativeMax: 1.0 }
};

var PARAM_KEYS = ["threshold", "ratio", "attack", "release", "makeup", "ceiling"];

function dbToLinear(db) {
    return Math.pow(10, db / 20);
}

// Floored so that a -Infinity never escapes into a plugin control or the UI.
function linearToDb(lin) {
    return 20 * Math.log10(Math.max(lin, 1e-6));
}

function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value));
}

function clampDb(key, value) {
    var p = PARAMS[key];
    if (!p || !isFinite(value))
        return p ? p.min : 0;
    return clamp(value, p.min, p.max);
}

// UI value -> the number the plugin control actually takes, clamped twice:
// once to the UI range, then to the port's strict bounds.
function toNative(key, value) {
    var p = PARAMS[key];
    var v = clampDb(key, value);
    var native = p.linear ? dbToLinear(v) : v;
    return clamp(native, p.nativeMin, p.nativeMax);
}

// Reset is a true pass-through, not a mid-strength default: ratio 1:1 reduces
// nothing, 0 dB makeup adds nothing, a 0 dB ceiling never limits. That makes
// it an audible null test against the effect being switched off.
var PRESETS = {
    reset: { threshold: -20, ratio: 1.0, attack: 10, release: 200, makeup: 0, ceiling: 0 },
    movies: { threshold: -28, ratio: 4.0, attack: 8, release: 200, makeup: 8, ceiling: -1 },
    gaming: { threshold: -22, ratio: 2.5, attack: 15, release: 150, makeup: 4, ceiling: -1 },
    streams: { threshold: -25, ratio: 3.0, attack: 10, release: 200, makeup: 5, ceiling: -1 }
};

var PRESET_ORDER = ["movies", "gaming", "streams", "reset"];

var PRESET_LABELS = {
    movies: "Movies / TV",
    gaming: "Gaming",
    streams: "Streams",
    reset: "Reset",
    custom: "Custom"
};

// Typical dialogue level, used as the reference for the makeup suggestion.
var REFERENCE_DB = -20;

// Levels shown in the reduction table; the same five the test tones use.
var TABLE_LEVELS = [-45, -35, -25, -15, -3];

// Standard soft-knee downward compression. Returns the output level in dBFS
// for an input level in dBFS, ignoring makeup gain and ballistics — this is
// the static transfer curve, which is what the UI draws.
function gainComputer(inputDb, thresholdDb, ratio) {
    var half = KNEE_WIDTH_DB / 2;
    if (inputDb < thresholdDb - half)
        return inputDb;
    if (inputDb <= thresholdDb + half) {
        var over = inputDb - thresholdDb + half;
        return inputDb + ((1 / ratio - 1) * over * over) / (2 * KNEE_WIDTH_DB);
    }
    return thresholdDb + (inputDb - thresholdDb) / ratio;
}

function gainReduction(inputDb, thresholdDb, ratio) {
    return inputDb - gainComputer(inputDb, thresholdDb, ratio);
}

// How much makeup to add so that reference-level material comes back to where
// it started. Rounded to the makeup slider's own step.
function suggestedMakeup(thresholdDb, ratio) {
    var gr = gainReduction(REFERENCE_DB, thresholdDb, ratio);
    return Math.round(clamp(gr, PARAMS.makeup.min, PARAMS.makeup.max) * 2) / 2;
}

// Lowest input level at which compressed-plus-makeup output reaches the
// ceiling, or null when that never happens at or below 0 dBFS. Inverted
// analytically above the knee; the knee region is swept because the inverse
// of the quadratic is not worth the algebra for a display value.
function limiterOnsetDb(thresholdDb, ratio, makeupDb, ceilingDb) {
    for (var x = -60; x <= 0; x += 0.05) {
        if (gainComputer(x, thresholdDb, ratio) + makeupDb >= ceilingDb)
            return Math.round(x * 100) / 100;
    }
    return null;
}

function matchPreset(values) {
    for (var i = 0; i < PRESET_ORDER.length; i++) {
        var name = PRESET_ORDER[i];
        var preset = PRESETS[name];
        var same = true;
        for (var k = 0; k < PARAM_KEYS.length; k++) {
            var key = PARAM_KEYS[k];
            if (Math.abs(values[key] - preset[key]) > 1e-9) {
                same = false;
                break;
            }
        }
        if (same)
            return name;
    }
    return "custom";
}

var SINK_NAME = "dynamic_loudness";
var PLAYBACK_NAME = "output.dynamic_loudness";

function quote(s) {
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

// Trim float noise without losing the precision the plugin bounds need.
function num(v) {
    return String(Math.round(v * 1e6) / 1e6);
}

// The structure below was verified by running it; `cm`, `rrl`, `kn` and `lk`
// are pinned rather than left to plugin defaults so the graph is explicit,
// and `alr`/`boost` MUST stay 0 or the limiter applies its own levelling.
function renderConf(values, targetSink) {
    var n = function (key) {
        return num(toNative(key, values[key]));
    };
    return [
        "context.properties = { log.level = 0 }",
        "context.spa-libs = {",
        "    audio.convert.* = audioconvert/libspa-audioconvert",
        "    support.*       = support/libspa-support",
        "}",
        "context.modules = [",
        "    { name = libpipewire-module-rt flags = [ ifexists nofail ] }",
        "    { name = libpipewire-module-protocol-native }",
        "    { name = libpipewire-module-client-node }",
        "    { name = libpipewire-module-adapter }",
        "    { name = libpipewire-module-filter-chain",
        "        args = {",
        '            node.description = "Dynamic Loudness"',
        '            media.name       = "Dynamic Loudness"',
        "            filter.graph = {",
        "                nodes = [",
        "                    { type = lv2 name = comp",
        '                      plugin = "' + COMPRESSOR_URI + '"',
        '                      control = { "cm" = 0.0 "al" = ' + n("threshold") + ' "cr" = ' + n("ratio")
            + ' "at" = ' + n("attack") + ' "rrl" = 0.0 "rt" = ' + n("release")
            + ' "kn" = ' + num(KNEE_LINEAR) + ' "mk" = ' + n("makeup") + " } }",
        "                    { type = lv2 name = lim",
        '                      plugin = "' + LIMITER_URI + '"',
        '                      control = { "th" = ' + n("ceiling") + ' "alr" = 0.0 "boost" = 0.0 "lk" = 5.0 } }',
        "                ]",
        "                links = [",
        '                    { output = "comp:out_l" input = "lim:in_l" }',
        '                    { output = "comp:out_r" input = "lim:in_r" }',
        "                ]",
        '                inputs  = [ "comp:in_l" "comp:in_r" ]',
        '                outputs = [ "lim:out_l" "lim:out_r" ]',
        "            }",
        "            audio.channels = 2",
        "            audio.position = [ FL FR ]",
        "            capture.props = {",
        '                node.name   = "' + SINK_NAME + '"',
        "                media.class = Audio/Sink",
        "            }",
        "            playback.props = {",
        '                node.name     = "' + PLAYBACK_NAME + '"',
        "                node.passive  = true",
        '                target.object = "' + quote(targetSink) + '"',
        "            }",
        "        }",
        "    }",
        "]",
        ""
    ].join("\n");
}

// Every parameter goes in one pod. PipeWire accepts the whole set in a single
// set-param, so a slider drag costs one short-lived process rather than six.
function setParamsArgs(nodeId, values) {
    var parts = [];
    for (var i = 0; i < PARAM_KEYS.length; i++) {
        var key = PARAM_KEYS[i];
        parts.push('"' + PARAMS[key].control + '" ' + num(toNative(key, values[key])));
    }
    return ["pw-cli", "s", String(nodeId), "Props", "{ params = [ " + parts.join(" ") + " ] }"];
}

// The chain's playback end is an ordinary stream, so pactl can move it to a
// different device without touching the graph.
function parseSinkInputIndex(text, nodeName) {
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!parsed || !parsed.length)
        return null;
    for (var i = 0; i < parsed.length; i++) {
        var props = parsed[i].properties || {};
        if (props["node.name"] === nodeName)
            return parsed[i].index;
    }
    return null;
}

function parseNodeId(text, nodeName) {
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!parsed || !parsed.length)
        return null;
    for (var i = 0; i < parsed.length; i++) {
        var info = parsed[i].info || {};
        var props = info.props || {};
        if (props["node.name"] === nodeName)
            return parsed[i].id;
    }
    return null;
}

if (typeof module !== "undefined") {
    module.exports = {
        COMPRESSOR_URI: COMPRESSOR_URI,
        LIMITER_URI: LIMITER_URI,
        KNEE_LINEAR: KNEE_LINEAR,
        KNEE_WIDTH_DB: KNEE_WIDTH_DB,
        PARAMS: PARAMS,
        PARAM_KEYS: PARAM_KEYS,
        dbToLinear: dbToLinear,
        linearToDb: linearToDb,
        clamp: clamp,
        clampDb: clampDb,
        toNative: toNative,
        PRESETS: PRESETS,
        PRESET_ORDER: PRESET_ORDER,
        PRESET_LABELS: PRESET_LABELS,
        REFERENCE_DB: REFERENCE_DB,
        TABLE_LEVELS: TABLE_LEVELS,
        gainComputer: gainComputer,
        gainReduction: gainReduction,
        suggestedMakeup: suggestedMakeup,
        limiterOnsetDb: limiterOnsetDb,
        matchPreset: matchPreset,
        SINK_NAME: SINK_NAME,
        PLAYBACK_NAME: PLAYBACK_NAME,
        renderConf: renderConf,
        setParamsArgs: setParamsArgs,
        parseNodeId: parseNodeId,
        parseSinkInputIndex: parseSinkInputIndex
    };
}
