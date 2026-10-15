const test = require("node:test");
const assert = require("node:assert");
const L = require("../KeybindsLogic.js");

const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000;
// A slice of the keymap keybinds.py prints for the Estonian layout.
const keymap = { "10": "1", "24": "q", "34": "udiaeresis", "36": "Return", "50": "Shift_L", "108": "ISO_Level3_Shift", "133": "Super_L" };

test("parseKeys normalizes modifier names and order", () => {
  assert.deepStrictEqual(L.parseKeys("SHIFT + SUPER + q"), { mods: ["SUPER", "SHIFT"], key: "q" });
  assert.deepStrictEqual(L.parseKeys("CONTROL + ALT + T"), { mods: ["CTRL", "ALT"], key: "T" });
  assert.deepStrictEqual(L.parseKeys("XF86AudioMute"), { mods: [], key: "XF86AudioMute" });
});

test("comboIdOf ignores key case and modifier spelling", () => {
  assert.strictEqual(L.comboIdOf("SUPER + CONTROL + left"), L.comboIdOf("SUPER + CTRL + Left"));
  assert.notStrictEqual(L.comboIdOf("SUPER + Q"), L.comboIdOf("SUPER + SHIFT + Q"));
  assert.strictEqual(L.comboIdOf(""), "");
});

test("comboFromEvent names keys by the layout's unshifted keysym", () => {
  // Shift+1 reports Qt.Key_Exclam, but Hyprland binds it as "1".
  assert.deepStrictEqual(L.comboFromEvent(0x21, META | SHIFT, 10, keymap), { mods: ["SUPER", "SHIFT"], key: "1" });
  assert.deepStrictEqual(L.comboFromEvent(0x51, META | CTRL | ALT, 24, keymap), { mods: ["SUPER", "CTRL", "ALT"], key: "Q" });
  assert.deepStrictEqual(L.comboFromEvent(0xdc, META, 34, keymap), { mods: ["SUPER"], key: "udiaeresis" });
});

test("comboFromEvent ignores modifiers pressed on their own", () => {
  assert.strictEqual(L.comboFromEvent(0x01000020, SHIFT, 50, keymap), null);
  assert.strictEqual(L.comboFromEvent(0x01001103, 0, 108, keymap), null);
  assert.strictEqual(L.comboFromEvent(0x01000053, META, 133, keymap), null);
});

test("comboFromEvent falls back to Qt key names without a keymap", () => {
  assert.deepStrictEqual(L.comboFromEvent(0x01000033, META, 999, {}), { mods: ["SUPER"], key: "F4" });
  assert.deepStrictEqual(L.comboFromEvent(0x01000012, 0, 999, null), { mods: [], key: "Left" });
  assert.strictEqual(L.comboFromEvent(0x0100ffff, 0, 999, {}), null);
});

test("keysString writes modifiers in a fixed order", () => {
  assert.strictEqual(L.keysString(["SHIFT", "SUPER"], "T"), "SUPER + SHIFT + T");
  assert.strictEqual(L.keysString([], "F1"), "F1");
});

test("chips label keys for the key caps", () => {
  assert.deepStrictEqual(L.chips("SUPER + mouse:272"), ["SUPER", "Left click"]);
  assert.deepStrictEqual(L.chips("SUPER + PERIOD"), ["SUPER", "."]);
  assert.deepStrictEqual(L.chips("SUPER + q"), ["SUPER", "Q"]);
  assert.deepStrictEqual(L.chips("XF86AudioRaiseVolume"), ["Volume up"]);
});

test("conflicts finds other bound binds on the same combo", () => {
  const a = { keys: "SUPER + Q", offset: 10 };
  const b = { keys: "SUPER + q", offset: 20 };
  const c = { keys: "SUPER + Q", offset: 30, unbound: true };
  const d = { keys: "SUPER + SHIFT + Q", offset: 40 };
  const binds = [a, b, c, d];
  assert.deepStrictEqual(L.conflicts(binds, ["SUPER"], "Q", a), [b]);
  assert.deepStrictEqual(L.conflicts(binds, ["SUPER", "SHIFT"], "q", a), [d]);
  assert.deepStrictEqual(L.conflicts(binds, ["CTRL"], "Q", a), []);
});

