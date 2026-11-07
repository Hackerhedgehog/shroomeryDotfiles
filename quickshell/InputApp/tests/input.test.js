const test = require("node:test");
const assert = require("node:assert");
const L = require("../InputLogic.js");

test("normalize: missing/bad → defaults", () => {
    assert.deepStrictEqual(L.normalize({}), L.DEFAULTS);
    assert.deepStrictEqual(L.normalize(null), L.DEFAULTS);
    assert.deepStrictEqual(L.normalize("x"), L.DEFAULTS);
    assert.deepStrictEqual(L.normalize({ layout: 'ee"; x', variant: "a b", speed: "fast", scaleWithMonitor: "yes" }),
        L.DEFAULTS);
});

test("normalize keeps good values", () => {
    assert.deepStrictEqual(L.normalize({ layout: "ee", variant: "nodeadkeys", speed: 0.3, scaleWithMonitor: true }),
        { layout: "ee", variant: "nodeadkeys", speed: 0.3, scaleWithMonitor: true });
    assert.strictEqual(L.normalize({ speed: "0.25" }).speed, 0.25);
});

test("speed is clamped and rounded", () => {
    assert.strictEqual(L.normalize({ speed: 99 }).speed, L.SPEED.max);
    assert.strictEqual(L.normalize({ speed: 0 }).speed, L.SPEED.min);
    assert.strictEqual(L.normalize({ speed: 0.12345 }).speed, 0.123);
    assert.strictEqual(L.normalize({ speed: NaN }).speed, L.DEFAULTS.speed);
});

test("rebase keeps the speed on the current monitor", () => {
    // 4K at 1.5: factor 1.333. 0.4 in effect without scaling → base 0.3 with it.
    assert.strictEqual(L.rebase(0.4, 1.333, true), 0.3);
    // And back: 0.3 × 1.333 ≈ 0.4.
    assert.strictEqual(L.rebase(0.3, 1.333, false), 0.4);
    // 1080p at 1: unchanged.
    assert.strictEqual(L.rebase(0.7, 1, true), 0.7);
    // Bad factor counts as 1.
    assert.strictEqual(L.rebase(0.7, 0, true), 0.7);
    assert.strictEqual(L.rebase(0.7, undefined, false), 0.7);
    // Clamped.
    assert.strictEqual(L.rebase(3, 2, false), L.SPEED.max);
});

test("parseCodes / layoutItems", () => {
    const text = "us\tEnglish (US)\nee\tEstonian\n\nbad line\nde\tGerman\n";
    assert.deepStrictEqual(L.parseCodes(text), [
        { code: "us", name: "English (US)" }, { code: "ee", name: "Estonian" }, { code: "de", name: "German" }]);
    assert.deepStrictEqual(L.layoutItems(text).map(i => i.key), ["us", "ee", "de"]);
    assert.deepStrictEqual(L.layoutItems(text)[1], { key: "ee", label: "Estonian", detail: "ee" });
    assert.deepStrictEqual(L.parseCodes(""), []);
    assert.deepStrictEqual(L.parseCodes(undefined), []);
});

test("layoutName falls back to the code", () => {
    const items = L.layoutItems("ee\tEstonian\n");
    assert.strictEqual(L.layoutName(items, "ee"), "Estonian");
    assert.strictEqual(L.layoutName(items, "xx"), "xx");
});

test("formatSpeed / describeMonitor", () => {
    assert.strictEqual(L.formatSpeed(0.4), "0.40×");
    assert.strictEqual(L.formatSpeed(1.333), "1.33×");
    assert.strictEqual(L.describeMonitor({ monitor: "DP-3", width: 3840, height: 2160, scale: 1.5 }),
        "DP-3 · 3840×2160 at scale 1.5");
    assert.strictEqual(L.describeMonitor(null), "");
});
