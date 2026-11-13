const test = require("node:test");
const assert = require("node:assert");
const S = require("../Stats.js");

const SNAPSHOT = [
  "##cpu",
  "cpu  2623268 636874 1313854 71283224 66954 0 47300 0 0 0",
  "##mem",
  "MemTotal:       16217096 kB",
  "MemFree:         3508328 kB",
  "MemAvailable:    9197684 kB",
  "SwapTotal:       8388604 kB",
  "SwapFree:        8000000 kB",
  "##net",
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "    lo: 1701728   20457    0    0    0     0          0         0  1701728   20457    0    0    0     0       0          0",
  "  eno1: 36006903067 25942320    0 7995    0     0          0      5544 964138173 9065293    0    0    0     0       0          0",
  "veth12: 500 1 0 0 0 0 0 0 700 1 0 0 0 0 0 0",
  "##temp",
  "48250",
  "##df",
  "Filesystem     1024-blocks      Used Available Capacity Mounted on",
  "/dev/nvme1n1p3   531914832 266157244 238664340      53% /",
  "/dev/nvme1n1p1     1098632    360312    738320      33% /boot/efi",
  "/dev/nvme1n1p2  1387603232 983424476 333618604      75% /home/user/Storage",
  "##uptime",
  "47965.25 712832.48",
  ""
].join("\n");

test("snapshotScript prints every section from the given dirs", () => {
  const s = S.snapshotScript({ procDir: "/proc", hwmonDir: "/sys/class/hwmon" });
  for (const sec of ["##cpu", "##mem", "##net", "##temp", "##df", "##uptime"])
    assert.ok(s.includes(sec), sec);
  assert.ok(s.includes("/proc/stat") && s.includes("/sys/class/hwmon/hwmon*"));
});

test("parseSnapshot reads every section", () => {
  const s = S.parseSnapshot(SNAPSHOT);
  assert.deepStrictEqual(s.cpu, { idle: 71283224 + 66954, total: 2623268 + 636874 + 1313854 + 71283224 + 66954 + 0 + 47300 + 0 });
  assert.deepStrictEqual(s.mem, { totalKb: 16217096, availableKb: 9197684, swapTotalKb: 8388604, swapFreeKb: 8000000 });
  assert.deepStrictEqual(s.net, { rx: 36006903067, tx: 964138173 });
  assert.strictEqual(s.tempC, 48.25);
  assert.deepStrictEqual(s.disks.map(d => d.mount), ["/", "/home/user/Storage"]);
  assert.strictEqual(Math.round(s.disks[0].percent), 50);
  assert.strictEqual(s.uptime, 47965.25);
});

test("parseSnapshot tolerates missing sections", () => {
  const s = S.parseSnapshot("##cpu\ncpu 1 2 3 4\n");
  assert.ok(s.cpu);
  assert.strictEqual(s.mem, null);
  assert.strictEqual(s.net, null);
  assert.ok(Number.isNaN(s.tempC));
  assert.strictEqual(s.disks, null);
  assert.strictEqual(s.uptime, 0);
});

test("cpuPercent is the busy share between two samples", () => {
  assert.strictEqual(S.cpuPercent({ idle: 100, total: 200 }, { idle: 150, total: 400 }), 75);
  assert.strictEqual(S.cpuPercent({ idle: 100, total: 200 }, { idle: 100, total: 200 }), 0);
});

test("parseMeminfo falls back to MemFree without MemAvailable", () => {
  assert.strictEqual(S.parseMeminfo("MemTotal: 100 kB\nMemFree: 40 kB").availableKb, 40);
  assert.strictEqual(S.parseMeminfo("nothing"), null);
});

test("rate is bytes per second and never negative", () => {
  assert.strictEqual(S.rate(1000, 3000, 2), 1000);
  assert.strictEqual(S.rate(3000, 1000, 2), 0);   // counter reset
  assert.strictEqual(S.rate(1000, 3000, 0), 0);
});

test("parseNvidia reads the csv line", () => {
  assert.deepStrictEqual(S.parseNvidia("37, 1024, 8192, 55\n"), { util: 37, memUsedMb: 1024, memTotalMb: 8192, tempC: 55 });
  assert.strictEqual(S.parseNvidia("No devices were found"), null);
  assert.strictEqual(S.parseNvidia(""), null);
});

test("formatBytes picks a unit", () => {
  assert.strictEqual(S.formatBytes(0), "0 B");
  assert.strictEqual(S.formatBytes(1536), "1.5 KB");
  assert.strictEqual(S.formatBytes(5 * 1024 * 1024 * 1024), "5.0 GB");
  assert.strictEqual(S.formatBytes(150 * 1024 * 1024), "150 MB");
  assert.strictEqual(S.formatRate(2048), "2.0 KB/s");
});

test("formatUptime", () => {
  assert.strictEqual(S.formatUptime(47965), "13h 19m");
  assert.strictEqual(S.formatUptime(59), "0m");
  assert.strictEqual(S.formatUptime(2 * 86400 + 4 * 3600 + 5), "2d 4h");
});

test("formatClock for media positions", () => {
  assert.strictEqual(S.formatClock(0), "0:00");
  assert.strictEqual(S.formatClock(83.9), "1:23");
  assert.strictEqual(S.formatClock(3725), "1:02:05");
  assert.strictEqual(S.formatClock(NaN), "0:00");
});
