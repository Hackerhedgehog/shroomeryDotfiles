//
// Geometry of the status bar background when it grows into a popout panel:
// where the panel goes under the pill, and the SVG outline of pill + panel as
// one shape (StatusbarApp/BarShape.qml draws it with PathSvg). Free of QML
// imports and `.pragma library` so Node can load it for the unit tests.
//
// The outline is traced clockwise (y down): convex corners are arcs with
// sweep 1, the concave joins where the panel meets the pill's bottom edge
// have sweep 0. `inset` gives the same outline moved inward by that many
// pixels (the fill inside the border): convex radii shrink, concave grow.

function n(v) {
    return Math.round(v * 100) / 100;
}

function arc(p, r, sweep, x, y) {
    var rr = n(Math.max(0, r));
    p.push("A", rr, rr, 0, 0, sweep, n(x), n(y));
}

function roundedRect(x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    var p = ["M", n(x + r), n(y), "H", n(x + w - r)];
    arc(p, r, 1, x + w, y + r);
    p.push("V", n(y + h - r));
    arc(p, r, 1, x + w - r, y + h);
    p.push("H", n(x + r));
    arc(p, r, 1, x, y + h - r);
    p.push("V", n(y + r));
    arc(p, r, 1, x + r, y);
    p.push("Z");
    return p.join(" ");
}

// Left edge of a panel of width panelW centered under centerX, kept inside
// the pill, and snapped flush to a pill edge it lands within `snap` of. A
// panel wider than the pill is centered on it.
function panelX(centerX, panelW, pillX, pillW, snap) {
    if (panelW >= pillW)
        return pillX + (pillW - panelW) / 2;
    var right = pillX + pillW;
    var x = Math.round(centerX - panelW / 2);
    x = Math.max(pillX, Math.min(right - panelW, x));
    if (x - pillX < snap)
        return pillX;
    if (right - (x + panelW) < snap)
        return right - panelW;
    return x;
}

// g: { pillX, pillY, pillW, pillH, pillR, panelX, panelW, panelH, joinR, bottomR }
// The panel's top is the pill's bottom edge. A side whose gap to the pill
// edge is under half a pixel runs straight down (flush). Near-flush sides
// shrink their join and pill corner with the gap, so sliding to flush is
// continuous.
function barPath(g, inset) {
    var d = inset || 0;
    var x0 = g.pillX, x1 = g.pillX + g.pillW, y0 = g.pillY, y1 = g.pillY + g.pillH;
    var R = g.pillR, h = g.panelH;
    if (h < 0.5 + 2 * d)
        return roundedRect(x0 + d, y0 + d, g.pillW - 2 * d, g.pillH - 2 * d, Math.max(0, R - d));

    var a0 = g.panelX, a1 = g.panelX + g.panelW, yb = y1 + h;
    var rb = Math.min(g.bottomR, h / 2, g.panelW / 4);
    var gapL = a0 - x0, gapR = x1 - a1;
    var flushL = gapL < 0.5, flushR = gapR < 0.5;
    var L = flushL ? Math.min(x0, a0) : x0;
    var Rt = flushR ? Math.max(x1, a1) : x1;
    // Outer bottom corner of a flush side: the pill's radius while the
    // panel is short, growing to bottomR.
    var rf = Math.min(g.bottomR, R + h);

    var p = ["M", n(L + R), n(y0 + d), "H", n(Rt - R)];
    arc(p, R - d, 1, Rt - d, y0 + R);

    if (flushR) {
        p.push("V", n(yb - rf));
        arc(p, rf - d, 1, Rt - rf, yb - d);
    } else {
        var jR = Math.min(g.joinR, h / 2, gapR / 2);
        var cR = Math.min(R, gapR - jR);
        p.push("V", n(y1 - cR));
        arc(p, cR - d, 1, Rt - cR, y1 - d);
        p.push("H", n(a1 + jR));
        arc(p, jR + d, 0, a1 - d, y1 + jR);
        p.push("V", n(yb - rb));
        arc(p, rb - d, 1, a1 - rb, yb - d);
    }

    if (flushL) {
        p.push("H", n(L + rf));
        arc(p, rf - d, 1, L + d, yb - rf);
    } else {
        var jL = Math.min(g.joinR, h / 2, gapL / 2);
        var cL = Math.min(R, gapL - jL);
        p.push("H", n(a0 + rb));
        arc(p, rb - d, 1, a0 + d, yb - rb);
        p.push("V", n(y1 + jL));
        arc(p, jL + d, 0, a0 - jL, y1 - d);
        p.push("H", n(L + cL));
        arc(p, cL - d, 1, L + d, y1 - cL);
    }

    p.push("V", n(y0 + R));
    arc(p, R - d, 1, L + R, y0 + d);
    p.push("Z");
    return p.join(" ");
}

if (typeof module !== "undefined") {
    module.exports = { panelX: panelX, barPath: barPath, roundedRect: roundedRect };
}
