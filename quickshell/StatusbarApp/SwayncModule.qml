import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared

// Toggles the SwayNotificationCenter panel. Shows a filled bell while there
// are pending notifications.
BarButton {
    id: swaync

    property bool hasNotifications: false

    iconSrc: hasNotifications
        ? Paths.icon("bell-filled")
        : Paths.icon("bell")

    onClicked: {
        Quickshell.execDetached(["swaync-client", "-t", "-sw"])
    }

    // Live notification count via swaync's waybar subscription, which emits a
    // JSON line (e.g. {"text": "3", ...}) on every add/close event.
    Process {
        id: swayncProc
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    swaync.hasNotifications = parseInt(JSON.parse(data).text) > 0
                } catch (e) {
                    // Ignore malformed lines.
                }
            }
        }
    }
}