test("visibleBinds filters by words and section and marks section heads", () => {
  const sections = [
    { label: "Apps", binds: [{ keys: "SUPER + Q", description: "Open the terminal", command: "kitty" },
                             { keys: "SUPER + W", description: "Open the browser", command: "firefox" }] },
    { label: "Media", binds: [{ keys: "XF86AudioMute", description: "Mute audio", command: "wpctl" }] }
  ];
  const all = L.visibleBinds(sections, "", "");
  assert.deepStrictEqual(all.map(r => r.header), ["Apps", "", "Media"]);
  assert.deepStrictEqual(L.visibleBinds(sections, "open kitty", "").map(r => r.bind.command), ["kitty"]);
  assert.deepStrictEqual(L.visibleBinds(sections, "mute", "").map(r => r.header), ["Media"]);
  assert.deepStrictEqual(L.visibleBinds(sections, "", "Media").length, 1);
  assert.deepStrictEqual(L.visibleBinds(sections, "super w", "").map(r => r.bind.command), ["firefox"]);
});

test("heldMods tracks a modifier pressed or released on its own", () => {
  assert.deepStrictEqual(L.heldMods(0x01000020, 0, true), ["SHIFT"]);
  assert.deepStrictEqual(L.heldMods(0x01000022, SHIFT, true), ["SUPER", "SHIFT"]);
  assert.deepStrictEqual(L.heldMods(0x01000020, META | SHIFT, false), ["SUPER"]);
  assert.deepStrictEqual(L.heldMods(0x41, CTRL, true), ["CTRL"]);
});

test("comboFromMouse names buttons by evdev code", () => {
  assert.deepStrictEqual(L.comboFromMouse(1, META), { mods: ["SUPER"], key: "mouse:272" });
  assert.deepStrictEqual(L.comboFromMouse(2, CTRL | ALT), { mods: ["CTRL", "ALT"], key: "mouse:273" });
  assert.deepStrictEqual(L.comboFromMouse(4, 0), { mods: [], key: "mouse:274" });
  assert.deepStrictEqual(L.comboFromMouse(8, 0).key, "mouse:275");    // Qt.BackButton, BTN_SIDE
  assert.deepStrictEqual(L.comboFromMouse(16, 0).key, "mouse:276");   // Qt.ForwardButton, BTN_EXTRA
  assert.deepStrictEqual(L.comboFromMouse(32, 0).key, "mouse:277");
  assert.strictEqual(L.comboFromMouse(0, 0), null);
  assert.strictEqual(L.comboFromMouse(3, 0), null);
});

test("comboFromWheel matches Hyprland's scroll names", () => {
  assert.deepStrictEqual(L.comboFromWheel(0, -120, META), { mods: ["SUPER"], key: "mouse_down" });
  assert.deepStrictEqual(L.comboFromWheel(0, 120, META).key, "mouse_up");
  assert.deepStrictEqual(L.comboFromWheel(120, 0, 0).key, "mouse_left");
  assert.deepStrictEqual(L.comboFromWheel(-120, 10, 0).key, "mouse_right");
  assert.strictEqual(L.comboFromWheel(0, 0, 0), null);
});

test("comboProblem refuses bare keys that would break normal input", () => {
  assert.notStrictEqual(L.comboProblem({ mods: [], key: "Q" }, false), "");
  assert.notStrictEqual(L.comboProblem({ mods: [], key: "mouse:272" }, false), "");
  assert.notStrictEqual(L.comboProblem({ mods: [], key: "mouse_down" }, false), "");
  assert.strictEqual(L.comboProblem({ mods: [], key: "mouse:276" }, false), "");
  assert.strictEqual(L.comboProblem({ mods: [], key: "F5" }, false), "");
  assert.strictEqual(L.comboProblem({ mods: [], key: "XF86AudioMute" }, false), "");
  assert.strictEqual(L.comboProblem({ mods: ["SUPER"], key: "mouse:272" }, false), "");
  assert.notStrictEqual(L.comboProblem({ mods: ["SUPER"], key: "Q" }, true), "");
  assert.strictEqual(L.comboProblem({ mods: ["SUPER"], key: "mouse:273" }, true), "");
});
