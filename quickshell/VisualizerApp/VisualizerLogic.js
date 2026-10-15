//
// Pure geometry and color helpers for the visualizer (VisualizerRenderer.qml, VisualizerPanel.qml).
// Free of QML imports and `.pragma library` so Node can load it for the tests.
//
// Spectrum layout: 2·n slots clockwise from the bottom center, so bass sits
// at the bottom, treble at the top, the same on both sides. u in 0..1 is a
// slot's position along that loop. Screen coordinates: y points down.

var STYLES = ["center-out", "center-in", "border"];
var DRAWS = ["bars", "wave", "line"];
var MIN_LIGHTNESS = 0.70;      // OKLCH floor so bars stay visible over the video
var CHROMA_BOOST = 1.15;
var MAX_CHROMA = 0.37;

function cycle(list, current, step) {
    var i = list.indexOf(current);
    if (i < 0)
        return list[0];
    var n = list.length;
    return list[((i + step) % n + n) % n];
}

function validStyle(s) { return STYLES.indexOf(s) >= 0 ? s : STYLES[0]; }
function validDraw(d) { return DRAWS.indexOf(d) >= 0 ? d : DRAWS[0]; }

function mirror(bars) {
    return bars.concat(bars.slice().reverse());
}

// --- screen-colors client ---

// Whether the client restarts the daemon on its `attempt`th connection retry
// (one retry per 500 ms): attempts 1, 2, 4, … 32, then every 60 — a daemon
// that keeps crashing is respawned at most every 30 s, not twice a second.
var RESTART_EVERY = 60;
function restartDue(attempt) {
    if (attempt >= RESTART_EVERY)
        return attempt % RESTART_EVERY === 0;
    return (attempt & (attempt - 1)) === 0;
}

// --- zone colors -> conical gradient ---

function zoneCount(edges) {
    return (edges.top || 0) + (edges.right || 0) + (edges.bottom || 0) + (edges.left || 0);
}

// Center of zone i on a w×h picture (protocol v1 order: clockwise from the
// top-left corner).
function zonePoint(edges, i, w, h) {
    var t = edges.top, r = edges.right, b = edges.bottom;
    if (i < t)
        return { x: (i + 0.5) / t * w, y: 0 };
    i -= t;
    if (i < r)
        return { x: w, y: (i + 0.5) / r * h };
    i -= r;
    if (i < b)
        return { x: w - (i + 0.5) / b * w, y: h };
    i -= b;
    return { x: 0, y: h - (i + 0.5) / edges.left * h };
}

// Position 0..1 of a point in a ConicalGradient with angle 0 centered on
// (cx, cy): Qt runs conical gradients counter-clockwise on screen from 3 o'clock.
function conicalPosition(x, y, cx, cy) {
    var deg = Math.atan2(-(y - cy), x - cx) * 180 / Math.PI;
    return ((deg / 360) % 1 + 1) % 1;
}

// Settings (visualizer.json): defaults and the valid range of each number.
// Anything missing, non-numeric or out of range falls back to the default.
var DEFAULTS = {
    style: "center-out", draw: "bars", monitor: "", sensitivity: 1.0,
    barWidth: 3, barSpacing: 2, lineWidth: 3, minLength: 4,
    outX: 0.5, outY: 0.5, outDiameter: 0.24,
    inX: 0.5, inY: 0.5, inDiameter: 0.9,
    smoothness: 0.5, outline: 1.5,
    wallpaperOnly: false
};
var RANGES = {
    sensitivity: [0.5, 2.0], barWidth: [1, 12], barSpacing: [0, 12], lineWidth: [1, 8],
    minLength: [0, 40], outX: [0, 1], outY: [0, 1], outDiameter: [0.05, 1.0],
    inX: [0, 1], inY: [0, 1], inDiameter: [0.05, 1.0],
    smoothness: [0, 1], outline: [0, 6]
};

