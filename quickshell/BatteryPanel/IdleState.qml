pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared
import qs.shared.ui
import "IdleLogic.js" as Logic

// What happens when the machine sits idle (hypridle.conf listeners) and when
// the lid closes (systemd-logind, through shroomery's lid-switch.sh). Shown in
// the battery panel; kept here so a pending password prompt outlives the panel.
Singleton {
    id: root

    readonly property bool panelOpen: PopoutState.currentName === "battery"
    onPanelOpenChanged: if (panelOpen) refreshLid()

    // ------------------------------------------------------------- hypridle

    // parseListeners() blocks, plus `choices` for the combo.
    property var listeners: []

    function parse(): void {
        root.listeners = Logic.parseListeners(conf.text()).map(block => {
            block.choices = Logic.choices(block);
            return block;
        });
    }

    // Fire listener `index` after `seconds`, or never (0 comments it out).
    // hypridle reads its config once, so a running one is restarted.
    function setIdleTimeout(index: int, seconds: int): void {
        const before = conf.text();
        const after = Logic.setTimeoutAt(before, index, seconds);
        if (after === before)
            return;
        conf.setText(after);
        Qt.callLater(root.parse);
        Quickshell.execDetached(["sh", "-c",
            "pgrep -x hypridle >/dev/null || exit 0; pkill -x hypridle; "
            + "while pgrep -x hypridle >/dev/null; do sleep 0.1; done; "
            + "exec setsid -f hypridle >/dev/null 2>&1"]);
    }

    FileView {
        id: conf
        path: Paths.hypridleConf
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse()
        onLoadFailed: root.listeners = []
    }

    // ------------------------------------------------------------------ lid

    // lid-switch.sh's actions, in menu order. `needs` names the logind
    // Can* check the action depends on (hibernation needs swap + resume).
    readonly property var allLidActions: [
        { value: "suspend", label: "Suspend" },
        { value: "hibernate", label: "Hibernate", needs: "CanHibernate" },
        { value: "suspend-then-hibernate", label: "Suspend, then hibernate", needs: "CanSuspendThenHibernate" },
        { value: "hybrid-sleep", label: "Hybrid sleep", needs: "CanHybridSleep" },
        { value: "lock", label: "Lock the screen" },
        { value: "poweroff", label: "Power off" },
        { value: "ignore", label: "Do nothing" }
    ]
    // The ones that would work here ("challenge" = allowed after a password).
    readonly property var lidActions: allLidActions.filter(action =>
        !action.needs || lid[action.needs] === "yes" || lid[action.needs] === "challenge")

    // True when the machine has a lid (a laptop).
    property bool lidPresent: false
    // What logind does now and can do: { HandleLidSwitch: "suspend",
    // HandleLidSwitchExternalPower: "", CanHibernate: "na", … }.
    property var lid: ({})
    // { key, action } while a change waits for the password / logind reload.
    property var lidPending: null
    property string lidError: ""

    // The action shown for `key`: the pending one while a change is in flight.
    function lidAction(key: string): string {
        if (lidPending && lidPending.key === key)
            return lidPending.action;
        return lid[key] || "";
    }

    function refreshLid(): void {
        if (!lidReader.running)
            lidReader.running = true;
    }

    function setLid(key: string, action: string): void {
        if (lidWriter.running || action === lidAction(key))
            return;
        root.lidError = "";
        root.lidPending = { key: key, action: action };
        lidWriter.command = [Paths.lidSwitch, "set", key, action];
        lidWriter.running = true;
    }

    Process {
        id: lidReader
        command: [Paths.lidSwitch, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = {};
                let present = false;
                for (const line of this.text.split("\n")) {
                    const eq = line.indexOf("=");
                    if (eq < 0)
                        continue;
                    const key = line.slice(0, eq), value = line.slice(eq + 1).trim();
                    if (key === "present")
                        present = value === "true";
                    else
                        values[key] = value;
                }
                root.lidPresent = present;
                root.lid = values;
            }
        }
    }

    Process {
        id: lidWriter
        stderr: StdioCollector { id: lidWriterErr }
        onExited: code => {
            // 2 = the password prompt was dismissed: nothing changed, no error.
            if (code !== 0 && code !== 2)
                root.lidError = lidWriterErr.text.trim() || "Could not change logind.conf (exit " + code + ").";
            root.lidPending = null;
            root.refreshLid();
        }
    }

    Component.onCompleted: refreshLid()
}
