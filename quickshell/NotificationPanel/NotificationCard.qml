import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.NotificationPanel

// One notification: icon, app name and age, summary, body and action
// buttons. Used by the panel's list and by the popups. A click on the body
// runs the notification's default action; the × dismisses it for good.
Rectangle {
    id: card

    // A NotificationState entry.
    required property QtObject entry
    readonly property var n: entry ? entry.notification : null
    // Popups cap the body at a few lines; the panel shows it all.
    property int maxBodyLines: 6
    // Emitted after a click ran the default action (callers close/hide).
    signal activated()

    readonly property bool critical: n && n.urgency === NotificationUrgency.Critical
    readonly property bool hovered: hover.hovered

    implicitHeight: layout.implicitHeight + 20
    radius: 8
    color: critical
        ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
        : (hovered ? Theme.surface_container : Theme.surface_container_low)
    border.color: critical ? Theme.error : Theme.outline_variant
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: {
            if (NotificationState.activate(card.entry))
                card.activated();
        }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 10

        // Icon: the notification's image / app icon, or a bell.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 36
            implicitHeight: 36
            radius: 18
            color: Theme.surface_container_highest
            clip: true

            readonly property string src: NotificationState.iconFor(card.n)

            Image {
                id: appIcon
                anchors.fill: parent
                anchors.margins: card.n && card.n.image ? 0 : 6
                source: parent.src
                sourceSize.width: 72
                sourceSize.height: 72
                fillMode: card.n && card.n.image ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                visible: status === Image.Ready
                asynchronous: true
            }
            ColoredIcon {
                anchors.centerIn: parent
                visible: appIcon.status !== Image.Ready
                source: Paths.icon("bell")
                color: card.critical ? Theme.error : Theme.on_surface_variant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: card.n ? (card.n.appName || "Notification") : ""
                    color: card.critical ? Theme.error : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Text {
                    text: card.entry ? NotificationState.relativeTime(card.entry.time) : ""
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                ActionIcon {
                    implicitWidth: 20
                    implicitHeight: 20
                    iconTxt: "✕"
                    iconColor: Theme.on_surface_variant
                    opacity: card.hovered ? 1 : 0.5
                    onClicked: NotificationState.dismiss(card.entry)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.n ? card.n.summary : ""
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.n ? card.n.body : ""
                textFormat: Text.StyledText
                color: Theme.on_surface_variant
                linkColor: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: card.maxBodyLines
                elide: Text.ElideRight
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // Non-default actions as buttons.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                visible: actionRepeater.count > 0

                Repeater {
                    id: actionRepeater
                    model: card.n ? card.n.actions.filter(a => a.identifier !== "default") : []
                    PanelButton {
                        required property var modelData
                        compact: true
                        tonal: true
                        text: modelData.text
                        onClicked: {
                            modelData.invoke();
                            card.activated();
                        }
                    }
                }
            }
        }
    }
}
