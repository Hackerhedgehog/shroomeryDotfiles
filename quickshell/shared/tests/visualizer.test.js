const test = require("node:test");
const assert = require("node:assert");
const V = require("../Visualizer.js");

test("pushLevel keeps the newest `size` levels, clamped to 0..1", () => {
  let h = [];
  for (const v of [0.2, 1.5, -1, 0.4])
    h = V.pushLevel(h, v, 3);
  assert.deepStrictEqual(h, [1, 0, 0.4]);
});

test("pushLevel treats a missing level as silence", () => {
  assert.deepStrictEqual(V.pushLevel([], NaN, 4), [0]);
  assert.deepStrictEqual(V.pushLevel([], undefined, 4), [0]);
});

test("silence draws every tick at the minimum length", () => {
  assert.deepStrictEqual(V.tickLengths([], 8, 2, 10), [2, 2, 2, 2, 2, 2, 2, 2]);
});

test("the newest level is at the top tick and older ones ripple out both ways", () => {
  // history oldest..newest
  const t = V.tickLengths([0, 0.25, 1], 8, 0, 10);
  assert.strictEqual(t[0], 10);                    // newest, full level
  assert.strictEqual(t[1], 5);                     // sqrt(0.25) = 0.5
  assert.strictEqual(t[7], 5);                     // mirrored
  assert.strictEqual(t[2], 0);
  assert.strictEqual(t[4], 0);                     // beyond the history: silence
});

test("the ring is symmetric around the top", () => {
  const t = V.tickLengths([0.1, 0.3, 0.6, 0.9], 12, 1, 9);
  for (let i = 1; i < 12; i++)
    assert.strictEqual(t[i], t[12 - i]);
});

test("historySize covers half the ring plus the top tick", () => {
  assert.strictEqual(V.historySize(48), 25);
});

test("ringPath draws one radial tick per length, clockwise from the top", () => {
  // two ticks: top (-90°) and bottom (90°), inner radius 5 around (10, 10)
  assert.strictEqual(V.ringPath([2, 3], 10, 10, 5), "M 10 5 L 10 3 M 10 15 L 10 18");
});

test("ringPath of no ticks is empty", () => {
  assert.strictEqual(V.ringPath([], 10, 10, 5), "");
});

test("parseCavaFrame reads one ascii frame as 0..1 values", () => {
  assert.deepStrictEqual(V.parseCavaFrame("0;50;100;", 100), [0, 0.5, 1]);
});

test("parseCavaFrame clamps and skips garbage", () => {
  assert.deepStrictEqual(V.parseCavaFrame("120;x;-3;", 100), [1, 0, 0]);
  assert.deepStrictEqual(V.parseCavaFrame("", 100), []);
});

test("mirrorBars runs the spectrum down both sides of the ring from the top", () => {
  // bass at the top, treble meeting at the bottom
  const t = V.mirrorBars([1, 0.25, 0], 0, 10);
  assert.deepStrictEqual(t, [10, 2.5, 0, 0, 2.5, 10]);
});

test("mirrorBars of no bars is empty", () => {
  assert.deepStrictEqual(V.mirrorBars([], 1, 10), []);
});
