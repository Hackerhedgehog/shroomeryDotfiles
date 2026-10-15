const test = require("node:test");
const assert = require("node:assert");
const P = require("../PopoutLogic.js");

const A = { id: "audio-button" };
const N = { id: "network-button" };
const B = { id: "audio-button-on-HDMI" };

function run(events, start) {
  let state = start || P.initial();
  let effects = [];
  for (const ev of events) {
    const r = P.reduce(state, ev);
    state = r.state;
    effects = r.effects;
  }
  return { state, effects };
}

// Hover-opening buttons (like the taskbar's window lists).
const hoverA = { type: "hover", screen: "DP-2", name: "audio", anchor: A, opens: true };
const hoverN = { type: "hover", screen: "DP-2", name: "network", anchor: N, opens: true };
// Click-only buttons (most of the bar).
const clickA = { type: "click", screen: "DP-2", name: "audio", anchor: A };
const clickN = { type: "click", screen: "DP-2", name: "network", anchor: N };
const passA = { type: "hover", screen: "DP-2", name: "audio", anchor: A, opens: false };
const passN = { type: "hover", screen: "DP-2", name: "network", anchor: N, opens: false };
const openedA = run([hoverA, { type: "openTimer" }]).state;

test("starts closed", () => {
  assert.deepStrictEqual(P.initial(), { name: "", screen: "", anchor: null, pinned: false, pending: null });
});

test("hovering an icon while closed waits for the open delay", () => {
  const r = P.reduce(P.initial(), hoverA);
  assert.strictEqual(r.state.name, "");
  assert.deepStrictEqual(r.state.pending, { screen: "DP-2", name: "audio", anchor: A });
  assert.deepStrictEqual(r.effects, ["startOpenTimer"]);
});

test("the open delay opens the hovered panel unpinned", () => {
  assert.strictEqual(openedA.name, "audio");
  assert.strictEqual(openedA.screen, "DP-2");
  assert.strictEqual(openedA.anchor, A);
  assert.strictEqual(openedA.pinned, false);
  assert.strictEqual(openedA.pending, null);
});

test("leaving the icon before the delay opens nothing", () => {
  const { state, effects } = run([hoverA, { type: "unhover", anchor: A }]);
  assert.strictEqual(state.pending, null);
  assert.deepStrictEqual(effects, ["stopOpenTimer"]);
  assert.strictEqual(P.reduce(state, { type: "openTimer" }).state.name, "");
});

test("a fast sweep opens only the icon the pointer rests on", () => {
  const { state } = run([hoverA, { type: "unhover", anchor: A }, hoverN, { type: "openTimer" }]);
  assert.strictEqual(state.name, "network");
  assert.strictEqual(state.anchor, N);
});

test("unhover of an icon that is not pending changes nothing", () => {
  const r = P.reduce(openedA, { type: "unhover", anchor: N });
  assert.deepStrictEqual(r.state, openedA);
  assert.deepStrictEqual(r.effects, []);
});

test("hovering another icon while open morphs at once", () => {
  const r = P.reduce(openedA, hoverN);
  assert.strictEqual(r.state.name, "network");
  assert.strictEqual(r.state.anchor, N);
  assert.ok(!r.effects.includes("startOpenTimer"));
  assert.ok(r.effects.includes("stopCloseTimer"));
});

test("leaving pill and panel starts the close delay, coming back cancels it", () => {
  assert.deepStrictEqual(P.reduce(openedA, { type: "pointer", screen: "DP-2", inside: false }).effects, ["startCloseTimer"]);
  assert.deepStrictEqual(P.reduce(openedA, { type: "pointer", screen: "DP-2", inside: true }).effects, ["stopCloseTimer"]);
});

test("the close delay closes an unpinned panel", () => {
  assert.deepStrictEqual(P.reduce(openedA, { type: "closeTimer" }).state, P.initial());
});

test("a press pins the panel: leaving no longer closes it", () => {
  const pinned = P.reduce(openedA, { type: "press" }).state;
  assert.strictEqual(pinned.pinned, true);
  assert.deepStrictEqual(P.reduce(pinned, { type: "pointer", screen: "DP-2", inside: false }).effects, []);
  assert.strictEqual(P.reduce(pinned, { type: "closeTimer" }).state.name, "audio");
});

test("a press while closed does nothing", () => {
  assert.deepStrictEqual(P.reduce(P.initial(), { type: "press" }).state, P.initial());
});

test("a pinned panel follows hover to another icon and stays pinned", () => {
  const pinned = P.reduce(openedA, { type: "press" }).state;
  const r = P.reduce(pinned, hoverN);
  assert.strictEqual(r.state.name, "network");
  assert.strictEqual(r.state.pinned, true);
});

test("hover on another monitor moves the panel there, pinned or not", () => {
  const pinned = P.reduce(openedA, { type: "press" }).state;
  const r = P.reduce(pinned, { type: "hover", screen: "HDMI-A-1", name: "audio", anchor: B, opens: true });
  assert.strictEqual(r.state.screen, "HDMI-A-1");
  assert.strictEqual(r.state.anchor, B);
  assert.strictEqual(r.state.pinned, true);
});

