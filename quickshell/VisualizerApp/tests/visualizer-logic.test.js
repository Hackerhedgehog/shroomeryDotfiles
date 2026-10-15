const test = require("node:test");
const assert = require("node:assert");
const L = require("../VisualizerLogic.js");

const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) <= eps, `${a} != ${b}`);
const E169 = { top: 16, right: 9, bottom: 16, left: 9 };

test("cycle wraps both ways and recovers from unknown values", () => {
  assert.strictEqual(L.cycle(L.STYLES, "border", 1), "center-out");
  assert.strictEqual(L.cycle(L.STYLES, "center-out", -1), "border");
  assert.strictEqual(L.cycle(L.DRAWS, "bars", 1), "wave");
  assert.strictEqual(L.cycle(L.STYLES, "nonsense", 1), "center-out");
  assert.strictEqual(L.validStyle("x"), "center-out");
  assert.strictEqual(L.validDraw("wave"), "wave");
});

test("mirror puts bass at both ends and treble in the middle", () => {
  assert.deepStrictEqual(L.mirror([1, 2, 3]), [1, 2, 3, 3, 2, 1]);
  assert.deepStrictEqual(L.mirror([]), []);
});

test("zonePoint follows the protocol's clockwise order", () => {
  assert.strictEqual(L.zoneCount(E169), 50);
  assert.deepStrictEqual(L.zonePoint(E169, 0, 1600, 900), { x: 50, y: 0 });
  assert.deepStrictEqual(L.zonePoint(E169, 16, 1600, 900), { x: 1600, y: 50 });
  assert.deepStrictEqual(L.zonePoint(E169, 25, 1600, 900), { x: 1550, y: 900 });
  assert.deepStrictEqual(L.zonePoint(E169, 41, 1600, 900), { x: 0, y: 850 });
});

test("conicalPosition: 0 right, 0.25 up, 0.5 left, 0.75 down (counter-clockwise on screen)", () => {
  near(L.conicalPosition(10, 0, 0, 0), 0);
  near(L.conicalPosition(0, -10, 0, 0), 0.25);
  near(L.conicalPosition(-10, 0, 0, 0), 0.5);
  near(L.conicalPosition(0, 10, 0, 0), 0.75);
});

test("gradientStops are sorted and wrap from 0 to 1", () => {
  const colors = Array.from({ length: 50 }, (_, i) => (i < 16 ? "#ff0000" : "#0000ff"));
  const stops = L.gradientStops(E169, colors, 1600, 900);
  assert.strictEqual(stops.length, 52);
  assert.strictEqual(stops[0].position, 0);
  assert.strictEqual(stops[stops.length - 1].position, 1);
  assert.strictEqual(stops[0].color, stops[stops.length - 1].color);
  for (let i = 1; i < stops.length; i++)
    assert.ok(stops[i].position >= stops[i - 1].position);
  // the top zones sit around 0.25 (up) and carry their red
  const up = stops.reduce((a, b) => (Math.abs(b.position - 0.25) < Math.abs(a.position - 0.25) ? b : a));
  assert.strictEqual(up.color, "#ff0000");
});

test("gradientStops handles 21:9 edges", () => {
  const e = { top: 16, right: 7, bottom: 16, left: 7 };
  const stops = L.gradientStops(e, Array(46).fill("#00ff00"), 2560, 1080);
  assert.strictEqual(stops.length, 48);
});

test("readable lifts dark colors and keeps the hue", () => {
  const gray = L.hexToRgb(L.readable("#000000"));
  assert.ok(gray[0] > 0.55 && Math.abs(gray[0] - gray[2]) < 0.01);
  const red = L.hexToRgb(L.readable("#400000"));
  assert.ok(red[0] > red[1] && red[0] > red[2]);
  assert.strictEqual(L.readable("#ffffff"), "#ffffff");
});

test("hex helpers", () => {
  assert.strictEqual(L.rgbToHex(L.hexToRgb("#1a2b3c")), "#1a2b3c");
  assert.strictEqual(L.mixHex("#000000", "#ffffff", 0.5), "#808080");
  assert.deepStrictEqual(L.fallbackStops("#111111", "#222222").map(s => s.position), [0, 0.5, 1]);
});

