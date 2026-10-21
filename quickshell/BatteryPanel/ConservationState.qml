pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared

// Lenovo battery conservation mode (ideapad_acpi), through shroomery's
// conservation-mode.sh. `available` is false on other machines, so the toggles
// hide themselves. Shown in the battery panel and flipped by a right click on
// the battery module.
Singleton {
    id: root

    property bool available: false
    property bool enabled: false
    // True while the password prompt / write is in flight.
    property bool busy: false
    property string error: ""

    function refresh(): void {
        if (!reader.running)
            reader.running = true;
    }

    function toggle(): void {
        if (!available || writer.running)
            return;
        root.error = "";
        root.busy = true;
        writer.command = [Paths.conservationMode, "toggle"];
        writer.running = true;
    }

    Process {
        id: reader
        command: [Paths.conservationMode, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = this.text.includes("available=true");
                root.enabled = this.text.includes("enabled=true");
            }
        }
    }

    Process {
        id: writer
        stderr: StdioCollector { id: writerErr }
        onExited: code => {
            // 2 = the password prompt was dismissed: nothing changed, no error.
            if (code !== 0 && code !== 2)
                root.error = writerErr.text.trim() || "Could not change conservation mode (exit " + code + ").";
            root.busy = false;
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