function normalizeSettings(raw) {
    raw = raw || {};
    var out = {};
    for (var key in DEFAULTS) {
        var def = DEFAULTS[key], v = raw[key];
        if (key === "style")
            out[key] = validStyle(v);
        else if (key === "draw")
            out[key] = validDraw(v);
        else if (key === "monitor")
            out[key] = typeof v === "string" ? v : def;
        else if (key === "wallpaperOnly")
            out[key] = v === true;
        else {
            var num = (v === null || v === undefined || v === "") ? NaN : Number(v);
            out[key] = !isNaN(num) && num >= RANGES[key][0] && num <= RANGES[key][1] ? num : def;
        }
    }
    return out;
}

// Super+Alt+V: what a toggle does in the current state.
function nextAction(running, setupOpen) {
    return running ? "stop" : (setupOpen ? "close" : "open");
}

// The saved monitor when it is connected, else the focused one, else the first.
function pickMonitor(saved, connected, focused) {
    if (saved && connected.indexOf(saved) >= 0)
        return saved;
    if (connected.indexOf(focused) >= 0)
        return focused;
    return connected.length > 0 ? connected[0] : "";
}

// Circle center, radius and max bar length in px for a w×h screen. Border:
// the screen center (where its colors are measured from), radius 0.
function circleGeometry(style, cfg, w, h) {
    var s = Math.min(w, h);
    if (style === "border")
        return { cx: w / 2, cy: h / 2, radius: 0, maxLen: 0.12 * s };
    var inward = style === "center-in";
    var x = inward ? cfg.inX : cfg.outX, y = inward ? cfg.inY : cfg.outY;
    var dia = inward ? cfg.inDiameter : cfg.outDiameter;
    return { cx: x * w, cy: y * h, radius: dia * s / 2, maxLen: (inward ? 0.25 : 0.30) * s };
}

function hitCircle(x, y, geo, handle) {
    var d = Math.hypot(x - geo.cx, y - geo.cy);
    // The edge band never covers more than the outer 40%, so a circle smaller
    // than the handle keeps a center to grab.
    if (Math.abs(d - geo.radius) <= Math.min(handle, 0.4 * geo.radius))
        return "edge";
    return d < geo.radius ? "inside" : "outside";
}

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

// Settings to change while dragging in the mini screen (screen px): "inside"
// moves the center (grab = {dx, dy}, center minus the press point), "edge"
// resizes (grab = {cx, cy}, the center). Always within the valid ranges.
function dragUpdate(mode, prefix, x, y, grab, w, h) {
    var out = {};
    if (mode === "inside") {
        out[prefix + "X"] = Math.round(clamp((x + grab.dx) / w, 0, 1) * 1000) / 1000;
        out[prefix + "Y"] = Math.round(clamp((y + grab.dy) / h, 0, 1) * 1000) / 1000;
    } else if (mode === "edge") {
        var dia = 2 * Math.hypot(x - grab.cx, y - grab.cy) / Math.min(w, h);
        out[prefix + "Diameter"] = Math.round(clamp(dia, 0.05, 1.0) * 1000) / 1000;
    }
    return out;
}

function gradientStops(edges, colors, w, h, cx, cy) {
    if (cx === undefined) cx = w / 2;
    if (cy === undefined) cy = h / 2;
    var stops = [];
    for (var i = 0; i < colors.length; i++) {
        var p = zonePoint(edges, i, w, h);
        stops.push({ position: conicalPosition(p.x, p.y, cx, cy), color: colors[i] });
    }
    return wrapStops(stops);
}

// n colors around the ring: entry j is the color at t = j / (n - 1).
function ringFromStops(stops, n) {
    var out = [], k = 0;
    for (var j = 0; j < n; j++) {
        var t = j / (n - 1);
        while (k < stops.length - 2 && stops[k + 1].position < t)
            k++;
        var a = stops[k], b = stops[k + 1];
        var span = b.position - a.position;
        out.push(mixHex(a.color, b.color, span > 0 ? clamp((t - a.position) / span, 0, 1) : 0));
    }
    return out;
}

