// TimeApp helpers: clock formats, date/time input, timezone and locale lists
// (shroomery/scripts/time.sh output) and the system locale draft. Tests in
// tests/time.test.js.

// --- clock formats (statusbar.json "clock": format, dateFormat, longDateFormat) ---

// Qt.formatDateTime patterns. Short dates go in the status bar, long dates on
// the dashboard.
var SHORT_DATE_PRESETS = ["ddd, dd MMM", "ddd d MMM", "ddd d.MM", "dd.MM.yyyy", "yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"];
var LONG_DATE_PRESETS = ["dddd, d MMMM yyyy", "dddd d. MMMM yyyy", "dddd, MMMM d, yyyy", "dddd, yyyy-MM-dd"];

function timeFormat(h24, seconds) {
    return (h24 ? "HH:mm" : "h:mm") + (seconds ? ":ss" : "") + (h24 ? "" : " AP");
}

// What a time pattern shows: 24 h unless it has AP/ap, seconds when it has s.
function parseTimeFormat(fmt) {
    var f = String(fmt || "");
    return { h24: !/a/i.test(f.replace(/'[^']*'/g, "")), seconds: /s/.test(f.replace(/'[^']*'/g, "")) };
}

// FMT without its seconds (":ss" / ".ss"), for clocks that tick per minute.
function withoutSeconds(fmt) {
    return String(fmt || "").replace(/[:.]ss?/g, "");
}

// --- date and time input ---

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// "YYYY-MM-DD" of a real date → true.
function validDate(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text || "").trim());
    if (!m)
        return false;
    var y = +m[1], mo = +m[2], d = +m[3];
    if (mo < 1 || mo > 12 || d < 1)
        return false;
    var days = [31, (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return d <= days[mo - 1];
}

// "H:MM", "HH:MM" or "HH:MM:SS" (24 h) → "HH:MM:SS", or "" when malformed.
function normalizeTime(text) {
    var m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(text || "").trim());
    if (!m)
        return "";
    var h = +m[1], mi = +m[2], s = m[3] === undefined ? 0 : +m[3];
    if (h > 23 || mi > 59 || s > 59)
        return "";
    return pad2(h) + ":" + pad2(mi) + ":" + pad2(s);
}

// The argument for time.sh set-time, or "" when either part is invalid.
function composeDateTime(date, time) {
    var t = normalizeTime(time);
    if (!validDate(date) || t === "")
        return "";
    return String(date).trim() + " " + t;
}

function dateInput(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function timeInput(d) {
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
}

// --- timezones (time.sh timezones: "ZONE<TAB>+HHMM") ---

// "+0530" → "UTC+05:30", "" → "".
function formatOffset(off) {
    var m = /^([+-])(\d{2})(\d{2})$/.exec(String(off || ""));
    return m ? "UTC" + m[1] + m[2] + ":" + m[3] : "";
}

// The local UTC offset of a Date as "+HHMM".
function offsetOf(d) {
    var m = -d.getTimezoneOffset();
    var a = Math.abs(m);
    return (m < 0 ? "-" : "+") + pad2(Math.floor(a / 60)) + pad2(a % 60);
}

function timezoneItems(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var parts = lines[i].split("\t");
        if (parts[0] === "")
            continue;
        out.push({ key: parts[0], label: parts[0].replace(/_/g, " "), detail: formatOffset(parts[1]) });
    }
    return out;
}

// --- locales (time.sh locales: "NAME<TAB>INSTALLED<TAB>LANGUAGE<TAB>TERRITORY") ---

function localeLabel(l) {
    var name = l.language ? l.language + (l.territory ? " (" + l.territory + ")" : "") : l.name;
    return name + " · " + l.name.replace(/\.UTF-8/, "");
}

function parseLocales(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var p = lines[i].split("\t");
        if (p[0] === "")
            continue;
        var l = { name: p[0], installed: p[1] === "1", language: p[2] || "", territory: p[3] || "" };
        l.label = localeLabel(l);
        out.push(l);
    }
    return out.sort(function (a, b) { return a.label.localeCompare(b.label); });
}

// Qt.locale() name for a system locale: "et_EE.UTF-8" → "et_EE".
function qtLocaleName(name) {
    return String(name || "").replace(/\..*$/, "").replace(/@.*$/, "");
}

