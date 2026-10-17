// hypridle.conf editing for the battery panel: find the `listener { }`
// blocks (active or commented out), name what each one does, and change a
// block's timeout or comment it out ("never") while leaving the rest of the
// file as it was.
// Free of QML imports and of `.pragma library` so it loads in QML and in Node
// for the unit tests.

var HEADER = /^\s*(#\s*)?listener\s*\{/;
var CLOSE = /^\s*#?\s*\}/;
var TIMEOUT = /^(\s*#?\s*timeout\s*=\s*)(\d+)(.*)$/;
var ON_TIMEOUT = /^\s*#?\s*on-timeout\s*=\s*(.*)$/;
// A trailing "# 8min." / "# 30 min" / "# 1h" comment that restates the timeout.
var DURATION_COMMENT = /(#\s*)\d+(\.\d+)?\s*(s|sec|secs|seconds?|m|min|mins|minutes?|h|hours?)(\.?\s*)$/i;

// The choices offered for a timeout, in seconds.
var PRESETS = [60, 120, 180, 300, 480, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200];

// "8 min", "1 h 30 min", "45 s".
function formatSeconds(seconds) {
    if (seconds < 60)
        return seconds + " s";
    var minutes = Math.round(seconds / 60);
    var h = Math.floor(minutes / 60);
    var m = minutes % 60;
    if (h === 0)
        return m + " min";
    return m === 0 ? h + " h" : h + " h " + m + " min";
}

function splitComment(text) {
    var i = text.indexOf("#");
    return i < 0 ? { command: text.trim(), comment: "" }
                 : { command: text.slice(0, i).trim(), comment: text.slice(i + 1).trim() };
}

// What an on-timeout command does, in a few words.
function describe(command, comment) {
    var c = command || "";
    if (/kbd_backlight/.test(c))
        return "Keyboard backlight off";
    if (/brightnessctl/.test(c))
        return "Dim the screen";
    if (/lock-session|hyprlock/.test(c))
        return "Lock the screen";
    if (/dpms/.test(c))
        return "Turn the screen off";
    if (/suspend-then-hibernate/.test(c))
        return "Suspend, then hibernate";
    if (/hibernate/.test(c))
        return "Hibernate";
    if (/suspend/.test(c))
        return "Suspend";
    if (/poweroff|shutdown/.test(c))
        return "Power off";
    if (comment)
        return comment.charAt(0).toUpperCase() + comment.slice(1).replace(/\.$/, "");
    return c || "Listener";
}

// The listener blocks, in file order:
// { start, end (line indexes, inclusive), enabled, timeout (s), timeoutLine, command, label }
function parseListeners(text) {
    var lines = text.split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var head = lines[i].match(HEADER);
        if (!head)
            continue;
        var block = { start: i, end: -1, enabled: !head[1], timeout: 0, timeoutLine: -1, command: "", label: "" };
        var comment = "";
        for (var j = i + 1; j < lines.length; j++) {
            if (HEADER.test(lines[j]))
                break;
            if (CLOSE.test(lines[j])) {
                block.end = j;
                break;
            }
            var t = lines[j].match(TIMEOUT);
            if (t && block.timeoutLine < 0) {
                block.timeout = parseInt(t[2], 10);
                block.timeoutLine = j;
            }
            var o = lines[j].match(ON_TIMEOUT);
            if (o && block.command === "") {
                var parts = splitComment(o[1]);
                block.command = parts.command;
                comment = parts.comment;
            }
        }
        if (block.end < 0 || block.timeoutLine < 0)
            continue;
        block.label = describe(block.command, comment);
        out.push(block);
        i = block.end;
    }
    return out;
}

function commentBlock(lines, block) {
    for (var i = block.start; i <= block.end; i++)
        lines[i] = "#" + lines[i];
}

// Undo commentBlock, or a hand-commented "# listener {" block: strip the same
// marker the header used ("#" or "# ") from each line.
function uncommentBlock(lines, block) {
    var marker = lines[block.start].match(/^\s*(#\s?)/)[1];
    for (var i = block.start; i <= block.end; i++) {
        var line = lines[i];
        var at = line.search(/\S/);
        if (at < 0 || line.charAt(at) !== "#")
            continue;
        var rest = line.slice(at);
        lines[i] = line.slice(0, at) + rest.slice(rest.indexOf(marker) === 0 ? marker.length : 1);
    }
}

// The file with listener `index` set to fire after `seconds`, or commented
// out when `seconds` is 0. Returns the text unchanged for a bad index.
function setTimeoutAt(text, index, seconds) {
    var blocks = parseListeners(text);
    var block = blocks[index];
    if (!block)
        return text;
    var lines = text.split("\n");
    if (seconds <= 0) {
        if (block.enabled)
            commentBlock(lines, block);
        return lines.join("\n");
    }
    if (!block.enabled)
        uncommentBlock(lines, block);
    lines[block.timeoutLine] = lines[block.timeoutLine].replace(TIMEOUT, function (_, before, _old, after) {
        return before + seconds + after.replace(DURATION_COMMENT, "$1" + formatSeconds(seconds).replace(/ /g, "") + "$4");
    });
    return lines.join("\n");
}

// Combo choices for one listener: the presets, its own timeout when that is
// not one of them, then "Never". { labels, values, index } (value 0 = never).
function choices(block) {
    var values = PRESETS.slice();
    if (block.timeout > 0 && values.indexOf(block.timeout) < 0) {
        values.push(block.timeout);
        values.sort(function (a, b) { return a - b; });
    }
    values.push(0);
    var labels = values.map(function (v) { return v === 0 ? "Never" : formatSeconds(v); });
    var index = values.indexOf(block.enabled ? block.timeout : 0);
    return { labels: labels, values: values, index: index };
}

if (typeof module !== "undefined") {
    module.exports = {
        PRESETS: PRESETS, formatSeconds: formatSeconds, describe: describe,
        parseListeners: parseListeners, setTimeoutAt: setTimeoutAt, choices: choices
    };
}
