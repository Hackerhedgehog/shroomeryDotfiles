// Safe system update (shroomery/scripts/pkg-update.sh): pure helpers shared by
// UpdateState.qml and tests/update.test.js. The JSON shapes are the CLI's:
//   check  → {updates:[{name,old,new,held}], count, held_count, refreshed}
//   status → {known_good: null|{created,kernel,forced,source,verified},
//             pending: null|{state,started,changed}, discarded: null|{state,started,changed}, matches}
//   (`discarded` is the record `discard` keeps until the next promote; `changed` = packages the update
//   moved to another version; a record that exists but cannot be read is {state: "unknown"}.)

var KEEP = { min: 1, max: 20, fallback: 3 };
var LOG_LINES = 500;

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function emptyCheck(error) {
    return { updates: [], held: [], count: 0, heldCount: 0, error: error };
}

function countOr(value, fallback) {
    return typeof value === "number" && isFinite(value) && value >= 0 ? Math.floor(value) : fallback;
}

// The output of `pkg-update.sh check`. `updates` holds the packages that will be
// updated, `held` the ones IgnorePkg/IgnoreGroup keep back. Never throws: bad
// input gives empty lists and a message in `error`.
function parseCheck(raw) {
    if (typeof raw !== "string" || raw.trim() === "")
        return emptyCheck("no output from the update check");
    var data;
    try {
        data = JSON.parse(raw);
    } catch (e) {
        return emptyCheck("unreadable update check: " + e.message);
    }
    if (!isObject(data) || !Array.isArray(data.updates))
        return emptyCheck("unexpected update check output");
    var updates = [];
    var held = [];
    for (var i = 0; i < data.updates.length; i++) {
        var u = data.updates[i];
        if (!isObject(u))
            continue;
        (u.held === true ? held : updates).push(u);
    }
    return {
        updates: updates,
        held: held,
        count: countOr(data.count, updates.length),
        heldCount: countOr(data.held_count, held.length),
        error: null
    };
}

// 1000-based like pacman and `df -H`: 0 → "0 B", 6.9e9 → "6.9 GB".
function formatBytes(n) {
    var v = typeof n === "string" && n.trim() !== "" ? Number(n) : n;
    if (typeof v !== "number" || !isFinite(v) || v <= 0)
        return "0 B";
    if (v < 1000)
        return Math.floor(v) + " B";
    var units = ["kB", "MB", "GB", "TB"];
    var i = -1;
    do {
        v /= 1000;
        i++;
    } while (v >= 999.95 && i < units.length - 1);
    return v.toFixed(1) + " " + units[i];
}

// A failed update record (pending or discarded) that had already moved packages to
// new versions: the system is half updated (do not reboot; restore or finish it).
function partlyChanged(record) {
    return isObject(record) && record.state === "failed"
        && typeof record.changed === "number" && record.changed > 0;
}

// The state chip of the Update tab from the parsed `status` JSON (null when
// `status` failed). In this order: a running / failed / unverified update; no
// known-good; an update that was discarded (installed, never verified) while the
// installed protected set is not the recovery point; then the known-good: matching
// and verified, matching but never verified (apply's checkpoint), or not matching.
function stateChip(status) {
    if (!isObject(status))
        return { text: "status unknown", tone: "error" };
    var pending = isObject(status.pending) ? status.pending : null;
    if (pending) {
        if (pending.state === "running")
            return { text: "update running", tone: "busy" };
        if (pending.state === "failed")
            return partlyChanged(pending) ? { text: "update failed, packages partly changed", tone: "error" }
                                          : { text: "update failed", tone: "error" };
        if (pending.state === "awaiting-verification")
            return { text: "awaiting verification", tone: "busy" };
        return { text: "update state unknown", tone: "error" };
    }
    var kg = isObject(status.known_good) ? status.known_good : null;
    if (!kg)
        return { text: "no recovery point", tone: "error" };
    if (isObject(status.discarded) && status.matches !== true)
        return { text: "update discarded, not verified", tone: "busy" };
    var forced = kg.forced === true ? " (forced)" : "";
    if (status.matches === true) {
        if (kg.verified === false && kg.forced !== true)
            return { text: "recovery point not verified", tone: "normal" };
        return { text: "protected (known-good)" + forced, tone: "good" };
    }
    return { text: "not made through the safe flow" + forced, tone: "normal" };
}

// Identity of the pending record in the `status` JSON: "" when there is none (or
// status failed), else state and start time. A change means a different update.
function pendingKey(status) {
    if (!isObject(status) || !isObject(status.pending))
        return "";
    return String(status.pending.state) + "|" + String(status.pending.started);
}

// The date part of a record's ISO time ("2026-10-17T10:00:00Z" -> "2026-10-17"); "" when absent.
function dayOf(iso) {
    if (typeof iso !== "string")
        return "";
    var m = /^\d{4}-\d{2}-\d{2}/.exec(iso);
    return m ? m[0] : iso.trim();
}

// `checksDone` = checks already made since boot (UpdateState counts them per qs
// session, which stands in for "since boot"). The first check of a session uses
// the cached sync data; every later one re-downloads the databases.
function shouldRefresh(checksDone) {
    return typeof checksDone === "number" && checksDone >= 1;
}

// Versions to keep in the package cache: an integer 1–20 (numeric strings too);
// anything else is the default 3, like settings_cache_keep in pkg-lib.sh.
function clampKeep(v) {
    if (typeof v !== "number" && typeof v !== "string")
        return KEEP.fallback;
    var s = String(v).trim();
    if (!/^\d+$/.test(s))
        return KEEP.fallback;
    var n = parseInt(s, 10);
    return n >= KEEP.min && n <= KEEP.max ? n : KEEP.fallback;
}

// The last `max` lines of the live log.
function trimLog(lines, max) {
    var limit = max === undefined ? LOG_LINES : max;
    return lines.length > limit ? lines.slice(lines.length - limit) : lines;
}

// A log line without terminal colors ([INFO] etc. are colored for the terminal)
// and without a trailing carriage return.
function cleanLine(line) {
    return String(line).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\r+$/, "");
}

// One line for the end of a mutating command's log; "" on success.
function exitMessage(code) {
    if (code === 0)
        return "";
    if (code === 3)
        return "Another update operation is already running.";
    if (code === 4)
        return "An earlier update is not promoted yet: verify and promote it, or discard it.";
    if (code === 126 || code === 127)
        return "Authentication was cancelled or not authorised.";
    if (code === 2)
        return "The command was refused as malformed (exit 2).";
    return "The command failed (exit " + code + ").";
}

if (typeof module !== "undefined") {
    module.exports = {
        KEEP: KEEP, LOG_LINES: LOG_LINES,
        parseCheck: parseCheck, formatBytes: formatBytes, stateChip: stateChip, partlyChanged: partlyChanged,
        pendingKey: pendingKey, dayOf: dayOf,
        shouldRefresh: shouldRefresh, clampKeep: clampKeep, trimLog: trimLog,
        exitMessage: exitMessage, cleanLine: cleanLine
    };
}
