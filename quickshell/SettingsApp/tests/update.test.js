const test = require("node:test");
const assert = require("node:assert");
const L = require("../UpdateLogic.js");

const CHECK = JSON.stringify({
    updates: [
        { name: "firefox", old: "130-1", new: "131-1", held: false },
        { name: "linux", old: "6.15.2-1", new: "6.15.3-1", held: true },
        { name: "grub", old: "2:2.12-1", new: "2:2.14-1", held: false }
    ],
    count: 2, held_count: 1, refreshed: false
});

test("parseCheck splits held from updates", () => {
    const r = L.parseCheck(CHECK);
    assert.strictEqual(r.error, null);
    assert.deepStrictEqual(r.updates.map(u => u.name), ["firefox", "grub"]);
    assert.deepStrictEqual(r.held.map(u => u.name), ["linux"]);
    assert.strictEqual(r.count, 2);
    assert.strictEqual(r.heldCount, 1);
    assert.strictEqual(r.updates[1].new, "2:2.14-1");
});

test("parseCheck: nothing to update", () => {
    const r = L.parseCheck('{"updates":[],"count":0,"held_count":0,"refreshed":true}');
    assert.deepStrictEqual(r, { updates: [], held: [], count: 0, heldCount: 0, error: null });
});

test("parseCheck falls back to list lengths when counts are missing", () => {
    const r = L.parseCheck('{"updates":[{"name":"a","old":"1","new":"2","held":false},{"name":"b","old":"1","new":"2","held":true}]}');
    assert.strictEqual(r.count, 1);
    assert.strictEqual(r.heldCount, 1);
});

test("parseCheck never throws on bad input", () => {
    for (const bad of ["", "   ", "not json", "{", "null", "[]", "42", '"x"', '{"updates":"x"}', null, undefined, 7]) {
        const r = L.parseCheck(bad);
        assert.ok(typeof r.error === "string" && r.error.length > 0, String(bad));
        assert.deepStrictEqual(r.updates, [], String(bad));
        assert.deepStrictEqual(r.held, [], String(bad));
        assert.strictEqual(r.count, 0);
        assert.strictEqual(r.heldCount, 0);
    }
});

test("parseCheck skips malformed entries", () => {
    const r = L.parseCheck('{"updates":[null,{"name":"a","old":"1","new":"2","held":false},5]}');
    assert.deepStrictEqual(r.updates.map(u => u.name), ["a"]);
    assert.strictEqual(r.error, null);
});

test("formatBytes is 1000-based with one decimal from kB", () => {
    assert.strictEqual(L.formatBytes(0), "0 B");
    assert.strictEqual(L.formatBytes(999), "999 B");
    assert.strictEqual(L.formatBytes(1023), "1.0 kB");
    assert.strictEqual(L.formatBytes(1500000), "1.5 MB");
    assert.strictEqual(L.formatBytes(6.9e9), "6.9 GB");
    assert.strictEqual(L.formatBytes(2.5e12), "2.5 TB");
});

test("formatBytes tolerates bad values", () => {
    for (const bad of [-1, NaN, null, undefined, "abc"])
        assert.strictEqual(L.formatBytes(bad), "0 B", String(bad));
    assert.strictEqual(L.formatBytes("2000"), "2.0 kB");
});

const KG = { created: "2026-10-17T10:00:00Z", kernel: "6.15.3-arch1-1", forced: false };

test("stateChip: unknown status", () => {
    assert.deepStrictEqual(L.stateChip(null), { text: "status unknown", tone: "error" });
    assert.deepStrictEqual(L.stateChip(undefined), { text: "status unknown", tone: "error" });
});

test("stateChip: pending states win over known-good", () => {
    const base = { known_good: KG, matches: true };
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "running" } }), { text: "update running", tone: "busy" });
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "failed" } }), { text: "update failed", tone: "error" });
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "awaiting-verification" } }), { text: "awaiting verification", tone: "busy" });
});

test("stateChip: no known-good", () => {
    assert.deepStrictEqual(L.stateChip({ known_good: null, pending: null, matches: false }), { text: "no recovery point", tone: "error" });
});

test("stateChip: known-good matches or not", () => {
    assert.deepStrictEqual(L.stateChip({ known_good: KG, pending: null, matches: true }), { text: "protected (known-good)", tone: "good" });
    assert.deepStrictEqual(L.stateChip({ known_good: KG, pending: null, matches: false }), { text: "not made through the safe flow", tone: "normal" });
});

test("stateChip: forced known-good", () => {
    const forced = { ...KG, forced: true };
    assert.deepStrictEqual(L.stateChip({ known_good: forced, pending: null, matches: true }), { text: "protected (known-good) (forced)", tone: "good" });
    assert.deepStrictEqual(L.stateChip({ known_good: forced, pending: null, matches: false }), { text: "not made through the safe flow (forced)", tone: "normal" });
});

test("stateChip: a failed update that changed packages says so", () => {
    const base = { known_good: KG, matches: false };
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "failed", changed: 3 } }),
        { text: "update failed, packages partly changed", tone: "error" });
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "failed", changed: 0 } }), { text: "update failed", tone: "error" });
    assert.deepStrictEqual(L.stateChip({ ...base, pending: { state: "failed", changed: null } }), { text: "update failed", tone: "error" });
});

