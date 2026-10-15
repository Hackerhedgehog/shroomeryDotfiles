const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const E = require("../Emoji.js");

const sample = [
  "# a comment",
  "",
  "😀\tSmileys & Emotion\tgrinning face\tface grin happy",
  "👋\tPeople & Body\twaving hand\thand wave",
  "🇪🇪\tFlags\tflag: Estonia\t",
  "🦄\tUnknown Group\tunicorn\tmagic",
].join("\n");

test("parse reads emoji, category, name and keywords, skipping comments", () => {
  const list = E.parse(sample);
  assert.deepStrictEqual(list.map(e => e.emoji), ["😀", "👋", "🇪🇪"]);
  assert.deepStrictEqual(list[0], {
    emoji: "😀", category: "smileys", name: "grinning face", keywords: "face grin happy",
  });
  assert.strictEqual(list[2].category, "flags");
  assert.strictEqual(list[2].keywords, "");
});

test("parse drops rows from unknown groups and malformed rows", () => {
  const list = E.parse("x\ty\n🦄\tUnknown\tunicorn\tmagic\n");
  assert.strictEqual(list.length, 0);
});

test("every category has a key, icon and label", () => {
  assert.strictEqual(E.CATEGORIES.length, 9);
  for (const c of E.CATEGORIES) {
    assert.ok(c.key && c.icon && c.label && c.group, JSON.stringify(c));
  }
});

test("the bundled emojis.tsv parses into every category", () => {
  const text = fs.readFileSync(path.join(__dirname, "..", "emojis.tsv"), "utf8");
  const list = E.parse(text);
  assert.ok(list.length > 1800, `only ${list.length} emoji`);
  for (const c of E.CATEGORIES)
    assert.ok(list.some(e => e.category === c.key), `no emoji in ${c.key}`);
  assert.ok(!list.some(e => /skin tone/.test(e.name)), "skin tone variants left in");
  const names = new Set(list.map(e => e.name));
  assert.strictEqual(names.size, list.length, "an emoji is listed twice");
});

test("gridMove: steps within the grid and clamps at its ends", () => {
  // 10 cells, 4 columns.
  assert.strictEqual(E.gridMove(0, 1, 10), 1);
  assert.strictEqual(E.gridMove(1, 4, 10), 5);
  assert.strictEqual(E.gridMove(8, 4, 10), 9);
  assert.strictEqual(E.gridMove(2, -4, 10), 0);
  assert.strictEqual(E.gridMove(0, -1, 10), 0);
  assert.strictEqual(E.gridMove(0, 1, 0), 0);
});

test("sideStep: moves within the row, or off its edge into a category", () => {
  // 10 cells, 4 columns: rows [0..3] [4..7] [8, 9].
  assert.deepStrictEqual(E.sideStep(1, 1, 10, 4), { index: 2, category: 0 });
  assert.deepStrictEqual(E.sideStep(1, -1, 10, 4), { index: 0, category: 0 });
  // Left from the first column, right from the last column or last cell.
  assert.deepStrictEqual(E.sideStep(4, -1, 10, 4), { index: -1, category: -1, row: 1 });
  assert.deepStrictEqual(E.sideStep(7, 1, 10, 4), { index: -1, category: 1, row: 1 });
  assert.deepStrictEqual(E.sideStep(9, 1, 10, 4), { index: -1, category: 1, row: 2 });
  assert.deepStrictEqual(E.sideStep(0, -1, 0, 4), { index: -1, category: -1, row: 0 });
});

test("landing: same row in the new category, at the side it was entered from", () => {
  // Entered moving left: the row's last cell; moving right: its first.
  assert.strictEqual(E.landing(1, -1, 10, 4), 7);
  assert.strictEqual(E.landing(1, 1, 10, 4), 4);
  // A short last row, and a category with fewer rows.
  assert.strictEqual(E.landing(2, -1, 10, 4), 9);
  assert.strictEqual(E.landing(5, 1, 10, 4), 8);
  assert.strictEqual(E.landing(5, -1, 10, 4), 9);
  assert.strictEqual(E.landing(0, 1, 0, 4), 0);
});