test("daemon restarts back off: 0.5, 1, 2, 4, 8, 16, 30 s, then every 30 s", () => {
  const due = [];
  for (let a = 1; a <= 200; a++)
    if (L.restartDue(a)) due.push(a);
  assert.deepStrictEqual(due.slice(0, 7), [1, 2, 4, 8, 16, 32, 60]);
  assert.deepStrictEqual(due.slice(7), [120, 180]);
});

test("DRAWS has bars, wave and line, and cycling wraps", () => {
  assert.deepStrictEqual(L.DRAWS, ["bars", "wave", "line"]);
  assert.strictEqual(L.cycle(L.DRAWS, "line", 1), "bars");
  assert.strictEqual(L.cycle(L.DRAWS, "bars", -1), "line");
  assert.strictEqual(L.validDraw("line"), "line");
});

test("normalizeSettings fills defaults", () => {
  const c = L.normalizeSettings({});
  assert.deepStrictEqual(c, L.DEFAULTS);
  assert.strictEqual(c.barWidth, 3);
  assert.strictEqual(c.inDiameter, 0.9);
});

test("normalizeSettings falls back per key", () => {
  const c = L.normalizeSettings({
    style: "nope", draw: 7, monitor: 3, sensitivity: "abc", barWidth: 99,
    barSpacing: -1, lineWidth: "4", minLength: null, outX: 0.2, wallpaperOnly: "yes"
  });
  assert.strictEqual(c.style, "center-out");
  assert.strictEqual(c.draw, "bars");
  assert.strictEqual(c.monitor, "");
  assert.strictEqual(c.sensitivity, 1.0);
  assert.strictEqual(c.barWidth, 3);      // out of range -> default
  assert.strictEqual(c.barSpacing, 2);
  assert.strictEqual(c.lineWidth, 4);     // numeric strings are fine
  assert.strictEqual(c.minLength, 4);
  assert.strictEqual(c.outX, 0.2);
  assert.strictEqual(c.wallpaperOnly, false);
});

test("nextAction: stop beats close beats open", () => {
  assert.strictEqual(L.nextAction(true, true), "stop");
  assert.strictEqual(L.nextAction(true, false), "stop");
  assert.strictEqual(L.nextAction(false, true), "close");
  assert.strictEqual(L.nextAction(false, false), "open");
});

test("pickMonitor falls back", () => {
  assert.strictEqual(L.pickMonitor("HDMI-A-1", ["DP-2", "HDMI-A-1"], "DP-2"), "HDMI-A-1");
  assert.strictEqual(L.pickMonitor("HDMI-A-1", ["DP-2"], "DP-2"), "DP-2");
  assert.strictEqual(L.pickMonitor("", ["DP-2", "HDMI-A-1"], "HDMI-A-1"), "HDMI-A-1");
  assert.strictEqual(L.pickMonitor("", ["DP-2"], "gone"), "DP-2");
  assert.strictEqual(L.pickMonitor("", [], ""), "");
});

test("circleGeometry follows the screen shape", () => {
  const c = L.normalizeSettings({ outX: 0.25, outY: 0.5, outDiameter: 0.5 });
  const wide = L.circleGeometry("center-out", c, 2560, 1080);
  assert.deepStrictEqual([wide.cx, wide.cy, wide.radius, wide.maxLen], [640, 540, 270, 324]);
  const tall = L.circleGeometry("center-out", c, 2560, 1440);
  assert.deepStrictEqual([tall.cx, tall.cy, tall.radius], [640, 720, 360]);
  const inward = L.circleGeometry("center-in", L.DEFAULTS, 2000, 1000);
  assert.deepStrictEqual([inward.radius, inward.maxLen], [450, 250]);
  const border = L.circleGeometry("border", L.DEFAULTS, 2000, 1000);
  assert.deepStrictEqual([border.cx, border.cy, border.radius, border.maxLen], [1000, 500, 0, 120]);
});

test("hitCircle: edge handle, inside, outside", () => {
  const g = { cx: 100, cy: 100, radius: 50 };
  assert.strictEqual(L.hitCircle(100, 100, g, 8), "inside");
  assert.strictEqual(L.hitCircle(154, 100, g, 8), "edge");
  assert.strictEqual(L.hitCircle(100, 44, g, 8), "edge");
  assert.strictEqual(L.hitCircle(200, 200, g, 8), "outside");
});