test("stateChip: a pending dir without a readable record (state unknown) is an error", () => {
    assert.deepStrictEqual(L.stateChip({ known_good: KG, pending: { state: "unknown" }, matches: true }),
        { text: "update state unknown", tone: "error" });
});

test("stateChip: a discarded update is not 'not made through the safe flow'", () => {
    const st = { known_good: KG, pending: null, discarded: { state: "failed", started: "x", changed: 2 }, matches: false };
    assert.deepStrictEqual(L.stateChip(st), { text: "update discarded, not verified", tone: "busy" });
    // the installed set is the recovery point again (restored): the known-good decides
    assert.deepStrictEqual(L.stateChip({ ...st, matches: true }), { text: "protected (known-good)", tone: "good" });
    // a pending update still comes first
    assert.strictEqual(L.stateChip({ ...st, pending: { state: "awaiting-verification" } }).text, "awaiting verification");
    // no known-good at all still says so
    assert.strictEqual(L.stateChip({ ...st, known_good: null }).text, "no recovery point");
});

test("stateChip: a known-good that was never verified", () => {
    const unverified = { ...KG, source: "checkpoint", verified: false };
    assert.deepStrictEqual(L.stateChip({ known_good: unverified, pending: null, matches: true }), { text: "recovery point not verified", tone: "normal" });
    assert.deepStrictEqual(L.stateChip({ known_good: unverified, pending: null, matches: false }), { text: "not made through the safe flow", tone: "normal" });
    // verified, or an older status without the key: protected
    assert.strictEqual(L.stateChip({ known_good: { ...KG, verified: true }, pending: null, matches: true }).text, "protected (known-good)");
    // a forced one keeps its own label
    assert.strictEqual(L.stateChip({ known_good: { ...KG, forced: true, verified: false }, pending: null, matches: true }).text, "protected (known-good) (forced)");
});

test("partlyChanged: a failed record that changed packages", () => {
    assert.strictEqual(L.partlyChanged({ state: "failed", changed: 1 }), true);
    assert.strictEqual(L.partlyChanged({ state: "failed", changed: 0 }), false);
    assert.strictEqual(L.partlyChanged({ state: "awaiting-verification", changed: 4 }), false);
    assert.strictEqual(L.partlyChanged(null), false);
    assert.strictEqual(L.partlyChanged({ state: "failed" }), false);
});

test("stateChip: unknown pending state is shown, not swallowed", () => {
    const c = L.stateChip({ known_good: KG, pending: { state: "weird" }, matches: true });
    assert.strictEqual(c.tone, "error");
});

test("shouldRefresh: the second check since boot refreshes", () => {
    assert.strictEqual(L.shouldRefresh(0), false);
    assert.strictEqual(L.shouldRefresh(1), true);
    assert.strictEqual(L.shouldRefresh(2), true);
    assert.strictEqual(L.shouldRefresh(undefined), false);
});

test("clampKeep accepts 1..20, anything else is the default 3", () => {
    assert.strictEqual(L.clampKeep(1), 1);
    assert.strictEqual(L.clampKeep(20), 20);
    assert.strictEqual(L.clampKeep("5"), 5);
    assert.strictEqual(L.clampKeep(" 7\n"), 7);
    for (const bad of [0, 21, -2, "abc", "", 2.5, "2.5", null, undefined, NaN])
        assert.strictEqual(L.clampKeep(bad), 3, String(bad));
});

test("trimLog keeps the last lines", () => {
    assert.deepStrictEqual(L.trimLog(["a", "b", "c"], 2), ["b", "c"]);
    assert.deepStrictEqual(L.trimLog(["a"], 2), ["a"]);
});

test("exitMessage explains the CLI's exit codes", () => {
    assert.strictEqual(L.exitMessage(0), "");
    assert.match(L.exitMessage(3), /already running/);
    assert.match(L.exitMessage(4), /promote/);
    assert.match(L.exitMessage(126), /cancelled/);
    assert.match(L.exitMessage(127), /cancelled/);
    assert.match(L.exitMessage(1), /exit 1/);
});

test("cleanLine strips colors and carriage returns", () => {
    assert.strictEqual(L.cleanLine("\x1b[0;32m[INFO]\x1b[0m done\r"), "[INFO] done");
    assert.strictEqual(L.cleanLine("plain"), "plain");
});

test("pendingKey identifies the pending record", () => {
    assert.strictEqual(L.pendingKey(null), "");
    assert.strictEqual(L.pendingKey({ known_good: null, pending: null }), "");
    const a = { pending: { state: "awaiting-verification", started: "2026-10-17T10:00:00Z" } };
    const b = { pending: { state: "awaiting-verification", started: "2026-10-18T10:00:00Z" } };
    assert.notStrictEqual(L.pendingKey(a), "");
    assert.strictEqual(L.pendingKey(a), L.pendingKey(JSON.parse(JSON.stringify(a))));
    assert.notStrictEqual(L.pendingKey(a), L.pendingKey(b));
    assert.notStrictEqual(L.pendingKey(a), L.pendingKey({ pending: { state: "failed", started: a.pending.started } }));
});

test("dayOf keeps the date of an ISO time", () => {
    assert.strictEqual(L.dayOf("2026-10-17T10:00:00Z"), "2026-10-17");
    assert.strictEqual(L.dayOf("unknown"), "unknown");
    assert.strictEqual(L.dayOf(undefined), "");
});
