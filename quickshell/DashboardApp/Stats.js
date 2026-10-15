//
// Parsers and formatters for the dashboard's system stats (SystemStats.qml).
// Free of QML imports and `.pragma library` so Node can load it for the unit
// tests. SystemStats runs snapshotScript() every 2 s and feeds its output to
// parseSnapshot().

// One shell script printing every source behind a "##name" marker line.
function snapshotScript(p) {
    return [
        "echo '##cpu'; head -n1 " + p.procDir + "/stat",
        "echo '##mem'; cat " + p.procDir + "/meminfo",
        "echo '##net'; cat " + p.procDir + "/net/dev",
        "echo '##temp'; for h in " + p.hwmonDir + "/hwmon*; do case \"$(cat \"$h/name\" 2>/dev/null)\" in"
            + " k10temp|coretemp|zenpower) cat \"$h/temp1_input\"; break;; esac; done",
        "echo '##df'; df -P -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs 2>/dev/null",
        "echo '##uptime'; cat " + p.procDir + "/uptime"
    ].join("; ");
}

function sections(text) {
    var out = {};
    var cur = null;
    String(text).split("\n").forEach(function (line) {
        if (line.indexOf("##") === 0) {
            cur = line.slice(2).trim();
            out[cur] = [];
        } else if (cur !== null) {
            out[cur].push(line);
        }
    });
    return out;
}

// The aggregate "cpu" line of /proc/stat -> { idle, total } jiffies.
function parseCpu(line) {
    var f = String(line).trim().split(/\s+/);
    if (f[0] !== "cpu")
        return null;
    var v = f.slice(1).map(Number);
    // user nice system idle iowait irq softirq steal (guest is counted in user)
    var total = 0;
    for (var i = 0; i < Math.min(v.length, 8); i++)
        total += v[i] || 0;
    return { idle: (v[3] || 0) + (v[4] || 0), total: total };
}

function cpuPercent(prev, cur) {
    var dt = cur.total - prev.total;
    var di = cur.idle - prev.idle;
    if (dt <= 0)
        return 0;
    return Math.max(0, Math.min(100, (1 - di / dt) * 100));
}

function parseMeminfo(text) {
    var m = {};
    String(text).split("\n").forEach(function (l) {
        var r = /^(\w+):\s+(\d+)/.exec(l);
        if (r)
            m[r[1]] = Number(r[2]);
    });
    if (!m.MemTotal)
        return null;
    return {
        totalKb: m.MemTotal,
        availableKb: m.MemAvailable !== undefined ? m.MemAvailable : (m.MemFree || 0),
        swapTotalKb: m.SwapTotal || 0,
        swapFreeKb: m.SwapFree || 0
    };
}

var VIRTUAL_IFACE = /^(lo|veth|docker|br-|virbr)/;

// Total received/transmitted bytes of the physical interfaces.
function parseNetDev(text) {
    var rx = 0, tx = 0, found = false;
    String(text).split("\n").forEach(function (l) {
        var r = /^\s*([^:\s]+):\s*(.*)$/.exec(l);
        if (!r || VIRTUAL_IFACE.test(r[1]))
            return;
        var f = r[2].trim().split(/\s+/).map(Number);
        if (f.length < 9)
            return;
        rx += f[0];
        tx += f[8];
        found = true;
    });
    return found ? { rx: rx, tx: tx } : null;
}

function rate(prev, cur, seconds) {
    if (!(seconds > 0) || cur < prev)
        return 0;
    return (cur - prev) / seconds;
}

// `df -P` output -> real filesystems, /boot* left out.
function parseDf(text) {
    var out = [];
    String(text).split("\n").slice(1).forEach(function (l) {
        var f = l.trim().split(/\s+/);
        if (f.length < 6)
            return;
        var mount = f.slice(5).join(" ");
        if (mount.indexOf("/boot") === 0)
            return;
        var size = Number(f[1]), used = Number(f[2]);
        if (!(size > 0))
            return;
        out.push({ mount: mount, sizeKb: size, usedKb: used, percent: used / size * 100 });
    });
    return out;
}

function parseSnapshot(text) {
    var s = sections(text);
    var temp = s.temp ? parseInt(s.temp.join("").trim(), 10) : NaN;
    var up = s.uptime ? parseFloat(s.uptime[0]) : NaN;
    return {
        cpu: s.cpu ? parseCpu(s.cpu[0] || "") : null,
        mem: s.mem ? parseMeminfo(s.mem.join("\n")) : null,
        net: s.net ? parseNetDev(s.net.join("\n")) : null,
        tempC: isNaN(temp) ? NaN : temp / 1000,
        disks: s.df ? parseDf(s.df.join("\n")) : null,
        uptime: isNaN(up) ? 0 : up
    };
}

// `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu
//  --format=csv,noheader,nounits` -> { util, memUsedMb, memTotalMb, tempC }.
function parseNvidia(text) {
    var line = String(text).trim().split("\n")[0] || "";
    var f = line.split(",").map(function (x) { return x.trim() === "" ? NaN : Number(x.trim()); });
    if (f.length < 4 || f.slice(0, 4).some(isNaN))
        return null;
    return { util: f[0], memUsedMb: f[1], memTotalMb: f[2], tempC: f[3] };
}

function formatBytes(bytes) {
    var units = ["B", "KB", "MB", "GB", "TB"];
    var v = Math.max(0, bytes || 0), i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (i === 0 || v >= 100 ? String(Math.round(v)) : v.toFixed(1)) + " " + units[i];
}

function formatRate(bytesPerSecond) {
    return formatBytes(bytesPerSecond) + "/s";
}

function formatUptime(seconds) {
    var m = Math.floor(Math.max(0, seconds) / 60);
    var d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), mm = m % 60;
    if (d > 0)
        return d + "d " + h + "h";
    if (h > 0)
        return h + "h " + mm + "m";
    return mm + "m";
}

function pad2(v) {
    return (v < 10 ? "0" : "") + v;
}

// Seconds -> "m:ss" or "h:mm:ss" (media positions).
function formatClock(seconds) {
    if (!(seconds >= 0) || !isFinite(seconds))
        return "0:00";
    var s = Math.floor(seconds), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    return h > 0 ? h + ":" + pad2(m) + ":" + pad2(ss) : m + ":" + pad2(ss);
}

if (typeof module !== "undefined") {
    module.exports = {
        snapshotScript: snapshotScript, parseSnapshot: parseSnapshot, parseCpu: parseCpu,
        cpuPercent: cpuPercent, parseMeminfo: parseMeminfo, parseNetDev: parseNetDev, rate: rate,
        parseDf: parseDf, parseNvidia: parseNvidia, formatBytes: formatBytes, formatRate: formatRate,
        formatUptime: formatUptime, formatClock: formatClock
    };
}
