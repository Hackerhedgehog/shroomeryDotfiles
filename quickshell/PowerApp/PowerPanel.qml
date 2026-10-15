import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui

// Power menu: the panel the status bar grows into from the power button
// (lock, suspend, logout, reboot, power off through shroomery's power.sh).
// Arrow keys move the selection, Return runs it.
// Reboot and power off ask first: their bubble grows over the others with a
// 5 s countdown. Clicking the bubble (or Return) runs it now; Cancel, Escape,
// a click anywhere else or the panel closing calls it off.
PopoutPanel {
    id: root

    implicitWidth: standardWidth
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 36)

    readonly property var actions: [
        { icon: "lock", label: "Lock", flag: "-l" },
        { icon: "suspend", label: "Suspend", flag: "-s" },
        { icon: "logout", label: "Log out", flag: "-e" },
        { icon: "reboot", label: "Reboot", flag: "-r", confirm: "Rebooting" },
        { icon: "power", label: "Power off", flag: "-p", confirm: "Powering off" }
    ]
    readonly property int countdownSeconds: 5

    // Keyboard selection; -1 until an arrow key is pressed.
    property int selectedIndex: -1
    // The action counting down, or -1.
    property int pendingIndex: -1
    readonly property var pending: pendingIndex >= 0 ? actions[pendingIndex] : null
    property int remaining: 0

    // The confirm bubble grows from the tile's rect (`fromRect`, in this
    // item's coordinates) to the whole tile row (`toRect`) while `expanded`.
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    property rect toRect: Qt.rect(0, 0, 0, 0)
    property bool expanded: false

    escapeHandler: function () {
        if (root.pendingIndex < 0)
            return false;
        root.cancel();
        return true;
    }

    onActiveChanged: {
        cancel();
        if (!active)
            return;
        selectedIndex = -1;
        uptimeFile.reload();
        keys.forceActiveFocus();
    }

    function execute(index: int): void {
        root.closeRequested();
        Quickshell.execDetached([Paths.power, actions[index].flag]);
    }

    // A tile was picked (click or Return).
    function run(index: int): void {
        if (index < 0 || index >= actions.length)
            return;
        if (actions[index].confirm)
            startConfirm(index);
        else
            execute(index);
    }

    function startConfirm(index: int): void {
        const tile = tiles.itemAt(index);
        const fromPos = tile.mapToItem(root, 0, 0);
        const rowPos = buttons.mapToItem(root, 0, 0);
        root.fromRect = Qt.rect(fromPos.x, fromPos.y, tile.width, tile.height);
        root.toRect = Qt.rect(rowPos.x, rowPos.y, buttons.width, buttons.height);
        root.pendingIndex = index;
        root.remaining = root.countdownSeconds;
        countdown.restart();
        // Next frame, so the bubble starts on the tile and animates out.
        Qt.callLater(() => { if (root.pendingIndex === index) root.expanded = true; });
    }

    // Skip the countdown.
    function confirmNow(): void {
        const index = root.pendingIndex;
        if (index < 0)
            return;
        root.cancel();
        root.execute(index);
    }

    function cancel(): void {
        countdown.stop();
        root.expanded = false;
        root.pendingIndex = -1;
    }

    function step(dir: int): void {
        const n = actions.length;
        selectedIndex = selectedIndex < 0 ? (dir > 0 ? 0 : n - 1) : (selectedIndex + dir + n) % n;
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining--;
            if (root.remaining <= 0)
                root.confirmNow();
        }
    }

    // "Up 3 h 12 min" from /proc/uptime.
    readonly property string uptimeText: {
        const seconds = parseFloat(uptimeFile.text());
        if (!(seconds > 0))
            return "";
        const minutes = Math.floor(seconds / 60);
        const d = Math.floor(minutes / 1440), h = Math.floor(minutes / 60) % 24, m = minutes % 60;
        if (d > 0)
            return "Up " + d + " d " + h + " h";
        return h > 0 ? "Up " + h + " h " + m + " min" : "Up " + m + " min";
    }

    FileView {
        id: uptimeFile
        path: Paths.procDir + "/uptime"
        printErrors: false
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        Keys.onLeftPressed: if (root.pendingIndex < 0) root.step(-1)
        Keys.onRightPressed: if (root.pendingIndex < 0) root.step(1)
        Keys.onUpPressed: if (root.pendingIndex < 0) root.step(-1)
        Keys.onDownPressed: if (root.pendingIndex < 0) root.step(1)
        Keys.onTabPressed: if (root.pendingIndex < 0) root.step(1)
        Keys.onBacktabPressed: if (root.pendingIndex < 0) root.step(-1)
        Keys.onReturnPressed: root.pendingIndex >= 0 ? root.confirmNow() : root.run(root.selectedIndex)
        Keys.onEnterPressed: root.pendingIndex >= 0 ? root.confirmNow() : root.run(root.selectedIndex)
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        PanelTitle {
            title: "Power"
            subtitle: root.uptimeText
        }

        Card {
            Layout.fillWidth: true
            implicitHeight: buttons.implicitHeight + 24

            RowLayout {
                id: buttons
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Repeater {
                    id: tiles
                    model: root.actions

                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool highlighted: root.pendingIndex < 0
                            && (mouseArea.containsMouse || root.selectedIndex === index)

                        Layout.fillWidth: true
                        implicitHeight: 76
                        radius: 14
                        color: highlighted ? Theme.primary : Theme.surface_container_high
                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            ColoredIcon {
                                Layout.alignment: Qt.AlignHCenter
                                size: 22
                                source: Paths.icon(tile.modelData.icon)
                                color: tile.highlighted ? Theme.on_primary : Theme.on_surface
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.modelData.label
                                color: tile.highlighted ? Theme.on_primary : Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: if (containsMouse) root.selectedIndex = tile.index
                            onClicked: root.run(tile.index)
                        }
                    }
                }
            }
        }
    }

    // While counting down, a click anywhere in the panel but the bubble
    // cancels.
    MouseArea {
        anchors.fill: parent
        visible: root.pendingIndex >= 0
        onClicked: root.cancel()
    }

    // ------------------------------------------------------ confirm bubble

    Rectangle {
        id: bubble

        readonly property int ms: 260
        x: root.expanded ? root.toRect.x : root.fromRect.x
        y: root.expanded ? root.toRect.y : root.fromRect.y
        width: root.expanded ? root.toRect.width : root.fromRect.width
        height: root.expanded ? root.toRect.height : root.fromRect.height
        Behavior on x { NumberAnimation { duration: bubble.ms; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: bubble.ms; easing.type: Easing.OutQuint } }

        // Stays up while shrinking back after a cancel.
        visible: root.pendingIndex >= 0 || width > root.fromRect.width + 0.5
        radius: 14
        color: Theme.primary
        clip: true

        // The last shown action, so the contents don't blank mid-shrink.
        property var shown: null
        Connections {
            target: root
            function onPendingChanged(): void { if (root.pending) bubble.shown = root.pending; }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmNow()
        }

        // Time left, draining along the bottom edge.
        Rectangle {
            id: drain
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: 4
            color: Theme.on_primary
            opacity: 0.35
            width: 0
            NumberAnimation on width {
                id: drainAnim
                running: false
                duration: root.countdownSeconds * 1000
            }
            Connections {
                target: root
                function onPendingIndexChanged(): void {
                    drainAnim.stop();
                    if (root.pendingIndex < 0)
                        return;
                    drainAnim.from = root.toRect.width;
                    drainAnim.to = 0;
                    drainAnim.start();
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 14
            opacity: root.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            ColoredIcon {
                size: 26
                source: bubble.shown ? Paths.icon(bubble.shown.icon) : ""
                color: Theme.on_primary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: bubble.shown ? bubble.shown.confirm + " in " + root.remaining + " s" : ""
                    color: Theme.on_primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: "Click to " + (bubble.shown ? bubble.shown.label.toLowerCase() : "") + " now"
                    color: Theme.on_primary
                    opacity: 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            PanelButton {
                text: "Cancel"
                compact: true
                onClicked: root.cancel()
            }
        }
    }
}
