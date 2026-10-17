import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.DashboardPanel

// The overview tab: a 3 × 2 grid of equal columns. Top row: output / input
// volume bubbles, the clock, CPU/RAM/disk rings. Bottom row: the weather,
// the month calendar, what's playing. The other tabs take this tab's width.
TabPage {
    id: tab

    readonly property int columnWidth: 300
    readonly property int topHeight: 132
    readonly property int bottomHeight: 270

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    onShownChanged: if (shown) calendar.reset()

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Glyph: Text {
        font.family: Theme.iconFontFamily
        color: Theme.primary
    }

    component Label: Text {
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    GridLayout {
        id: grid
        columns: 3
        rowSpacing: 12
        columnSpacing: 12

        // --- top row ---

        // Output and input volume.
        Card {
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.topHeight

            RowLayout {
                anchors.centerIn: parent
                spacing: 28
                VolumeBubble {
                    node: Pipewire.defaultAudioSink
                    iconName: "volume"
                    mutedIconName: "volume-muted"
                    label: "Output"
                    live: tab.active
                }
                VolumeBubble {
                    node: Pipewire.defaultAudioSource
                    iconName: "microphone"
                    mutedIconName: "microphone-muted"
                    label: "Input"
                    live: tab.active
                }
            }
        }

        Card {
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.topHeight

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 52
                    font.bold: true
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
                    font.pixelSize: 13
                }
            }
        }

        // CPU / RAM / disk; click for the Performance tab.
        Card {
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.topHeight

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tab.requestTab(2)
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 22
                RingGauge {
                    value: SystemStats.cpuPercent / 100
                    centerText: Math.round(SystemStats.cpuPercent) + "%"
                    label: "CPU"
                }
                RingGauge {
                    value: SystemStats.memTotalKb > 0 ? SystemStats.memUsedKb / SystemStats.memTotalKb : 0
                    centerText: Math.round(100 * value) + "%"
                    label: "RAM"
                }
                RingGauge {
                    value: SystemStats.rootDisk ? SystemStats.rootDisk.percent / 100 : 0
                    centerText: Math.round(100 * value) + "%"
                    label: "Disk"
                }
            }
        }

        // --- bottom row ---

        // Weather; click for the Weather tab.
        Card {
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.bottomHeight

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tab.requestTab(3)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4
                visible: Weather.current !== null

                Item { Layout.fillHeight: true }
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    text: Weather.current ? Weather.glyph(Weather.current.code) : ""
                    font.pixelSize: 64
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Weather.current ? Math.round(Weather.current.tempC) + "°" : ""
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 40
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Weather.current ? Weather.current.desc : ""
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: Weather.current !== null && Weather.current.days.length > 0
                    text: Weather.current && Weather.current.days.length > 0
                        ? "H " + Weather.current.days[0].maxC + "°  L " + Weather.current.days[0].minC + "°" : ""
                }
                Item { Layout.fillHeight: true }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Weather.current ? Weather.current.location : ""
                    opacity: 0.7
                }
            }

            Label {
                anchors.centerIn: parent
                visible: Weather.current === null
                text: Weather.loading ? "Loading weather…" : (Weather.error !== "" ? Weather.error : "No weather yet")
            }
        }

        Card {
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.bottomHeight

            MonthCalendar {
                id: calendar
                anchors.fill: parent
                anchors.margins: 12
            }
        }

        // What's playing; click for the Media tab.
        Card {
            id: mediaCard
            readonly property var player: Players.current
            Layout.preferredWidth: tab.columnWidth
            Layout.preferredHeight: tab.bottomHeight

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tab.requestTab(1)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6
                visible: mediaCard.player !== null

                RoundArt {
                    Layout.alignment: Qt.AlignHCenter
                    size: 104
                    live: tab.active
                    source: mediaCard.player && mediaCard.player.trackArtUrl ? mediaCard.player.trackArtUrl : ""
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: mediaCard.player ? (mediaCard.player.trackTitle || mediaCard.player.identity) : ""
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: mediaCard.player ? (mediaCard.player.trackArtist || "") : ""
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    ActionIcon {
                        iconTxt: String.fromCodePoint(0xF04AE)   // skip_previous
                        iconPixelSize: 20
                        enabled: mediaCard.player !== null && mediaCard.player.canGoPrevious
                        onClicked: mediaCard.player.previous()
                    }
                    ActionIcon {
                        iconTxt: String.fromCodePoint(mediaCard.player && mediaCard.player.isPlaying ? 0xF03E4 : 0xF040A)
                        iconPixelSize: 24
                        enabled: mediaCard.player !== null && mediaCard.player.canTogglePlaying
                        onClicked: mediaCard.player.isPlaying = !mediaCard.player.isPlaying
                    }
                    ActionIcon {
                        iconTxt: String.fromCodePoint(0xF04AD)   // skip_next
                        iconPixelSize: 20
                        enabled: mediaCard.player !== null && mediaCard.player.canGoNext
                        onClicked: mediaCard.player.next()
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: mediaCard.player === null
                text: "Nothing playing"
            }
        }
    }
}
