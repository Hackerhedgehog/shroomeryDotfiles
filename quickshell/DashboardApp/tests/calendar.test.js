const test = require("node:test");
const assert = require("node:assert");
const C = require("../CalendarModel.js");

test("October 2026 starts on Thursday, Monday-first grid", () => {
  const g = C.monthGrid(2026, 9, { y: 2026, m: 9, d: 11 });
  assert.strictEqual(g.days.length, 42);
  assert.deepStrictEqual(g.days[0], { day: 28, inMonth: false, isToday: false });   // Mon 28 Sep
  assert.deepStrictEqual(g.days[3], { day: 1, inMonth: true, isToday: false });
  assert.deepStrictEqual(g.days[13], { day: 11, inMonth: true, isToday: true });
  assert.strictEqual(g.weeks.length, 6);
  assert.strictEqual(g.weeks[0], 40);
});

test("ISO week 53 at the end of 2026", () => {
  assert.strictEqual(C.isoWeek(2026, 11, 28), 53);
  assert.strictEqual(C.monthGrid(2027, 0, null).weeks[0], 53);
});

test("shiftMonth wraps years", () => {
  assert.deepStrictEqual(C.shiftMonth(2026, 11, 1), { year: 2027, month: 0 });
  assert.deepStrictEqual(C.shiftMonth(2026, 0, -1), { year: 2025, month: 11 });
});
