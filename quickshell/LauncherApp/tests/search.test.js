const test = require("node:test");
const assert = require("node:assert");
const S = require("../Search.js");

const apps = [
  { name: "Firefox", fields: ["Firefox", "Web Browser", "internet;www"] },
  { name: "Files", fields: ["Files", "File Manager", "folder;nautilus"] },
  { name: "Kitty", fields: ["Kitty", "Terminal Emulator", "shell"] },
  { name: "LibreOffice Writer", fields: ["LibreOffice Writer", "Word Processor", ""] },
];

function names(query) {
  return S.filter(apps, query, a => a.name, a => a.fields).map(a => a.name);
}

test("empty query keeps every item in order", () => {
  assert.deepStrictEqual(names(""), ["Firefox", "Files", "Kitty", "LibreOffice Writer"]);
  assert.deepStrictEqual(names("   "), names(""));
});

test("matches case-insensitively in any field", () => {
  assert.deepStrictEqual(names("TERMINAL"), ["Kitty"]);
  assert.deepStrictEqual(names("www"), ["Firefox"]);
});

test("every word must match, in any order", () => {
  assert.deepStrictEqual(names("writer libre"), ["LibreOffice Writer"]);
  assert.deepStrictEqual(names("libre kitty"), []);
});

test("name prefix beats name substring beats other fields", () => {
  const items = [
    { name: "Disks", fields: ["Disks", "file systems"] },
    { name: "Profile Editor", fields: ["Profile Editor", ""] },
    { name: "Files", fields: ["Files", ""] },
  ];
  const got = S.filter(items, "fi", i => i.name, i => i.fields).map(i => i.name);
  assert.deepStrictEqual(got, ["Files", "Profile Editor", "Disks"]);
});