// The screen's zone colors as seen from (cx, cy): the color ring texture.
function colorRing(edges, colors, w, h, cx, cy, n) {
    return ringFromStops(gradientStops(edges, colors, w, h, cx, cy), n);
}

// Spectrum values (0–1) as gradient stops at their texel centers, grey: the
// Canvas fills them in one call and its interpolation does the blending.
function spectrumStops(values) {
    var n = values.length, out = [];
    // No stops would make Qt fall back to a black-to-white ramp: a fake spectrum.
    if (n === 0)
        return [{ position: 0, color: "rgb(0,0,0)" }, { position: 1, color: "rgb(0,0,0)" }];
    for (var i = 0; i < n; i++) {
        var g = Math.round(clamp(Number(values[i]) || 0, 0, 1) * 255);
        out.push({ position: (i + 0.5) / n, color: "rgb(" + g + "," + g + "," + g + ")" });
    }
    return out;
}

// Gaussian blur across neighbouring bands, so waves, lines and bars rise
// and fall together instead of in spikes. amount 0–1 -> sigma 0–4 bands;
// the ends are mirrored so bass and treble don't droop.
function smoothSpectrum(values, amount) {
    var n = values.length, sigma = 4 * (Number(amount) || 0);
    if (n === 0 || sigma < 0.05)
        return values.slice();
    var radius = Math.ceil(3 * sigma), weights = [], total = 0;
    for (var k = -radius; k <= radius; k++) {
        var w = Math.exp(-0.5 * (k / sigma) * (k / sigma));
        weights.push(w);
        total += w;
    }
    var out = new Array(n);
    for (var i = 0; i < n; i++) {
        var sum = 0;
        for (var j = -radius; j <= radius; j++) {
            var idx = i + j;
            while (idx < 0 || idx >= n)
                idx = idx < 0 ? -idx - 1 : 2 * n - idx - 1;
            sum += values[idx] * weights[j + radius];
        }
        out[i] = sum / total;
    }
    return out;
}

// Bar length with a soft limit (the shader uses the same curve): about
// linear when quiet, 95% of the way at full level, never flat at the top.
function softLength(v, sensitivity, minLen, maxLen) {
    return minLen + (maxLen - minLen) * (1 - Math.exp(-3 * v * sensitivity));
}

// A gentle moving spectrum for the preview while nothing plays.
function demoSpectrum(t, n) {
    var out = [];
    for (var i = 0; i < n; i++) {
        var fall = 1 - i / n;
        out.push(clamp((0.25 + 0.2 * Math.sin(t * 2 + i * 0.35) + 0.15 * Math.sin(t * 3.1 - i * 0.11)) * (0.4 + 0.6 * fall), 0, 1));
    }
    return out;
}

function isSilent(values) {
    for (var i = 0; i < values.length; i++)
        if (values[i] >= 0.01)
            return false;
    return true;
}

// Sorted stops plus wrap stops at 0 and 1 that blend the last and first
// colors, so the conical gradient has no seam.
function wrapStops(stops) {
    stops.sort(function (a, b) { return a.position - b.position; });
    var first = stops[0], last = stops[stops.length - 1];
    var gap = (1 - last.position) + first.position;
    var seam = mixHex(last.color, first.color, gap > 0 ? (1 - last.position) / gap : 0);
    return [{ position: 0, color: seam }].concat(stops, [{ position: 1, color: seam }]);
}

// Ring sector colors (clockwise from 12 o'clock, protocol v2) as conical
// gradient stops (counter-clockwise from 3 o'clock, as the shader samples).
function ringStopsFromSectors(colors) {
    var n = colors.length, stops = [];
    for (var i = 0; i < n; i++) {
        var turn = (i + 0.5) / n;
        stops.push({ position: (((0.25 - turn) % 1) + 1) % 1, color: colors[i] });
    }
    return wrapStops(stops);
}

function round4(v) {
    return Math.round(v * 10000) / 10000;
}

