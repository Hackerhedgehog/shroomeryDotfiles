// Night-light settings (shroomery/settings/night-light.json): defaults and
// validation, shared by NightLightState.qml and tests/night-light.test.js.
// The bash side (shroomery lib.sh night_light_setting) applies the same rules:
// not a number → default, out of range → clamped, bad time → default.

var DEFAULTS = { mode: "off", on: "21:00", off: "07:00", temperature: 4500, gamma: 100 };
var MODES = ["off", "fixed", "sun"];
var TEMPERATURE = { min: 2500, max: 6500 };
var GAMMA = { min: 50, max: 100 };

// Minutes since midnight of "H:MM" / "HH:MM" (24 h), or -1.
function parseTime(text) {
    if (typeof text !== "string")
        return -1;
    var m = /^(\d{1,2}):(\d{2})$/.exec(text.trim());
    if (!m)
        return -1;
    var h = parseInt(m[1], 10);
    var min = parseInt(m[2], 10);
    if (h > 23 || min > 59)
        return -1;
    return h * 60 + min;
}

function formatTime(minutes) {
    var h = Math.floor(minutes / 60);
    var m = minutes % 60;
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

// A number or numeric string, rounded and clamped; anything else → fallback.
function clampInt(value, min, max, fallback) {
    if (typeof value !== "number" && typeof value !== "string")
        return fallback;
    var s = String(value).trim();
    if (!/^-?\d+(\.\d+)?$/.test(s))
        return fallback;
    return Math.max(min, Math.min(max, Math.round(Number(s))));
}

function normalizeTime(text, fallback) {
    var m = parseTime(text);
    return m < 0 ? fallback : formatTime(m);
}

function normalize(obj) {
    var o = obj !== null && typeof obj === "object" ? obj : {};
    return {
        mode: MODES.indexOf(o.mode) >= 0 ? o.mode : DEFAULTS.mode,
        on: normalizeTime(o.on, DEFAULTS.on),
        off: normalizeTime(o.off, DEFAULTS.off),
        temperature: clampInt(o.temperature, TEMPERATURE.min, TEMPERATURE.max, DEFAULTS.temperature),
        gamma: clampInt(o.gamma, GAMMA.min, GAMMA.max, DEFAULTS.gamma)
    };
}

// "SUNRISE SUNSET" as printed by hyprsunset.sh sun-times → { sunrise, sunset }, or null.
function parseSunTimes(text) {
    var m = /^(\d{2}:\d{2}) (\d{2}:\d{2})$/.exec(String(text).trim());
    return m ? { sunrise: m[1], sunset: m[2] } : null;
}

if (typeof module !== "undefined") {
    module.exports = {
        DEFAULTS: DEFAULTS, MODES: MODES, TEMPERATURE: TEMPERATURE, GAMMA: GAMMA,
        parseTime: parseTime, formatTime: formatTime, clampInt: clampInt,
        normalize: normalize, parseSunTimes: parseSunTimes
    };
}
