const test = require("node:test");
const assert = require("node:assert");
const L = require("../Loudness.js");

test("dbToLinear and linearToDb round-trip", () => {
  for (const db of [-60, -28, -20, -1, 0, 8]) {
    assert.ok(Math.abs(L.linearToDb(L.dbToLinear(db)) - db) < 1e-9);
  }
});

test("dbToLinear matches known values", () => {
  assert.ok(Math.abs(L.dbToLinear(-28) - 0.0398107) < 1e-6);
  assert.ok(Math.abs(L.dbToLinear(8) - 2.5118864) < 1e-6);
  assert.ok(Math.abs(L.dbToLinear(-1) - 0.8912509) < 1e-6);
});

test("linearToDb floors at 1e-6 instead of returning -Infinity", () => {
  assert.ok(Number.isFinite(L.linearToDb(0)));
  assert.ok(L.linearToDb(0) <= -120);
});

test("clampDb holds each parameter inside its range", () => {
  assert.strictEqual(L.clampDb("threshold", -999), -60);
  assert.strictEqual(L.clampDb("threshold", 999), 0);
  assert.strictEqual(L.clampDb("ratio", 0.1), 1);
  assert.strictEqual(L.clampDb("ratio", 100), 20);
  assert.strictEqual(L.clampDb("attack", 0), 0.1);
  assert.strictEqual(L.clampDb("release", 5), 10);
  assert.strictEqual(L.clampDb("makeup", -5), 0);
  assert.strictEqual(L.clampDb("ceiling", -50), -12);
});

test("toNative converts to the plugin's own units", () => {
  assert.ok(Math.abs(L.toNative("threshold", -28) - 0.0398107) < 1e-6);
  assert.ok(Math.abs(L.toNative("makeup", 8) - 2.5118864) < 1e-6);
  assert.ok(Math.abs(L.toNative("ceiling", -1) - 0.8912509) < 1e-6);
  assert.strictEqual(L.toNative("ratio", 4), 4);
  assert.strictEqual(L.toNative("attack", 8), 8);
  assert.strictEqual(L.toNative("release", 200), 200);
});

test("toNative respects the plugin's strict linear bounds", () => {
  // -60 dB is 0.001, exactly comp:al's minimum; nothing may go below it.
  assert.ok(L.toNative("threshold", -60) >= 0.001);
  assert.ok(L.toNative("ceiling", -12) >= 0.003981);
});

test("presets carry all six keys within range", () => {
  for (const name of L.PRESET_ORDER) {
    const p = L.PRESETS[name];
    for (const key of L.PARAM_KEYS) {
      assert.ok(typeof p[key] === "number", `${name}.${key} missing`);
      assert.strictEqual(L.clampDb(key, p[key]), p[key], `${name}.${key} out of range`);
    }
  }
});

test("reset preset is a genuine pass-through", () => {
  assert.strictEqual(L.PRESETS.reset.ratio, 1.0);
  assert.strictEqual(L.PRESETS.reset.makeup, 0);
  assert.strictEqual(L.PRESETS.reset.ceiling, 0);
});

test("gainComputer is identity below the knee", () => {
  assert.strictEqual(L.gainComputer(-45, -28, 4), -45);
  assert.strictEqual(L.gainComputer(-35, -28, 4), -35);
});

test("gainComputer applies the ratio above the knee", () => {
  // -28 + (-20 + 28)/4
  assert.ok(Math.abs(L.gainComputer(-20, -28, 4) - -26) < 1e-9);
  assert.ok(Math.abs(L.gainComputer(-3, -28, 4) - -21.75) < 1e-9);
});

test("gainComputer is continuous at both knee boundaries", () => {
  // knee spans -34 .. -22 for threshold -28
  assert.ok(Math.abs(L.gainComputer(-34, -28, 4) - -34) < 1e-9);
  assert.ok(Math.abs(L.gainComputer(-22, -28, 4) - -26.5) < 1e-9);
});

test("gainComputer is monotonic and never boosts", () => {
  let prev = -Infinity;
  for (let x = -60; x <= 0; x += 0.25) {
    const y = L.gainComputer(x, -28, 4);
    assert.ok(y >= prev - 1e-9, `not monotonic at ${x}`);
    assert.ok(y <= x + 1e-9, `boosted at ${x}`);
    prev = y;
  }
});

test("ratio 1:1 reduces nothing anywhere", () => {
  for (let x = -60; x <= 0; x += 5) {
    assert.ok(Math.abs(L.gainReduction(x, -20, 1)) < 1e-9);
  }
});

test("gainReduction is never negative", () => {
  for (let x = -60; x <= 0; x += 0.5) {
    assert.ok(L.gainReduction(x, -28, 4) >= -1e-9);
  }
});

test("suggestedMakeup is the reduction at the -20 dBFS reference", () => {
  const m = L.PRESETS.movies;
  assert.strictEqual(L.suggestedMakeup(m.threshold, m.ratio), 6.0);
  assert.strictEqual(L.suggestedMakeup(-20, 1), 0.0);
});

test("suggestedMakeup stays inside the makeup range", () => {
  const v = L.suggestedMakeup(-60, 20);
  assert.ok(v >= 0 && v <= 24);
});

