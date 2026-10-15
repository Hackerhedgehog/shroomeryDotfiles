const test = require("node:test");
const assert = require("node:assert");
const L = require("../NightLightLogic.js");

test("parseTime accepts H:MM and HH:MM", () => {
    assert.strictEqual(L.parseTime("00:00"), 0);
    assert.strictEqual(L.parseTime("07:05"), 425);
    assert.strictEqual(L.parseTime("7:05"), 425);
    assert.strictEqual(L.parseTime(" 23:59 "), 1439);
});

test("parseTime rejects malformed times", () => {
    for (const bad of ["24:00", "12:60", "7:5", "abc", "", "0700", null, undefined, 700])
        assert.strictEqual(L.parseTime(bad), -1, String(bad));
});

test("formatTime pads", () => {
    assert.strictEqual(L.formatTime(0), "00:00");
    assert.strictEqual(L.formatTime(425), "07:05");
    assert.strictEqual(L.formatTime(1439), "23:59");
});

test("clampInt", () => {
    assert.strictEqual(L.clampInt(4500, 2500, 6500, 4500), 4500);
    assert.strictEqual(L.clampInt(1000, 2500, 6500, 4500), 2500);
    assert.strictEqual(L.clampInt(9000, 2500, 6500, 4500), 6500);
    assert.strictEqual(L.clampInt("3000", 2500, 6500, 4500), 3000);
    assert.strictEqual(L.clampInt(80.4, 50, 100, 100), 80);
    assert.strictEqual(L.clampInt("abc", 2500, 6500, 4500), 4500);
    assert.strictEqual(L.clampInt("", 50, 100, 100), 100);
    assert.strictEqual(L.clampInt(true, 50, 100, 100), 100);
    assert.strictEqual(L.clampInt(null, 50, 100, 100), 100);
});

test("normalize: empty/missing → defaults", () => {
    assert.deepStrictEqual(L.normalize({}), L.DEFAULTS);
    assert.deepStrictEqual(L.normalize(null), L.DEFAULTS);
    assert.deepStrictEqual(L.normalize("nope"), L.DEFAULTS);
});

test("normalize: valid values kept, times padded", () => {
    assert.deepStrictEqual(
        L.normalize({ mode: "sun", on: "7:30", off: "6:00", temperature: 3200, gamma: "80" }),
        { mode: "sun", on: "07:30", off: "06:00", temperature: 3200, gamma: 80 });
});

test("normalize: bad values → defaults or clamped", () => {
    assert.deepStrictEqual(
        L.normalize({ mode: "party", on: "25:00", temperature: 99999, gamma: true }),
        { mode: "off", on: "21:00", off: "07:00", temperature: 6500, gamma: 100 });
});

test("normalize returns a fresh object", () => {
    const a = L.normalize({});
    a.mode = "sun";
    assert.strictEqual(L.DEFAULTS.mode, "off");
});

test("parseSunTimes", () => {
    assert.deepStrictEqual(L.parseSunTimes("07:58 18:15\n"), { sunrise: "07:58", sunset: "18:15" });
    assert.strictEqual(L.parseSunTimes(""), null);
    assert.strictEqual(L.parseSunTimes("07:58"), null);
    assert.strictEqual(L.parseSunTimes("error 18:15"), null);
});