test("dragUpdate clamps", () => {
  const move = L.dragUpdate("inside", "out", 3000, -50, { dx: 0, dy: 0 }, 2000, 1000);
  assert.deepStrictEqual(move, { outX: 1, outY: 0 });
  const kept = L.dragUpdate("inside", "in", 500, 250, { dx: 100, dy: 50 }, 2000, 1000);
  assert.deepStrictEqual(kept, { inX: 0.3, inY: 0.3 });
  const big = L.dragUpdate("edge", "in", 1900, 500, { cx: 1000, cy: 500 }, 2000, 1000);
  assert.deepStrictEqual(big, { inDiameter: 1 });
  const small = L.dragUpdate("edge", "out", 1001, 500, { cx: 1000, cy: 500 }, 2000, 1000);
  assert.deepStrictEqual(small, { outDiameter: 0.05 });
  const mid = L.dragUpdate("edge", "out", 1200, 500, { cx: 1000, cy: 500 }, 2000, 1000);
  assert.deepStrictEqual(mid, { outDiameter: 0.4 });
  assert.deepStrictEqual(L.dragUpdate("", "out", 1, 1, {}, 10, 10), {});
});

const PATTERN = Array.from({ length: 50 }, (_, i) =>
  i < 16 ? "#ff0000" : i < 25 ? "#00ff00" : i < 41 ? "#0000ff" : "#ffff00");

test("colorRing: centered pattern lands at the right angles", () => {
  const ring = L.colorRing(E169, PATTERN, 1600, 900, 800, 450, 360);
  assert.strictEqual(ring.length, 360);
  assert.strictEqual(ring[0], "#00ff00");     // t = 0: right
  assert.strictEqual(ring[90], "#ff0000");    // t = 0.25: up
  assert.strictEqual(ring[180], "#ffff00");   // t = 0.5: left
  assert.strictEqual(ring[269], "#0000ff");   // t = 0.75: down
  assert.strictEqual(ring[0], ring[359]);     // no seam
});

test("colorRing: a ring near the left edge sees mostly left colors", () => {
  const count = (ring, c) => ring.filter(x => x === c).length;
  const centered = L.colorRing(E169, PATTERN, 1600, 900, 800, 450, 360);
  const left = L.colorRing(E169, PATTERN, 1600, 900, 80, 450, 360);
  assert.ok(count(left, "#ffff00") > 2 * count(centered, "#ffff00"));
});

test("colorRing handles 21:9 edges", () => {
  const e = { top: 16, right: 7, bottom: 16, left: 7 };
  const ring = L.colorRing(e, Array(46).fill("#00ff00"), 2560, 1080, 1280, 540, 360);
  assert.strictEqual(ring.length, 360);
  assert.ok(ring.every(c => c === "#00ff00"));
});

test("ringFromStops from the theme fallback", () => {
  const ring = L.ringFromStops(L.fallbackStops("#000000", "#ffffff"), 5);
  assert.deepStrictEqual(ring, ["#000000", "#808080", "#ffffff", "#808080", "#000000"]);
});

test("demoSpectrum and isSilent", () => {
  const d = L.demoSpectrum(1.0, 96);
  assert.strictEqual(d.length, 96);
  assert.ok(d.every(v => v >= 0 && v <= 1));
  assert.ok(!L.isSilent(d));
  assert.ok(L.isSilent([0, 0.005, 0]));
  assert.ok(L.isSilent([]));
});

test("spectrumStops: grey stops at texel centers, clamped", () => {
  assert.deepStrictEqual(L.spectrumStops([0, 0.5, 2, -1]), [
    { position: 0.125, color: "rgb(0,0,0)" }, { position: 0.375, color: "rgb(128,128,128)" },
    { position: 0.625, color: "rgb(255,255,255)" }, { position: 0.875, color: "rgb(0,0,0)" }]);
});

test("spectrumStops of nothing is silence, not Qt's default black-to-white ramp", () => {
  assert.deepStrictEqual(L.spectrumStops([]), [
    { position: 0, color: "rgb(0,0,0)" }, { position: 1, color: "rgb(0,0,0)" }]);
});

test("hitCircle: a circle smaller than the handle can still be moved", () => {
  const g = { cx: 100, cy: 100, radius: 8 };
  assert.strictEqual(L.hitCircle(100, 100, g, 10), "inside");
  assert.strictEqual(L.hitCircle(108, 100, g, 10), "edge");
  assert.strictEqual(L.hitCircle(130, 100, g, 10), "outside");
});

