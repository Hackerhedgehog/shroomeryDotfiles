import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.shared
import qs.shared.ui
import qs.NotificationPanel

// Notification history: the panel the status bar grows into from the bell
// (hover), or over IPC (toggle.sh, keybinding).
PopoutPanel {
    id: root

    implicitWidth: standardWidth

    // Hug the list, between an empty-state minimum and a cap. The fixed part
    // is the margins, the header and the "Clear all" row.
    readonly property int headerHeight: header.implicitHeight + 18 * 2 + 12
        + (NotificationState.count > 0 ? clearButton.implicitHeight + 12 : 0)
    implicitHeight: Math.min(maxHeight, Math.max(236, Math.min(596, headerHeight + list.contentHeight)))

    // Opening the panel hides the popups: they are all in the list anyway.
    onActiveChanged: {
        if (active)
            NotificationState.hideAllPopups();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 8

            PanelTitle {
                title: "Notifications"
                subtitle: NotificationState.count === 0
                    ? "Nothing new"
                    : NotificationState.count + (NotificationState.count === 1 ? " notification" : " notifications")
            }

            // Pushes the Do Not Disturb switch to the right edge.
            Item {
                Layout.fillWidth: true
            }

            Text {
                text: "Do not disturb"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            ToggleSwitch {
                checked: NotificationState.dnd
                onToggled: NotificationState.setDnd(checked)
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            // ScriptModel diffs the array, so existing cards are kept.
            model: ScriptModel { values: NotificationState.entries }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: NotificationCard {
                required property var modelData
                entry: modelData
                width: ListView.view.width
                onActivated: root.closeRequested()
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                NumberAnimation { property: "x"; from: 40; to: 0; duration: 300; easing.type: Easing.OutQuint }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutQuint }
                NumberAnimation { properties: "opacity"; to: 1; duration: 200 }
                NumberAnimation { properties: "x"; to: 0; duration: 200 }
            }

            // Empty state.
            ColumnLayout {
                anchors.centerIn: parent
                visible: NotificationState.count === 0
                spacing: 8
                ColoredIcon {
                    Layout.alignment: Qt.AlignHCenter
                    source: Paths.icon("bell")
                    size: 32
                    color: Theme.outline
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: NotificationState.dnd ? "Do not disturb is on" : "You're all caught up"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }

        PanelButton {
            id: clearButton
            Layout.alignment: Qt.AlignRight
            visible: NotificationState.count > 0
            compact: true
            text: "Clear all"
            onClicked: NotificationState.clearAll()
        }
    }
}
