const test = require("node:test");
const assert = require("node:assert");
const L = require("../TimeLogic.js");

test("timeFormat / parseTimeFormat round trip", () => {
    assert.strictEqual(L.timeFormat(true, false), "HH:mm");
    assert.strictEqual(L.timeFormat(true, true), "HH:mm:ss");
    assert.strictEqual(L.timeFormat(false, false), "h:mm AP");
    assert.strictEqual(L.timeFormat(false, true), "h:mm:ss AP");
    for (const h24 of [true, false])
        for (const s of [true, false])
            assert.deepStrictEqual(L.parseTimeFormat(L.timeFormat(h24, s)), { h24, seconds: s });
    // Quoted text doesn't count.
    assert.deepStrictEqual(L.parseTimeFormat("HH:mm 'as'"), { h24: true, seconds: false });
    assert.deepStrictEqual(L.parseTimeFormat(""), { h24: true, seconds: false });
});

test("withoutSeconds", () => {
    assert.strictEqual(L.withoutSeconds("HH:mm:ss"), "HH:mm");
    assert.strictEqual(L.withoutSeconds("h:mm:ss AP"), "h:mm AP");
    assert.strictEqual(L.withoutSeconds("HH:mm"), "HH:mm");
});

test("validDate", () => {
    assert.ok(L.validDate("2026-11-07"));
    assert.ok(L.validDate("2028-02-29"));
    assert.ok(L.validDate("2000-02-29"));
    assert.ok(!L.validDate("1900-02-29"));
    assert.ok(!L.validDate("2026-02-29"));
    assert.ok(!L.validDate("2026-04-31"));
    assert.ok(!L.validDate("2026-13-01"));
    assert.ok(!L.validDate("2026-00-10"));
    assert.ok(!L.validDate("2026-1-1"));
    assert.ok(!L.validDate(""));
});

test("normalizeTime", () => {
    assert.strictEqual(L.normalizeTime("7:05"), "07:05:00");
    assert.strictEqual(L.normalizeTime("23:59:59"), "23:59:59");
    assert.strictEqual(L.normalizeTime(" 12:30 "), "12:30:00");
    for (const bad of ["24:00", "12:60", "12:30:60", "1230", "", "ab:cd"])
        assert.strictEqual(L.normalizeTime(bad), "", bad);
});

test("composeDateTime", () => {
    assert.strictEqual(L.composeDateTime("2026-11-07", "9:15"), "2026-11-07 09:15:00");
    assert.strictEqual(L.composeDateTime("2026-02-30", "9:15"), "");
    assert.strictEqual(L.composeDateTime("2026-11-07", "25:00"), "");
});

test("dateInput / timeInput", () => {
    const d = new Date(2026, 0, 5, 3, 4, 9);
    assert.strictEqual(L.dateInput(d), "2026-01-05");
    assert.strictEqual(L.timeInput(d), "03:04:09");
});

test("timezones", () => {
    assert.strictEqual(L.formatOffset("+0530"), "UTC+05:30");
    assert.strictEqual(L.formatOffset("-0300"), "UTC-03:00");
    assert.strictEqual(L.formatOffset(""), "");
    assert.deepStrictEqual(L.timezoneItems("America/New_York\t-0500\n\nUTC\t+0000\nOdd\n"), [
        { key: "America/New_York", label: "America/New York", detail: "UTC-05:00" },
        { key: "UTC", label: "UTC", detail: "UTC+00:00" },
        { key: "Odd", label: "Odd", detail: "" }
    ]);
});

test("parseLocales", () => {
    const out = L.parseLocales("et_EE.UTF-8\t1\tEstonian\tEstonia\nC.UTF-8\t1\t\t\nsr_RS@latin\t0\tSerbian\tSerbia\n");
    assert.deepStrictEqual(out.map(l => l.label), ["C.UTF-8 · C", "Estonian (Estonia) · et_EE", "Serbian (Serbia) · sr_RS@latin"]);
    assert.deepStrictEqual(out.map(l => l.installed), [true, true, false]);
    assert.strictEqual(L.qtLocaleName("et_EE.UTF-8"), "et_EE");
    assert.strictEqual(L.qtLocaleName("sr_RS@latin"), "sr_RS");
});