test("smoothSpectrum: 0 leaves values alone", () => {
  assert.deepStrictEqual(L.smoothSpectrum([0.1, 0.9, 0.2], 0), [0.1, 0.9, 0.2]);
});

test("smoothSpectrum: a flat spectrum stays flat, ends included", () => {
  const out = L.smoothSpectrum(Array(20).fill(0.6), 1);
  out.forEach(v => near(v, 0.6, 1e-9));
});

test("smoothSpectrum: a spike spreads out but keeps its area", () => {
  const input = Array(41).fill(0);
  input[20] = 1;
  const out = L.smoothSpectrum(input, 0.5);
  assert.ok(out[20] < 1 && out[20] > out[22] && out[22] > 0);
  near(out.reduce((a, b) => a + b, 0), 1, 1e-6);
  near(out[18], out[22], 1e-12);   // symmetric
});

test("softLength: starts at minLen, stays under maxLen, keeps rising", () => {
  near(L.softLength(0, 1, 4, 100), 4);
  near(L.softLength(1, 1, 4, 100), 4 + 96 * (1 - Math.exp(-3)), 1e-9);   // about 95%
  let last = 4;
  for (let v = 0.1; v <= 10; v += 0.1) {
    const len = L.softLength(v, 1, 4, 100);
    assert.ok(len > last && len < 100);
    last = len;
  }
  assert.ok(L.softLength(1, 2, 0, 100) > L.softLength(1, 1, 0, 100));   // sensitivity
});

test("normalizeSettings: smoothness and outline", () => {
  assert.strictEqual(L.DEFAULTS.smoothness, 0.5);
  assert.strictEqual(L.DEFAULTS.outline, 1.5);
  const c = L.normalizeSettings({ smoothness: 0, outline: 0 });
  assert.strictEqual(c.smoothness, 0);
  assert.strictEqual(c.outline, 0);
  const bad = L.normalizeSettings({ smoothness: 2, outline: 9 });
  assert.strictEqual(bad.smoothness, 0.5);
  assert.strictEqual(bad.outline, 1.5);
});

test("visualizerRegions: center-out ring from the base past the tips", () => {
  const [r] = L.visualizerRegions(L.DEFAULTS, 2000, 1000);   // radius 120, maxLen 300
  assert.deepStrictEqual(r, { id: "viz", shape: "ring", cx: 0.5, cy: 0.5, inner: 0.12, outer: 0.45, sectors: 72 });
});

test("visualizerRegions: center-in ring from inside the tips past the base", () => {
  const [r] = L.visualizerRegions(L.normalizeSettings({ style: "center-in", inX: 0.25 }), 2000, 1000);
  assert.strictEqual(r.shape, "ring");
  assert.strictEqual(r.cx, 0.25);
  near(r.inner, 0.175);   // (450 - 275) / 1000
  near(r.outer, 0.475);   // (450 + 25) / 1000
});

test("visualizerRegions: border edges, depth past the bar tips", () => {
  const [r] = L.visualizerRegions(L.normalizeSettings({ style: "border" }), 1600, 900);
  assert.deepStrictEqual([r.shape, r.top, r.right, r.bottom, r.left], ["edges", 32, 18, 32, 18]);
  near(r.depth, 0.132);   // 1.1 * 108 / 900
});

test("ringStopsFromSectors: clockwise sectors from 12 o'clock to conical positions", () => {
  const stops = L.ringStopsFromSectors(["#ff0000", "#00ff00", "#0000ff", "#ffff00"]);
  // sector centers at 1:30, 4:30, 7:30, 10:30 -> t 0.125, 0.875, 0.625, 0.375
  assert.deepStrictEqual(stops.slice(1, 5).map(s => [s.position, s.color]),
    [[0.125, "#ff0000"], [0.375, "#ffff00"], [0.625, "#0000ff"], [0.875, "#00ff00"]]);
  assert.strictEqual(stops[0].position, 0);
  assert.strictEqual(stops[5].position, 1);
  assert.strictEqual(stops[0].color, stops[5].color);
});

test("ringStopsFromSectors: sector 0 sits just clockwise of 12 o'clock", () => {
  const stops = L.ringStopsFromSectors(Array.from({ length: 72 }, (_, i) => (i === 0 ? "#ffffff" : "#000000")));
  const white = stops.find(s => s.color === "#ffffff");
  assert.ok(white.position < 0.25 && white.position > 0.24);
});
