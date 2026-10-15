//
// Rings of ticks around round dashboard items: the volume bubbles' level
// ring (recent peak levels run around it from the top, so it ripples) and
// the cava spectrum around the cover art. Free of QML imports and
// `.pragma library` so Node can load it for the unit tests.

// Ticks from the top tick (0) to the bottom one: half the ring plus one.
function historySize(count) {
    return Math.floor(count / 2) + 1;
}

// Append a 0–1 peak level (anything else counts as silence), keeping the
// newest `size` values, oldest first.
function pushLevel(history, level, size) {
    var v = Number(level);
    v = isNaN(v) ? 0 : Math.max(0, Math.min(1, v));
    return history.concat([v]).slice(-size);
}

// Length of each of `count` ticks, clockwise from the top: the top tick
// shows the newest level, ticks further round both sides show older ones.
// sqrt makes quiet audio still visible.
function tickLengths(history, count, minLen, maxLen) {
    var out = [];
    for (var i = 0; i < count; i++) {
        var age = Math.min(i, count - i);
        var idx = history.length - 1 - age;
        var level = idx >= 0 ? history[idx] : 0;
        out.push(minLen + (maxLen - minLen) * Math.sqrt(level));
    }
    return out;
}

function n(v) {
    return Math.round(v * 100) / 100;
}

// SVG path (for PathSvg) of radial ticks around (cx, cy): tick i starts at
// radius r0 and points outward by lengths[i], clockwise from the top.
function ringPath(lengths, cx, cy, r0) {
    var parts = [];
    var count = lengths.length;
    for (var i = 0; i < count; i++) {
        var a = 2 * Math.PI * i / count - Math.PI / 2;
        var c = Math.cos(a), s = Math.sin(a);
        var r1 = r0 + lengths[i];
        parts.push("M", n(cx + r0 * c), n(cy + r0 * s), "L", n(cx + r1 * c), n(cy + r1 * s));
    }
    return parts.join(" ");
}

// One frame of cava's raw ascii output ("12;0;57;…;") -> values 0..1.
function parseCavaFrame(line, maxRange) {
    var out = [];
    var parts = String(line).split(";");
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].trim() === "")
            continue;
        var v = Number(parts[i]) / maxRange;
        out.push(isNaN(v) ? 0 : Math.max(0, Math.min(1, v)));
    }
    return out;
}

// Tick lengths for a spectrum ring: the bars run clockwise from the top
// (bass) down the right side to the bottom (treble), and mirrored back up
// the left side, so the ring is symmetric.
function mirrorBars(bars, minLen, maxLen) {
    var half = bars.map(function (v) { return minLen + (maxLen - minLen) * v; });
    return half.concat(half.slice().reverse());
}

if (typeof module !== "undefined") {
    module.exports = { historySize: historySize, pushLevel: pushLevel, tickLengths: tickLengths,
                       ringPath: ringPath, parseCavaFrame: parseCavaFrame, mirrorBars: mirrorBars };
}