const now = { LANG: "en_US.UTF-8", LC_TIME: "et_EE.UTF-8", LC_MONETARY: "et_EE.UTF-8", LC_NUMERIC: "et_EE.UTF-8" };

test("effective / formatsValue", () => {
    assert.strictEqual(L.effective(now, "LC_TIME"), "et_EE.UTF-8");
    assert.strictEqual(L.effective(now, "LC_PAPER"), "en_US.UTF-8");
    // Paper and measurement follow LANG: mixed.
    assert.strictEqual(L.formatsValue(now), "");
    assert.strictEqual(L.formatsValue(L.setFormats(now, "et_EE.UTF-8")), "et_EE.UTF-8");
    assert.strictEqual(L.formatsValue({ LANG: "de_DE.UTF-8" }), "de_DE.UTF-8");
});

test("setFormats sets all format categories; tidy drops repeats of LANG", () => {
    assert.deepStrictEqual(L.setFormats(now, "et_EE.UTF-8"), {
        LANG: "en_US.UTF-8", LC_TIME: "et_EE.UTF-8", LC_MONETARY: "et_EE.UTF-8", LC_NUMERIC: "et_EE.UTF-8",
        LC_PAPER: "et_EE.UTF-8", LC_MEASUREMENT: "et_EE.UTF-8"
    });
    assert.deepStrictEqual(L.setFormats(now, "en_US.UTF-8"), { LANG: "en_US.UTF-8" });
});

test("setLanguage keeps the formats the user sees", () => {
    const out = L.setLanguage({ LANG: "en_US.UTF-8" }, "et_EE.UTF-8");
    assert.strictEqual(out.LANG, "et_EE.UTF-8");
    for (const v of L.FORMAT_VARS)
        assert.strictEqual(out[v], "en_US.UTF-8", v);
    // Sorting and messages follow the new language.
    assert.strictEqual(out.LC_COLLATE, undefined);
    assert.strictEqual(out.LC_MESSAGES, undefined);
    // Switching the language to the formats' locale folds them away.
    assert.deepStrictEqual(L.setLanguage(L.setFormats(now, "et_EE.UTF-8"), "et_EE.UTF-8"), { LANG: "et_EE.UTF-8" });
});

test("setCategory", () => {
    assert.strictEqual(L.setCategory(now, "LC_PAPER", "et_EE.UTF-8").LC_PAPER, "et_EE.UTF-8");
    assert.strictEqual(L.setCategory(now, "LC_TIME", "").LC_TIME, undefined);
});

test("sameDraft / localeArgs", () => {
    assert.ok(L.sameDraft(now, Object.assign({}, now)));
    assert.ok(L.sameDraft(now, Object.assign({ LC_PAPER: "en_US.UTF-8" }, now)));
    assert.ok(!L.sameDraft(now, L.setFormats(now, "et_EE.UTF-8")));
    assert.deepStrictEqual(L.localeArgs(now),
        ["LANG=en_US.UTF-8", "LC_MONETARY=et_EE.UTF-8", "LC_NUMERIC=et_EE.UTF-8", "LC_TIME=et_EE.UTF-8"]);
    assert.deepStrictEqual(L.localeArgs({}), []);
});

test("offsetOf", () => {
    const fake = m => ({ getTimezoneOffset: () => m });
    assert.strictEqual(L.offsetOf(fake(-120)), "+0200");
    assert.strictEqual(L.offsetOf(fake(-330)), "+0530");
    assert.strictEqual(L.offsetOf(fake(300)), "-0500");
    assert.strictEqual(L.offsetOf(fake(0)), "+0000");
});
