import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Mpris
import qs.shared
import qs.shared.ui

// One card per MPRIS player: cover art, title/artist and transport controls.
// Grows with the player count up to two cards, then scrolls.
ListView {
    id: list

    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    Layout.maximumHeight: 210

    spacing: 10
    clip: true

    model: Mpris.players.values
    visible: count > 0

    // Only scroll once there are more players than fit.
    interactive: count > 2

    ScrollBar.vertical: ScrollBar {
        policy: list.count > 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        interactive: true
        contentItem: Rectangle {
            implicitWidth: 6; radius: 3; color: Theme.primary
            opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
        }
    }

    delegate: Rectangle {
        id: playerCard
        required property var modelData
        readonly property var player: modelData

        width: list.width - (list.count > 2 ? 16 : 0)
        implicitHeight: 100

        radius: 10
        color: Theme.background
        border.color: Theme.primary
        border.width: 1
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 15

            // Cover art, or a music note when the player has none.
            Rectangle {
                implicitWidth: 80
                implicitHeight: 80
                radius: 8
                color: "transparent"
                border.color: Theme.primary
                border.width: 1
                clip: true

                Image {
                    anchors.fill: parent
                    source: playerCard.player.trackArtUrl ? playerCard.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: playerCard.player.trackArtUrl !== ""
                }
                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    font.family: "monospace"
                    font.pixelSize: 32
                    color: Theme.primary
                    visible: !playerCard.player.trackArtUrl || playerCard.player.trackArtUrl === ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: playerCard.player.trackTitle
                        ? playerCard.player.trackTitle
                        : (playerCard.player.identity ? playerCard.player.identity : "No Media Playing")
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const p = playerCard.player
                        if (p.trackArtist) return p.trackArtist
                        if (p.trackArtists && p.trackArtists.length > 0) return p.trackArtists[0]
                        return "Unknown Artist"
                    }
                    color: Theme.on_background
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    opacity: 0.8
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15

                    Item { Layout.fillWidth: true }

                    ActionIcon {
                        iconTxt: "󰒮"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: playerCard.player.previous()
                    }

                    ActionIcon {
                        iconTxt: playerCard.player.isPlaying ? "󰏤" : "󰐊"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: playerCard.player.isPlaying = !playerCard.player.isPlaying
                    }

                    ActionIcon {
                        iconTxt: "󰒭"
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: playerCard.player.next()
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
