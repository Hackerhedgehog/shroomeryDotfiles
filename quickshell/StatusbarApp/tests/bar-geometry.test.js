const test = require("node:test");
const assert = require("node:assert");
const G = require("../BarGeometry.js");

const base = { pillX: 100, pillY: 10, pillW: 1000, pillH: 50, pillR: 12,
               panelX: 500, panelW: 400, panelH: 300, joinR: 12, bottomR: 16 };

function concaveArcs(path) {
  return (path.match(/A [\d.]+ [\d.]+ 0 0 0 /g) || []).length;
}

// The end point of every command, in order.
function points(path) {
  const t = path.split(" ");
  const pts = [];
  let x = 0, y = 0;
  for (let i = 0; i < t.length;) {
    const c = t[i++];
    if (c === "M") { x = +t[i++]; y = +t[i++]; }
    else if (c === "H") { x = +t[i++]; }
    else if (c === "V") { y = +t[i++]; }
    else if (c === "A") { i += 5; x = +t[i++]; y = +t[i++]; }
    else if (c === "Z") { continue; }
    else throw new Error("unexpected token " + c);
    pts.push([x, y]);
  }
  return pts;
}

test("panelX centers the panel under the icon", () => {
  assert.strictEqual(G.panelX(700, 400, 100, 1000, 24), 500);
});

test("panelX keeps the panel inside the pill", () => {
  assert.strictEqual(G.panelX(1080, 400, 100, 1000, 24), 700);
  assert.strictEqual(G.panelX(120, 400, 100, 1000, 24), 100);
});

test("panelX snaps flush when an edge lands within the snap distance", () => {
  assert.strictEqual(G.panelX(890, 400, 100, 1000, 24), 700);   // right gap 10
  assert.strictEqual(G.panelX(310, 400, 100, 1000, 24), 100);   // left gap 10
  assert.strictEqual(G.panelX(850, 400, 100, 1000, 24), 650);   // right gap 50: stays
});

test("panelX centers a panel that is wider than the pill", () => {
  assert.strictEqual(G.panelX(300, 1200, 100, 1000, 24), 0);
});

test("a closed panel draws the plain rounded pill", () => {
  assert.strictEqual(G.barPath(Object.assign({}, base, { panelH: 0 }), 0),
                     G.roundedRect(100, 10, 1000, 50, 12));
});

test("an open panel in the middle has two concave joins", () => {
  assert.strictEqual(concaveArcs(G.barPath(base, 0)), 2);
});

test("a panel flush with the pill's right edge has one concave join", () => {
  assert.strictEqual(concaveArcs(G.barPath(Object.assign({}, base, { panelX: 700 }), 0)), 1);
});

test("a panel as wide as the pill has no concave join", () => {
  assert.strictEqual(concaveArcs(G.barPath(Object.assign({}, base, { panelX: 100, panelW: 1000 }), 0)), 0);
});

test("the outline starts at the top and closes", () => {
  const p = G.barPath(base, 0);
  assert.match(p, /^M /);
  assert.match(p, / Z$/);
});

test("all numbers are finite, also mid-animation and near the edges", () => {
  for (const h of [0.6, 1, 5, 30, 300])
    for (const x of [100.3, 101, 103, 300, 690, 699.6, 700])
      for (const inset of [0, 2]) {
        const p = G.barPath(Object.assign({}, base, { panelH: h, panelX: x }), inset);
        for (const [px, py] of points(p)) {
          assert.ok(Number.isFinite(px) && Number.isFinite(py), `h=${h} x=${x} inset=${inset}: ${p}`);
        }
      }
});

test("the outline stays inside pill ∪ panel bounds", () => {
  const p = G.barPath(base, 0);
  for (const [x, y] of points(p)) {
    assert.ok(x >= 100 - 1e-6 && x <= 1100 + 1e-6, "x " + x);
    assert.ok(y >= 10 - 1e-6 && y <= 10 + 50 + 300 + 1e-6, "y " + y);
  }
});

test("the inset path stays inside the outline by the inset", () => {
  const p = G.barPath(base, 2);
  for (const [x, y] of points(p)) {
    assert.ok(x >= 102 - 1e-6 && x <= 1098 + 1e-6, "x " + x);
    assert.ok(y >= 12 - 1e-6 && y <= 358 + 1e-6, "y " + y);
  }
});

test("a right gap shrinking to zero converges on the flush outline", () => {
  const near = points(G.barPath(Object.assign({}, base, { panelX: 699.4 }), 0));
  const flush = points(G.barPath(Object.assign({}, base, { panelX: 700 }), 0));
  const maxX = pts => Math.max(...pts.map(q => q[0]));
  assert.ok(Math.abs(maxX(near) - maxX(flush)) < 1);
});
