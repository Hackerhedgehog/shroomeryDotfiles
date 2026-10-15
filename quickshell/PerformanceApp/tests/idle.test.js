const test = require("node:test");
const assert = require("node:assert");
const L = require("../IdleLogic.js");

// A trimmed copy of the stock hypridle.conf: one active block, one
// hand-commented "# listener {" block, one active and one "#listener {" block.
const conf = [
    "general {",
    "    lock_cmd = pidof hyprlock || hyprlock",
    "}",
    "",
    "listener {",
    "    timeout = 480                                # 8min.",
    "    on-timeout = brightnessctl -s set 10         # set monitor backlight to minimum.",
    "    on-resume = brightnessctl -r",
    "}",
    "",
    "# turn off keyboard backlight, comment out this section if you dont have one.",
    "# listener { ",
    "#     timeout = 480",
    "#     on-timeout = brightnessctl -sd rgb:kbd_backlight set 0",
    "# }",
    "",
    "listener {",
    "    timeout = 600                                 # 10min",
    "    on-timeout = loginctl lock-session            # lock screen",
    "}",
    "",
    "#listener {",
    "#    timeout = 1800                                # 30min",
    "#    on-timeout = systemctl suspend                # suspend pc",
    "#}",
    ""
].join("\n");

test("parseListeners finds active and commented blocks with labels", () => {
    const blocks = L.parseListeners(conf);
    assert.deepStrictEqual(blocks.map(b => [b.label, b.timeout, b.enabled]), [
        ["Dim the screen", 480, true],
        ["Keyboard backlight off", 480, false],
        ["Lock the screen", 600, true],
        ["Suspend", 1800, false]
    ]);
});

test("describe falls back to the comment, then the command", () => {
    assert.strictEqual(L.describe("notify-send hi", "say hi."), "Say hi");
    assert.strictEqual(L.describe("notify-send hi", ""), "notify-send hi");
});

test("setting a new time keeps the line and updates a duration comment", () => {
    const out = L.setTimeoutAt(conf, 2, 900);
    assert.match(out, /^    timeout = 900 {33}# 15min$/m);
    assert.strictEqual(L.parseListeners(out)[2].timeout, 900);
    assert.strictEqual(out.split("\n").length, conf.split("\n").length);
});

test("never comments the block out, and a time brings it back unchanged", () => {
    const off = L.setTimeoutAt(conf, 0, 0);
    assert.strictEqual(L.parseListeners(off)[0].enabled, false);
    assert.match(off, /^#listener \{$/m);
    assert.strictEqual(L.setTimeoutAt(off, 0, 480), conf);
});

test("enabling a commented block uncomments it", () => {
    const on = L.setTimeoutAt(conf, 3, 3600);
    const block = L.parseListeners(on)[3];
    assert.deepStrictEqual([block.enabled, block.timeout], [true, 3600]);
    assert.match(on, /^listener \{\n    timeout = 3600 +# 1h\n    on-timeout = systemctl suspend/m);

    const kbd = L.setTimeoutAt(conf, 1, 300);
    assert.match(kbd, /^listener \{ \n    timeout = 300\n    on-timeout = brightnessctl -sd/m);
    assert.match(kbd, /^# turn off keyboard backlight/m);
});

test("never on a commented block and a bad index change nothing", () => {
    assert.strictEqual(L.setTimeoutAt(conf, 3, 0), conf);
    assert.strictEqual(L.setTimeoutAt(conf, 9, 60), conf);
});

test("choices include an odd current timeout and select never when off", () => {
    const odd = L.choices({ timeout: 660, enabled: true });
    assert.strictEqual(odd.labels[odd.index], "11 min");
    assert.strictEqual(odd.labels[odd.labels.length - 1], "Never");
    const off = L.choices({ timeout: 1800, enabled: false });
    assert.strictEqual(off.labels[off.index], "Never");
    assert.strictEqual(L.formatSeconds(5400), "1 h 30 min");
});
