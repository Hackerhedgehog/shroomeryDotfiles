const test = require("node:test");
const assert = require("node:assert");
const W = require("../WeatherData.js");

const J1 = {
  current_condition: [{ temp_C: "12", FeelsLikeC: "10", humidity: "81", windspeedKmph: "14",
    winddir16Point: "SW", weatherCode: "116", weatherDesc: [{ value: "Partly cloudy " }] }],
  nearest_area: [{ areaName: [{ value: "Oslo" }], country: [{ value: "Norway" }] }],
  weather: [
    { date: "2026-10-11", maxtempC: "14", mintempC: "6",
      astronomy: [{ sunrise: "07:45 AM", sunset: "06:22 PM" }],
      hourly: [0, 300, 600, 900, 1200, 1500, 1800, 2100].map((t, i) => ({
        time: String(t), tempC: String(6 + i), weatherCode: i === 4 ? "113" : "119", chanceofrain: String(i * 10) })) },
    { date: "2026-10-12", maxtempC: "11", mintempC: "5", astronomy: [{}],
      hourly: [{ time: "0", tempC: "5", weatherCode: "296", chanceofrain: "80" }] },
    { date: "2026-10-13", maxtempC: "9", mintempC: "2", astronomy: [{}], hourly: [] }
  ]
};

test("url encodes the location and leaves it empty for auto", () => {
  assert.strictEqual(W.url(""), "https://wttr.in/?format=j1");
  assert.strictEqual(W.url("  New York "), "https://wttr.in/New%20York?format=j1");
});

test("normalize flattens wttr.in j1", () => {
  const w = W.normalize(J1);
  assert.strictEqual(w.location, "Oslo, Norway");
  assert.strictEqual(w.tempC, 12);
  assert.strictEqual(w.feelsC, 10);
  assert.strictEqual(w.desc, "Partly cloudy");
  assert.strictEqual(w.code, 116);
  assert.strictEqual(w.humidity, 81);
  assert.strictEqual(w.windKmph, 14);
  assert.strictEqual(w.windDir, "SW");
  assert.strictEqual(w.sunrise, "07:45 AM");
  assert.strictEqual(w.hourly.length, 8);
  assert.deepStrictEqual(w.hourly[5], { time: "15:00", hour: 15, tempC: 11, code: 119, rain: 50 });
  assert.deepStrictEqual(w.days.map(d => d.weekday), ["Sun", "Mon", "Tue"]);
  assert.strictEqual(w.days[0].code, 113);     // midday hour
  assert.strictEqual(w.days[1].code, 296);     // falls back to the first hour
  assert.ok(Number.isNaN(w.days[2].code));     // no hours at all
});

test("normalize rejects garbage", () => {
  assert.strictEqual(W.normalize(null), null);
  assert.strictEqual(W.normalize({}), null);
  assert.strictEqual(W.normalize({ current_condition: [] , weather: [] }), null);
});

test("glyph maps weather codes to Nerd Font weather icons", () => {
  assert.strictEqual(W.glyph(113, false), String.fromCodePoint(0xF0599));
  assert.strictEqual(W.glyph(113, true), String.fromCodePoint(0xF0594));
  assert.strictEqual(W.glyph(116, true), String.fromCodePoint(0xF0F31));
  assert.strictEqual(W.glyph(302, false), String.fromCodePoint(0xF0596));
  assert.strictEqual(W.glyph(389, false), String.fromCodePoint(0xF067E));
  assert.strictEqual(W.glyph(338, false), String.fromCodePoint(0xF0598));
  assert.strictEqual(W.glyph(9999, false), String.fromCodePoint(0xF0590));  // unknown -> cloudy
});

test("isNight and to24h read wttr.in clock strings", () => {
  assert.strictEqual(W.isNight(6 * 60, "07:45 AM", "06:22 PM"), true);
  assert.strictEqual(W.isNight(12 * 60, "07:45 AM", "06:22 PM"), false);
  assert.strictEqual(W.isNight(19 * 60, "07:45 AM", "06:22 PM"), true);
  assert.strictEqual(W.isNight(19 * 60, "", ""), false);
  assert.strictEqual(W.to24h("06:22 PM"), "18:22");
  assert.strictEqual(W.to24h("12:05 AM"), "00:05");
});

test("isStale", () => {
  assert.strictEqual(W.isStale(0, 1000, 500), true);
  assert.strictEqual(W.isStale(800, 1000, 500), false);
  assert.strictEqual(W.isStale(100, 1000, 500), true);
});
