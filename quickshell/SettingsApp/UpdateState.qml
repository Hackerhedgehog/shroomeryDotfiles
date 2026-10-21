pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "UpdateLogic.js" as Logic

// Safe system update, driven through shroomery/scripts/pkg-update.sh
// (Paths.pkgUpdate). Read-only calls (status, check, verify, cache size) run as
// the user. The mutating subcommands (apply, promote, discard, fetch-missing,
// cache keep|clear) re-execute themselves through pkexec, so the polkit prompt
// appears when one starts; they print `LOG=<path>` first and everything else
// also goes to that log, which is followed into `log` while `running`.
// Only one mutating command runs at a time: while `running` they return false.
Singleton {
    id: root

    // Parsed `pkg-update.sh status` JSON, or null while unknown / when status failed.
    property var status: null
    // {text, tone} for a StatusChip (UpdateLogic.stateChip).
    readonly property var chip: Logic.stateChip(status)

    // Last check: packages that will be updated, packages IgnorePkg/IgnoreGroup hold back.
    property var updates: []
    property var held: []
    property int count: 0
    property int heldCount: 0
    property string checkError: ""
    property bool checking: false
    // Checks that succeeded in this qs session. "Since boot" is approximated by the
    // session (this singleton lives as long as qs): from the second check on, the
    // sync databases are re-downloaded (--refresh).
    property int checkCount: 0

    // A mutating command is running (from start until its log is fully read).
    property bool running: false
    // What runs / ran last: apply, promote, discard, fetch-missing, cache-keep, cache-clear.
    property string runKind: ""
    // Exit code of the last mutating command, -1 while running or before the first.
    property int exitCode: -1
    // Live output (last ~500 lines) of the running or last mutating command.
    property string log: ""

    // `verify` result lines (`PASS|FAIL|WARN|SKIP <check>[: detail]`).
    property bool verifying: false
    property var verifyLines: []
    property bool verifyFailed: false

    // Bytes in the pacman package cache; versions per package `paccache` keeps.
    property real cacheBytes: 0
    property int keep: Logic.KEEP.fallback

    // Set by SettingsWindow: true while the window is open. Gates polling.
    property bool panelOpen: false

    // --- internals ---
    // Identity of the pending record the verify lines belong to ("" = none).
    property string pendingKey: ""
    property var lines: []
    property string logPath: ""
    property bool outDone: false
    property bool errDone: false
    property bool checkExited: false
    property int checkExit: 0
    property string checkOut: ""
    property string checkErr: ""

    function refreshStatus(): void {
        statusReader.running = false;
        statusReader.running = true;
    }

    function refreshCache(): void {
        cacheReader.running = false;
        cacheReader.running = true;
    }

    // Fetch the update list. `system` also lists what IgnorePkg/IgnoreGroup hold back
    // as updatable (--system). Returns false when a check already runs.
    function check(system): bool {
        return startCheck(system === true, Logic.shouldRefresh(checkCount));
    }

    function startCheck(system: bool, refresh: bool): bool {
        if (checking)
            return false;
        checking = true;
        checkError = "";
        outDone = false;
        errDone = false;
        checkExited = false;
        checkOut = "";
        checkErr = "";
        let cmd = [Paths.pkgUpdate, "check"];
        if (refresh)
            cmd.push("--refresh");
        if (system)
            cmd.push("--system");
        checker.command = cmd;
        checker.running = true;
        return true;
    }

    function finishCheck(): void {
        if (!(outDone && errDone && checkExited))
            return;
        const r = Logic.parseCheck(checkOut);
        let error = r.error === null ? "" : r.error;
        if (checkExit !== 0) {
            const msg = Logic.cleanLine(checkErr).trim();
            error = msg !== "" ? msg : "the update check failed (exit " + checkExit + ")";
        }
        const ok = error === "";
        updates = ok ? r.updates : [];
        held = ok ? r.held : [];
        count = ok ? r.count : 0;
        heldCount = ok ? r.heldCount : 0;
        checkError = error;
        if (ok)
            checkCount++;
        checking = false;
    }

    // Run the post-update checks as the user. Changes nothing.
    function verifyNow(): bool {
        if (verifying)
            return false;
        verifying = true;
        verifyFailed = false;
        verifyLines = [];
        verifier.running = true;
        return true;
    }

    // --- mutating commands (pkexec); false when one already runs ---

    // Update with the held-back packages left alone (system: false) or included.
    // `force` overrides the stop on an unpromoted earlier update.
    function update(system, force): bool {
        let args = ["apply"];
        if (system === true)
            args.push("--system");
        if (force === true)
            args.push("--force");
        args.push("--yes");
        return run(args, "apply");
    }

    // Make the installed state the new known-good (the CLI runs verify first;
    // `force` promotes despite failed checks).
    function promote(force): bool {
        return run(force === true ? ["promote", "--force", "--yes"] : ["promote", "--yes"], "promote");
    }

    function discard(): bool {
        return run(["discard"], "discard");
    }

    // Download the protected packages' archives the cache lacks.
    function fetchMissing(): bool {
        return run(["fetch-missing", "--yes"], "fetch-missing");
    }

    function cacheKeepNow(): bool {
        return run(["cache", "keep", String(keep)], "cache-keep");
    }

    function cacheClear(): bool {
        return run(["cache", "clear"], "cache-clear");
    }

    // Persist the number of versions to keep (the CLI reads the file before elevating).
    function setKeep(n): void {
        keep = Logic.clampKeep(n);
        keepFile.setText(keep + "\n");
    }

    // Open the recovery script in the configured terminal (it elevates with sudo
    // itself): the installed copy in the recovery dir, or the repo's before the
    // first apply has installed one.
    function restore(): void {
        Quickshell.execDetached([Paths.terminal, "bash", "-c",
            'f=$1; [ -f "$f" ] || f=$2; bash "$f"; echo; read -rsn1 -p "Press any key to close "',
            "recovery", Paths.recoveryScript, Paths.recoveryScriptSource]);
    }

    // Forget the last verify result: it belongs to an update that is over or replaced.
    function clearVerify(): void {
        verifier.running = false;
        verifying = false;
        verifyLines = [];
        verifyFailed = false;
    }

    function run(args: var, kind: string): bool {
        if (running)
            return false;
        clearVerify();
        running = true;
        runKind = kind;
        exitCode = -1;
        lines = [];
        log = "";
        logPath = "";
        runner.command = [Paths.pkgUpdate].concat(args);
        runner.running = true;
        return true;
    }

    function appendLine(line: string): void {
        lines = Logic.trimLog(lines.concat([Logic.cleanLine(line)]));
        log = lines.join("\n");
    }

    // The command is over and its log has had time to drain.
    function finishRun(): void {
        tailer.running = false;
        logPath = "";
        if (exitCode < 0)
            appendLine("The command did not run.");
        running = false;
        refreshStatus();
        refreshCache();
        // The packages just changed: what is left to update needs a fresh database.
        if (runKind === "apply" && exitCode === 0)
            startCheck(false, true);
    }

    onPanelOpenChanged: if (panelOpen) refreshCache()

    Timer {
        interval: 10000
        repeat: true
        running: root.panelOpen
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    // tee is asynchronous: give the log follower time to read the last lines.
    Timer {
        id: drain
        interval: 600
        onTriggered: root.finishRun()
    }

    Process {
        id: statusReader
        command: [Paths.pkgUpdate, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(this.text);
                } catch (e) {
                    parsed = null;
                }
                // A verify result belongs to one pending record: another one, or none, voids it.
                // (a failed status call proves nothing, so it keeps the lines).
                const key = Logic.pendingKey(parsed);
                if (parsed !== null && key !== root.pendingKey) {
                    root.pendingKey = key;
                    root.clearVerify();
                }
                root.status = parsed !== null && typeof parsed === "object" ? parsed : null;
            }
        }
    }

    Process {
        id: cacheReader
        command: [Paths.pkgUpdate, "cache", "size"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text.trim(), 10);
                if (!isNaN(n))
                    root.cacheBytes = n;
            }
        }
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                root.checkOut = this.text;
                root.outDone = true;
                root.finishCheck();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.checkErr = this.text;
                root.errDone = true;
                root.finishCheck();
            }
        }
        onExited: code => {
            root.checkExit = code;
            root.checkExited = true;
            root.finishCheck();
        }
    }

    Process {
        id: verifier
        command: [Paths.pkgUpdate, "verify"]
        stdout: SplitParser {
            onRead: line => {
                const l = Logic.cleanLine(line);
                root.verifyLines = root.verifyLines.concat([l]);
                if (l.indexOf("FAIL") === 0)
                    root.verifyFailed = true;
            }
        }
        onRunningChanged: if (!running) root.verifying = false
    }

    // The mutating command. Until `LOG=<path>` arrives its own output is shown
    // (pkexec errors, a refusal before the root part starts); after that the same
    // lines are in the log file, which is followed instead.
    Process {
        id: runner
        stdout: SplitParser {
            onRead: line => {
                if (root.logPath === "" && line.indexOf("LOG=") === 0) {
                    root.logPath = line.slice(4).trim();
                    tailer.running = false;
                    tailer.running = true;
                } else if (root.logPath === "") {
                    root.appendLine(line);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (root.logPath === "")
                    root.appendLine(line);
            }
        }
        onExited: code => {
            root.exitCode = code;
            const msg = Logic.exitMessage(code);
            if (msg !== "")
                root.appendLine(msg);
        }
        onRunningChanged: if (!running && root.running) drain.start()
    }

    Process {
        id: tailer
        command: ["tail", "-n", "+1", "-F", "--", root.logPath]
        stdout: SplitParser {
            onRead: line => root.appendLine(line)
        }
    }

    FileView {
        id: keepFile
        path: Paths.cacheKeepFile
        blockLoading: true
        // pkg-update.sh reads the file right after a save.
        blockWrites: true
        printErrors: false
        watchChanges: true
        onLoaded: root.keep = Logic.clampKeep(text())
        onFileChanged: reload()
    }
}