// --- system locale draft ({ LANG: …, LC_TIME: … } as in /etc/locale.conf) ---

// The categories "Formats" sets together.
var FORMAT_VARS = ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_PAPER", "LC_MEASUREMENT"];
// Shown one by one under "Per category".
var CATEGORIES = [
    { name: "LC_TIME", label: "Dates and times" },
    { name: "LC_NUMERIC", label: "Numbers" },
    { name: "LC_MONETARY", label: "Currency" },
    { name: "LC_PAPER", label: "Paper size" },
    { name: "LC_MEASUREMENT", label: "Units" },
    { name: "LC_COLLATE", label: "Sorting" },
    { name: "LC_MESSAGES", label: "App messages" }
];

function copyDraft(d) {
    var out = {};
    for (var k in d || {})
        if (d[k])
            out[k] = d[k];
    return out;
}

// What category VAR uses: its own value, else LANG.
function effective(draft, v) {
    return (draft && draft[v]) || (draft && draft.LANG) || "";
}

// The locale every format category uses, or "" when they differ.
function formatsValue(draft) {
    var first = effective(draft, FORMAT_VARS[0]);
    for (var i = 1; i < FORMAT_VARS.length; i++)
        if (effective(draft, FORMAT_VARS[i]) !== first)
            return "";
    return first;
}

// Remove categories that just repeat LANG, so they follow it later.
function tidy(draft) {
    var out = copyDraft(draft);
    for (var k in out)
        if (k !== "LANG" && out[k] === out.LANG)
            delete out[k];
    return out;
}

function setLanguage(draft, name) {
    var out = copyDraft(draft);
    // Categories that followed the old language keep it explicitly.
    for (var i = 0; i < CATEGORIES.length; i++) {
        var v = CATEGORIES[i].name;
        if (!out[v] && out.LANG && v !== "LC_MESSAGES" && v !== "LC_COLLATE")
            out[v] = out.LANG;
    }
    out.LANG = name;
    return tidy(out);
}

function setFormats(draft, name) {
    var out = copyDraft(draft);
    for (var i = 0; i < FORMAT_VARS.length; i++)
        out[FORMAT_VARS[i]] = name;
    return tidy(out);
}

// NAME "" = follow LANG.
function setCategory(draft, v, name) {
    var out = copyDraft(draft);
    if (name)
        out[v] = name;
    else
        delete out[v];
    return tidy(out);
}

function sameDraft(a, b) {
    var x = tidy(a), y = tidy(b);
    var keys = Object.keys(x).concat(Object.keys(y));
    for (var i = 0; i < keys.length; i++)
        if (x[keys[i]] !== y[keys[i]])
            return false;
    return true;
}

// Arguments for time.sh set-locale: LANG first, the rest sorted.
function localeArgs(draft) {
    var d = tidy(draft);
    var keys = Object.keys(d).filter(function (k) { return k !== "LANG"; }).sort();
    var out = d.LANG ? ["LANG=" + d.LANG] : [];
    for (var i = 0; i < keys.length; i++)
        out.push(keys[i] + "=" + d[keys[i]]);
    return out;
}

if (typeof module !== "undefined") {
    module.exports = {
        SHORT_DATE_PRESETS: SHORT_DATE_PRESETS, LONG_DATE_PRESETS: LONG_DATE_PRESETS,
        timeFormat: timeFormat, parseTimeFormat: parseTimeFormat, withoutSeconds: withoutSeconds,
        validDate: validDate, normalizeTime: normalizeTime, composeDateTime: composeDateTime,
        dateInput: dateInput, timeInput: timeInput,
        formatOffset: formatOffset, offsetOf: offsetOf, timezoneItems: timezoneItems,
        parseLocales: parseLocales, localeLabel: localeLabel, qtLocaleName: qtLocaleName,
        FORMAT_VARS: FORMAT_VARS, CATEGORIES: CATEGORIES, effective: effective,
        formatsValue: formatsValue, tidy: tidy, setLanguage: setLanguage, setFormats: setFormats,
        setCategory: setCategory, sameDraft: sameDraft, localeArgs: localeArgs
    };
}