// The screen-colors subscription regions for the visualizer's geometry: where
// its bars can be, plus 10% of the bar length (protocol v2, fractions).
function visualizerRegions(cfg, w, h) {
    var s = Math.min(w, h), geo = circleGeometry(cfg.style, cfg, w, h);
    if (cfg.style === "border") {
        var side = Math.max(4, Math.round(32 * h / w));
        return [{ id: "viz", shape: "edges", top: 32, right: side, bottom: 32, left: side,
                  depth: round4(Math.min(0.5, 1.1 * geo.maxLen / s)) }];
    }
    var inward = cfg.style === "center-in";
    var inner = inward ? Math.max(0, geo.radius - 1.1 * geo.maxLen) : geo.radius;
    var outer = inward ? geo.radius + 0.1 * geo.maxLen : geo.radius + 1.1 * geo.maxLen;
    return [{ id: "viz", shape: "ring", cx: round4(geo.cx / w), cy: round4(geo.cy / h),
              inner: round4(inner / s), outer: round4(Math.min(2, outer / s)), sectors: 72 }];
}

function fallbackStops(a, b) {
    return [{ position: 0, color: a }, { position: 0.5, color: b }, { position: 1, color: a }];
}

// --- color math (same matrices as shroomery/screencolors/color.py) ---

function hexToRgb(hex) {
    var v = parseInt(String(hex).slice(1, 7), 16);
    return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
}

function rgbToHex(rgb) {
    return "#" + rgb.map(function (c) {
        var v = Math.round(Math.max(0, Math.min(1, c)) * 255);
        return (v < 16 ? "0" : "") + v.toString(16);
    }).join("");
}

function mixHex(a, b, t) {
    var x = hexToRgb(a), y = hexToRgb(b);
    return rgbToHex([0, 1, 2].map(function (i) { return x[i] + (y[i] - x[i]) * t; }));
}

function srgbToLinear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function linearToSrgb(c) {
    c = Math.max(0, Math.min(1, c));
    return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

function linearToOklab(rgb) {
    var l = Math.cbrt(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2]);
    var m = Math.cbrt(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2]);
    var s = Math.cbrt(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2]);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
}

function oklabToLinear(lab) {
    var l = Math.pow(lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2], 3);
    var m = Math.pow(lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2], 3);
    var s = Math.pow(lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2], 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
}

// A sampled color made readable over the picture it came from: lightness at
// least MIN_LIGHTNESS, chroma boosted, hue kept (OKLCH).
function readable(hex) {
    var lab = linearToOklab(hexToRgb(hex).map(srgbToLinear));
    var c = Math.min(Math.hypot(lab[1], lab[2]) * CHROMA_BOOST, MAX_CHROMA);
    var hue = Math.atan2(lab[2], lab[1]);
    var lin = oklabToLinear([Math.max(lab[0], MIN_LIGHTNESS), c * Math.cos(hue), c * Math.sin(hue)]);
    return rgbToHex(lin.map(linearToSrgb));
}

if (typeof module !== "undefined") {
    module.exports = {
        STYLES: STYLES, DRAWS: DRAWS,
        restartDue: restartDue,
        cycle: cycle, validStyle: validStyle, validDraw: validDraw, mirror: mirror,
        zoneCount: zoneCount, zonePoint: zonePoint, conicalPosition: conicalPosition,
        gradientStops: gradientStops, fallbackStops: fallbackStops,
        wrapStops: wrapStops, ringStopsFromSectors: ringStopsFromSectors, visualizerRegions: visualizerRegions,
        DEFAULTS: DEFAULTS, normalizeSettings: normalizeSettings, nextAction: nextAction,
        pickMonitor: pickMonitor, circleGeometry: circleGeometry, hitCircle: hitCircle,
        dragUpdate: dragUpdate, ringFromStops: ringFromStops, colorRing: colorRing,
        demoSpectrum: demoSpectrum, isSilent: isSilent,
        spectrumStops: spectrumStops, smoothSpectrum: smoothSpectrum, softLength: softLength,
        readable: readable, hexToRgb: hexToRgb, rgbToHex: rgbToHex, mixHex: mixHex
    };
}