test("pointer events from a monitor that does not show the panel are ignored", () => {
  const r = P.reduce(openedA, { type: "pointer", screen: "HDMI-A-1", inside: false });
  assert.deepStrictEqual(r.state, openedA);
  assert.deepStrictEqual(r.effects, []);
});

test("IPC open is pinned and uses the given anchor", () => {
  const r = P.reduce(P.initial(), { type: "open", name: "audio", screen: "DP-2", anchor: null });
  assert.strictEqual(r.state.name, "audio");
  assert.strictEqual(r.state.pinned, true);
  assert.strictEqual(r.state.anchor, null);
});

test("IPC toggle opens, toggling the same name closes, another name switches", () => {
  const t = { type: "toggle", name: "audio", screen: "DP-2", anchor: A };
  const open = P.reduce(P.initial(), t).state;
  assert.strictEqual(open.name, "audio");
  assert.strictEqual(P.reduce(open, t).state.name, "");
  const other = P.reduce(open, { type: "toggle", name: "network", screen: "DP-2", anchor: N }).state;
  assert.strictEqual(other.name, "network");
  assert.strictEqual(other.pinned, true);
});

test("close with a name only closes that panel", () => {
  assert.strictEqual(P.reduce(openedA, { type: "close", name: "network" }).state.name, "audio");
  assert.strictEqual(P.reduce(openedA, { type: "close", name: "audio" }).state.name, "");
  assert.strictEqual(P.reduce(openedA, { type: "close" }).state.name, "");
});

test("forget closes the panel opened from that anchor and drops a pending hover", () => {
  assert.strictEqual(P.reduce(openedA, { type: "forget", anchor: A }).state.name, "");
  assert.strictEqual(P.reduce(openedA, { type: "forget", anchor: N }).state.name, "audio");
  const pending = P.reduce(P.initial(), hoverA).state;
  assert.strictEqual(P.reduce(pending, { type: "forget", anchor: A }).state.pending, null);
});

test("an open delay that fires after an IPC open is dropped", () => {
  const { state } = run([hoverA, { type: "open", name: "network", screen: "DP-2", anchor: N }, { type: "openTimer" }]);
  assert.strictEqual(state.name, "network");
  assert.strictEqual(state.pending, null);
});

test("forgetScreen closes a panel shown on a monitor that went away, also without an anchor", () => {
  const ipcOpen = P.reduce(P.initial(), { type: "open", name: "notifications", screen: "HDMI-A-1", anchor: null }).state;
  assert.strictEqual(P.reduce(ipcOpen, { type: "forgetScreen", screen: "HDMI-A-1" }).state.name, "");
  assert.strictEqual(P.reduce(ipcOpen, { type: "forgetScreen", screen: "DP-2" }).state.name, "notifications");
  const pending = P.reduce(P.initial(), { type: "hover", screen: "HDMI-A-1", name: "audio", anchor: A }).state;
  assert.strictEqual(P.reduce(pending, { type: "forgetScreen", screen: "HDMI-A-1" }).state.pending, null);
});

test("hovering a click-only button while closed does nothing", () => {
  const r = P.reduce(P.initial(), passA);
  assert.deepStrictEqual(r.state, P.initial());
  assert.deepStrictEqual(r.effects, []);
});

test("a click opens the panel pinned, clicking the same button again closes it", () => {
  const open = P.reduce(P.initial(), clickA).state;
  assert.strictEqual(open.name, "audio");
  assert.strictEqual(open.anchor, A);
  assert.strictEqual(open.pinned, true);
  assert.deepStrictEqual(P.reduce(open, clickA).state, P.initial());
});

test("clicking another button switches to its panel", () => {
  const r = run([clickA, clickN]).state;
  assert.strictEqual(r.name, "network");
  assert.strictEqual(r.anchor, N);
  assert.strictEqual(r.pinned, true);
});

test("hovering a click-only button while one is pinned moves it there", () => {
  const r = run([clickA, passN]);
  assert.strictEqual(r.state.name, "network");
  assert.strictEqual(r.state.anchor, N);
  assert.strictEqual(r.state.pinned, true);
});

test("a click-only button does not take over a panel that hover opened", () => {
  const r = P.reduce(openedA, passN);
  assert.deepStrictEqual(r.state, openedA);
});

test("a hover-opening button takes over a pinned panel", () => {
  const r = run([clickN, hoverA]).state;
  assert.strictEqual(r.name, "audio");
  assert.strictEqual(r.pinned, true);
});

test("clicking a button whose panel hover opened from another button opens it there", () => {
  const r = P.reduce(openedA, { type: "click", screen: "HDMI-A-1", name: "audio", anchor: B }).state;
  assert.strictEqual(r.anchor, B);
  assert.strictEqual(r.pinned, true);
});
