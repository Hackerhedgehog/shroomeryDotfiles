const test = require("node:test");
const assert = require("node:assert");
const P = require("../PickerLogic.js");

const zones = [
    { key: "America/New_York", label: "America/New York", detail: "-0500" },
    { key: "Europe/Tallinn", label: "Europe/Tallinn", detail: "+0200" },
    { key: "Asia/Tokyo", label: "Asia/Tokyo", detail: "+0900" },
    { key: "Tokyo/Fake", label: "Tokyo", detail: "" }
];

test("empty query keeps everything, in order (a copy)", () => {
    const out = P.filterItems(zones, "  ");
    assert.deepStrictEqual(out, zones);
    assert.notStrictEqual(out, zones);
});

test("matches label, detail and key, case-insensitive", () => {
    assert.deepStrictEqual(P.filterItems(zones, "TALLINN").map(z => z.key), ["Europe/Tallinn"]);
    assert.deepStrictEqual(P.filterItems(zones, "+0900").map(z => z.key), ["Asia/Tokyo"]);
});

test("_ and / count as spaces", () => {
    assert.deepStrictEqual(P.filterItems(zones, "new york").map(z => z.key), ["America/New_York"]);
    assert.deepStrictEqual(P.filterItems(zones, "new_york").map(z => z.key), ["America/New_York"]);
    assert.deepStrictEqual(P.filterItems(zones, "america new").map(z => z.key), ["America/New_York"]);
});

test("every word must match, in any order", () => {
    assert.deepStrictEqual(P.filterItems(zones, "york america").map(z => z.key), ["America/New_York"]);
    assert.deepStrictEqual(P.filterItems(zones, "york tokyo"), []);
});

test("label prefix matches come first", () => {
    assert.deepStrictEqual(P.filterItems(zones, "tokyo").map(z => z.key), ["Tokyo/Fake", "Asia/Tokyo"]);
});

test("missing fields and lists are tolerated", () => {
    assert.deepStrictEqual(P.filterItems(null, "x"), []);
    assert.deepStrictEqual(P.filterItems([{ key: "us" }], "us").map(i => i.key), ["us"]);
});

test("indexOfKey", () => {
    assert.strictEqual(P.indexOfKey(zones, "Asia/Tokyo"), 2);
    assert.strictEqual(P.indexOfKey(zones, "nope"), -1);
    assert.strictEqual(P.indexOfKey(undefined, "x"), -1);
});