test("limiterOnsetDb reports null when the limiter never engages", () => {
  const m = L.PRESETS.movies;
  // -28 + (0+28)/4 + 8 = -13 dB at full-scale input: never reaches -1.
  assert.strictEqual(L.limiterOnsetDb(m.threshold, m.ratio, m.makeup, m.ceiling), null);
});

test("limiterOnsetDb finds the onset when the limiter does engage", () => {
  // threshold -40, ratio 2, makeup 20, ceiling -1. Chosen so the onset sits
  // well above the knee (which spans -46..-34), where the transfer curve is
  // the plain -40 + (x+40)/2 line:
  //   -40 + (x+40)/2 + 20 = -1  ->  x = -2
  // The sweep steps 0.05 from -60, so allow one step of slack.
  const x = L.limiterOnsetDb(-40, 2, 20, -1);
  assert.ok(x !== null, "expected an onset");
  assert.ok(Math.abs(x - -2) < 0.06, `expected about -2, got ${x}`);
});

test("matchPreset identifies an exact preset and otherwise reports custom", () => {
  assert.strictEqual(L.matchPreset(L.PRESETS.gaming), "gaming");
  const tweaked = Object.assign({}, L.PRESETS.gaming, { ratio: 3.3 });
  assert.strictEqual(L.matchPreset(tweaked), "custom");
});

test("renderConf embeds both plugins, the link and the target sink", () => {
  const conf = L.renderConf(L.PRESETS.movies, "alsa_output.test");
  assert.ok(conf.includes(L.COMPRESSOR_URI));
  assert.ok(conf.includes(L.LIMITER_URI));
  assert.ok(conf.includes('output = "comp:out_l" input = "lim:in_l"'));
  assert.ok(conf.includes('output = "comp:out_r" input = "lim:in_r"'));
  assert.ok(conf.includes('target.object = "alsa_output.test"'));
  assert.ok(conf.includes('node.name   = "dynamic_loudness"'));
  assert.ok(conf.includes("media.class = Audio/Sink"));
});

test("renderConf writes the required limiter settings", () => {
  const conf = L.renderConf(L.PRESETS.movies, "sink");
  assert.ok(/"alr"\s*=\s*0/.test(conf), "alr must be disabled");
  assert.ok(/"boost"\s*=\s*0/.test(conf), "boost must be disabled");
});

test("renderConf writes native units, not dB", () => {
  const conf = L.renderConf(L.PRESETS.movies, "sink");
  assert.ok(/"al"\s*=\s*0\.0398/.test(conf), "threshold must be linear");
  assert.ok(/"mk"\s*=\s*2\.5118/.test(conf), "makeup must be linear");
  assert.ok(/"th"\s*=\s*0\.8912/.test(conf), "ceiling must be linear");
  assert.ok(/"at"\s*=\s*8/.test(conf), "attack stays in ms");
});

test("renderConf escapes a sink name containing a quote", () => {
  const conf = L.renderConf(L.PRESETS.reset, 'we"ird');
  assert.ok(conf.includes('target.object = "we\\"ird"'));
});

test("setParamsArgs builds one pw-cli command carrying every parameter", () => {
  const args = L.setParamsArgs(81, L.PRESETS.movies);
  assert.deepStrictEqual(args.slice(0, 4), ["pw-cli", "s", "81", "Props"]);
  const pod = args[4];
  for (const key of L.PARAM_KEYS)
    assert.ok(pod.includes(L.PARAMS[key].control), `${key} control missing from pod`);
  assert.ok(/^\{ params = \[ /.test(pod));
  assert.ok(/ \] \}$/.test(pod));
});

test("setParamsArgs writes native units into the pod", () => {
  const pod = L.setParamsArgs(1, L.PRESETS.movies)[4];
  assert.ok(/"comp:al" 0\.0398/.test(pod));
  assert.ok(/"comp:mk" 2\.5118/.test(pod));
  assert.ok(/"lim:th" 0\.8912/.test(pod));
  assert.ok(/"comp:at" 8/.test(pod));
});

test("parseSinkInputIndex finds the chain's playback stream", () => {
  const json = JSON.stringify([
    { index: 12, sink: 3, properties: { "node.name": "some.app" } },
    { index: 89, sink: 61, properties: { "node.name": "output.dynamic_loudness" } }
  ]);
  assert.strictEqual(L.parseSinkInputIndex(json, "output.dynamic_loudness"), 89);
  assert.strictEqual(L.parseSinkInputIndex(json, "absent"), null);
  assert.strictEqual(L.parseSinkInputIndex("not json", "x"), null);
});

test("parseNodeId finds the sink node by name", () => {
  const dump = JSON.stringify([
    { id: 12, info: { props: { "node.name": "something.else" } } },
    { id: 81, info: { props: { "node.name": "dynamic_loudness", "media.class": "Audio/Sink" } } }
  ]);
  assert.strictEqual(L.parseNodeId(dump, "dynamic_loudness"), 81);
});

test("parseNodeId returns null for absent node or unparseable input", () => {
  assert.strictEqual(L.parseNodeId("[]", "dynamic_loudness"), null);
  assert.strictEqual(L.parseNodeId("not json", "dynamic_loudness"), null);
});
