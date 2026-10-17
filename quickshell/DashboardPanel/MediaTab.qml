import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.shared
import qs.shared.ui
import qs.DashboardPanel
import "Stats.js" as Stats

// Full player for Players.current: round cover art, title/artist/album, a seek bar
// (when the player can seek), shuffle / previous / play-pause / next / loop,
// and a row to pick the player when more than one is running.
TabPage {
    id: tab

    readonly property var player: Players.current

    implicitWidth: 580
    implicitHeight: Math.max(240, content.implicitHeight)

    // MPRIS does not push the position; poll it while visible and playing.
    Timer {
        interval: 1000
        repeat: true
        running: tab.active && tab.player !== null && tab.player.isPlaying
        onTriggered: tab.player.positionChanged()
    }

    ColumnLayout {
        id: content
        width: tab.implicitWidth
        spacing: 12
        visible: tab.player !== null

        RowLayout {
            spacing: 18

            RoundArt {
                id: art
                size: 184
                live: tab.active
                source: tab.player && tab.player.trackArtUrl ? tab.player.trackArtUrl : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: art.implicitHeight
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: tab.player ? (tab.player.trackTitle || tab.player.identity) : ""
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    text: tab.player ? (tab.player.trackArtist || "") : ""
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tab.player ? (tab.player.trackAlbum || "") : ""
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                // Seek bar.
                Item {
                    id: seek
                    Layout.fillWidth: true
                    implicitHeight: 16
                    readonly property real fraction: tab.player && tab.player.length > 0
                        ? Math.max(0, Math.min(1, tab.player.position / tab.player.length)) : 0
                    readonly property bool canSeek: tab.player !== null && tab.player.canSeek && tab.player.length > 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.surface_container_highest
                        Rectangle {
                            width: parent.width * seek.fraction
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }
                    Rectangle {
                        visible: seek.canSeek
                        x: seek.width * seek.fraction - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: seek.canSeek
                        cursorShape: Qt.PointingHandCursor
                        function seekTo(x: real): void {
                            tab.player.position = Math.max(0, Math.min(1, x / width)) * tab.player.length;
                        }
                        onPressed: mouse => seekTo(mouse.x)
                        onPositionChanged: mouse => { if (pressed) seekTo(mouse.x); }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Stats.formatClock(tab.player ? tab.player.position : 0)
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Stats.formatClock(tab.player ? tab.player.length : 0)
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    ActionIcon {
                        visible: tab.player !== null && tab.player.shuffleSupported
                        iconTxt: String.fromCodePoint(tab.player && tab.player.shuffle ? 0xF049F : 0xF049E)
                        iconPixelSize: 18
                        onClicked: tab.player.shuffle = !tab.player.shuffle
                    }
                    ActionIcon {
                        iconTxt: String.fromCodePoint(0xF04AE)
                        iconPixelSize: 24
                        enabled: tab.player !== null && tab.player.canGoPrevious
                        onClicked: tab.player.previous()
                    }
                    ActionIcon {
                        implicitWidth: 44
                        implicitHeight: 44
                        iconTxt: String.fromCodePoint(tab.player && tab.player.isPlaying ? 0xF03E4 : 0xF040A)
                        iconPixelSize: 32
                        enabled: tab.player !== null && tab.player.canTogglePlaying
                        onClicked: tab.player.isPlaying = !tab.player.isPlaying
                    }
                    ActionIcon {
                        iconTxt: String.fromCodePoint(0xF04AD)
                        iconPixelSize: 24
                        enabled: tab.player !== null && tab.player.canGoNext
                        onClicked: tab.player.next()
                    }
                    ActionIcon {
                        visible: tab.player !== null && tab.player.loopSupported
                        iconTxt: String.fromCodePoint(!tab.player ? 0xF0457
                            : tab.player.loopState === MprisLoopState.Track ? 0xF0458
                            : tab.player.loopState === MprisLoopState.Playlist ? 0xF0456 : 0xF0457)
                        iconPixelSize: 18
                        onClicked: {
                            const s = tab.player.loopState;
                            tab.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                                : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
                        }
                    }
                }
            }
        }

        // Player picker.
        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: Players.list.length > 1

            Repeater {
                model: Players.list
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool current: modelData === tab.player
                    implicitWidth: chip.implicitWidth + 24
                    implicitHeight: 28
                    radius: 14
                    color: current ? Theme.primary_container : Theme.surface_container_high
                    Text {
                        id: chip
                        anchors.centerIn: parent
                        text: parent.modelData.identity || "Player"
                        color: parent.current ? Theme.on_primary_container : Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Players.chosen = parent.modelData
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: tab.player === null
        text: "Nothing playing"
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 14
    }
}
