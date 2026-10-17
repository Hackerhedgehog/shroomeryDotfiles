pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import qs.shared
import qs.shared.ui
import qs.VisualizerApp

// The notification daemon (org.freedesktop.Notifications) and its history.
// Only one daemon can own that D-Bus name: while swaync (or any other
// daemon) is running, this server does not receive anything.
//
// Every incoming notification becomes an entry (newest first) that shows as
// a popup until it times out and stays in the panel's list until dismissed.
// Do Not Disturb (persisted in shroomery/settings/notifications.json)
// suppresses the popups of everything but critical notifications.
Singleton {
    id: root

    // Whether the notification panel is open in the status bar.
    readonly property bool panelOpen: PopoutState.currentName === "notifications"

    // Newest first. Each entry: { notification, time, popup, hovered }.
    property var entries: []
    readonly property int count: entries.length
    readonly property var popups: entries.filter(e => e.popup)

    // Ticks so relative times ("5m") stay current.
    readonly property date now: clock.date
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- Do Not Disturb ---
    readonly property bool dnd: settingsAdapter.dnd

    function setDnd(on: bool): void {
        settingsAdapter.dnd = on;
        settingsFile.writeAdapter();
        if (on)
            hideAllPopups();
    }

    FileView {
        id: settingsFile
        path: Paths.notificationSettings
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: settingsAdapter
            property bool dnd: false
        }
    }

    function toggle(): void {
        PopoutState.toggle("notifications");
    }

    // --- actions ---
    function dismiss(entry: QtObject): void {
        if (entry && entry.notification)
            entry.notification.dismiss();
    }

    function clearAll(): void {
        const list = entries.slice();
        for (let i = 0; i < list.length; i++)
            dismiss(list[i]);
    }

    function hidePopup(entry: QtObject): void {
        if (!entry)
            return;
        entry.popup = false;
        // Transient notifications don't belong in the history.
        if (entry.notification && entry.notification.transient)
            entry.notification.expire();
    }

    // Popups already on screen go to the history when visualizer mode starts.
    Connections {
        target: VisualizerState
        function onActiveChanged() {
            if (VisualizerState.active)
                root.hideAllPopups();
        }
    }

    function hideAllPopups(): void {
        const list = entries.slice();
        for (let i = 0; i < list.length; i++)
            if (list[i].popup)
                hidePopup(list[i]);
    }

    // Run the notification's "default" action (a click on its body), if any.
    function activate(entry: QtObject): bool {
        const n = entry ? entry.notification : null;
        if (!n)
            return false;
        for (let i = 0; i < n.actions.length; i++) {
            if (n.actions[i].identifier === "default") {
                n.actions[i].invoke();
                return true;
            }
        }
        return false;
    }

    // "now", "5m", "3h", or the clock time / date for older ones.
    function relativeTime(time: date): string {
        const mins = Math.floor((root.now.getTime() - time.getTime()) / 60000);
        if (mins < 1)
            return "now";
        if (mins < 60)
            return mins + "m";
        if (mins < 24 * 60)
            return Math.floor(mins / 60) + "h";
        return Qt.formatDateTime(time, "ddd HH:mm");
    }

    // Icon source for a notification: its image, else its app icon (name or
    // path), else empty.
    function iconFor(n: var): string {
        if (!n)
            return "";
        if (n.image)
            return n.image;
        const icon = n.appIcon || n.desktopEntry || "";
        if (icon === "")
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.includes("://"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    component Entry: QtObject {
        id: entry
        property Notification notification
        property date time: new Date()
        property bool popup: true
        property bool hovered: false

        readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
        readonly property int timeoutMs: notification && notification.expireTimeout > 0
            ? notification.expireTimeout * 1000
            : (notification && notification.urgency === NotificationUrgency.Low ? 3000 : 6000)

        property Timer timer: Timer {
            interval: entry.timeoutMs
            running: entry.popup && !entry.hovered && !entry.critical
            onTriggered: root.hidePopup(entry)
        }
    }

    Component {
        id: entryComponent
        Entry {}
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            // Do Not Disturb and visualizer mode let only critical ones pop up.
            const quiet = root.dnd || VisualizerState.active;
            const showPopup = !root.panelOpen
                && (!quiet || n.urgency === NotificationUrgency.Critical);
            const entry = entryComponent.createObject(root, {
                notification: n,
                popup: showPopup
            });
            let times = Object.assign({}, persist.times);
            times[n.id] = entry.time.getTime();
            persist.times = times;
            n.closed.connect(() => root.remove(entry));
            root.entries = [entry].concat(root.entries);
            if (!showPopup && n.transient)
                n.expire();
        }
    }

    // Arrival times by notification id, kept across hot reloads along with
    // the notifications themselves.
    PersistentProperties {
        id: persist
        reloadableId: "notificationTimes"
        property var times: ({})
    }

    function remove(entry: QtObject): void {
        root.entries = root.entries.filter(e => e !== entry);
        if (entry.notification) {
            let times = Object.assign({}, persist.times);
            delete times[entry.notification.id];
            persist.times = times;
        }
        entry.destroy(1000);
    }

    // Re-adopt notifications kept across a hot reload (keepOnReload).
    Component.onCompleted: {
        const kept = server.trackedNotifications.values;
        let list = [];
        for (let i = kept.length - 1; i >= 0; i--) {
            const n = kept[i];
            const t = persist.times[n.id];
            const entry = entryComponent.createObject(root, {
                notification: n,
                popup: false,
                time: t ? new Date(t) : new Date()
            });
            n.closed.connect(() => root.remove(entry));
            list.push(entry);
        }
        root.entries = list;
    }

    IpcHandler {
        target: "notifications-state"
        function clearAll(): void { root.clearAll(); }
        function setDnd(on: bool): void { root.setDnd(on); }
        function toggleDnd(): void { root.setDnd(!root.dnd); }
        function isDnd(): bool { return root.dnd; }
        function count(): int { return root.count; }
    }
}
