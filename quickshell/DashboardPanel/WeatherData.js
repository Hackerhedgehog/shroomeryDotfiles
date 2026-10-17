//
// wttr.in (?format=j1) parsing for the dashboard (Weather.qml). Free of QML
// imports and `.pragma library` so Node can load it for the unit tests.

function url(location) {
    return "https://wttr.in/" + encodeURIComponent(String(location || "").trim()) + "?format=j1";
}

function pad2(v) {
    return (v < 10 ? "0" : "") + v;
}

function firstValue(list) {
    return list && list[0] && list[0].value ? String(list[0].value).trim() : "";
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function weekday(iso) {
    var p = String(iso).split("-").map(Number);
    if (p.length !== 3 || p.some(isNaN))
        return "";
    return WEEKDAYS[new Date(p[0], p[1] - 1, p[2]).getDay()];
}

function normalize(j1) {
    if (!j1 || !j1.current_condition || !j1.current_condition[0] || !j1.weather || !j1.weather.length)
        return null;
    var c = j1.current_condition[0];
    var area = j1.nearest_area && j1.nearest_area[0];
    var today = j1.weather[0];
    var astro = (today.astronomy && today.astronomy[0]) || {};
    return {
        location: area ? [firstValue(area.areaName), firstValue(area.country)].filter(Boolean).join(", ") : "",
        tempC: Number(c.temp_C),
        feelsC: Number(c.FeelsLikeC),
        code: Number(c.weatherCode),
        desc: firstValue(c.weatherDesc),
        humidity: Number(c.humidity),
        windKmph: Number(c.windspeedKmph),
        windDir: c.winddir16Point || "",
        sunrise: astro.sunrise || "",
        sunset: astro.sunset || "",
        hourly: (today.hourly || []).map(function (h) {
            var hour = Math.floor(Number(h.time) / 100);
            return { time: pad2(hour) + ":00", hour: hour, tempC: Number(h.tempC),
                     code: Number(h.weatherCode), rain: Number(h.chanceofrain) };
        }),
        days: j1.weather.slice(0, 3).map(function (d) {
            var hours = d.hourly || [];
            var mid = hours[4] || hours[0] || {};
            return { date: d.date, weekday: weekday(d.date), maxC: Number(d.maxtempC),
                     minC: Number(d.mintempC), code: Number(mid.weatherCode) };
        })
    };
}

// Nerd Font Material Design weather glyphs (verified against glyphnames.json).
var CP = {
    sun: 0xF0599, night: 0xF0594, partly: 0xF0595, partlyNight: 0xF0F31, cloudy: 0xF0590,
    fog: 0xF0591, rain: 0xF0597, pouring: 0xF0596, snow: 0xF0598, sleet: 0xF067F, thunder: 0xF067E
};

// wttr.in / WWO weather codes by kind.
var KIND = {};
function assign(kind, codes) {
    codes.forEach(function (c) { KIND[c] = kind; });
}
assign("clear", [113]);
assign("partly", [116]);
assign("cloudy", [119, 122]);
assign("fog", [143, 248, 260]);
assign("rain", [176, 263, 266, 293, 296, 353]);
assign("pouring", [299, 302, 305, 308, 356, 359]);
assign("sleet", [179, 182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377]);
assign("snow", [227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 392, 395]);
assign("thunder", [200, 386, 389]);

function glyph(code, night) {
    var k = KIND[Number(code)] || "cloudy";
    if (k === "clear")
        return String.fromCodePoint(night ? CP.night : CP.sun);
    if (k === "partly")
        return String.fromCodePoint(night ? CP.partlyNight : CP.partly);
    return String.fromCodePoint(CP[k]);
}

// "07:12 AM" -> minutes since midnight, -1 when unreadable.
function clockMinutes(s) {
    var r = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec(String(s || "").trim());
    if (!r)
        return -1;
    var h = Number(r[1]) % 12;
    if (r[3].toUpperCase() === "PM")
        h += 12;
    return h * 60 + Number(r[2]);
}

function isNight(nowMinutes, sunrise, sunset) {
    var up = clockMinutes(sunrise), down = clockMinutes(sunset);
    if (up < 0 || down < 0)
        return false;
    return nowMinutes < up || nowMinutes >= down;
}

function to24h(s) {
    var m = clockMinutes(s);
    if (m < 0)
        return String(s || "");
    return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60);
}

function isStale(fetchedAt, now, maxAgeMs) {
    return !(fetchedAt > 0) || now - fetchedAt > maxAgeMs;
}

if (typeof module !== "undefined") {
    module.exports = { url: url, normalize: normalize, glyph: glyph, isNight: isNight,
                       to24h: to24h, isStale: isStale };
}
