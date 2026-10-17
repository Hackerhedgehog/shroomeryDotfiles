import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.Pipewire
import qs.shared
import qs.AudioPanel

// One volume control: icon, name, slider, percentage, mute button and a live
// peak meter. Used for the master blocks and for every mixer stream.
Item {
    id: row

    property var node: null
    property string title: ""
    property string subtitle: ""
    property bool large: false
    property bool micIcon: false
    // Peak monitoring costs a PipeWire stream per node, so only the visible
    // tab turns it on. Never on a muted node: the capture stream wakes the
    // device even when muted (a mic with hardware sidetone would play back).
    property bool meterActive: false

    readonly property bool muted: AudioState.isMuted(node)
    readonly property real modelVolume: AudioState.volumeOf(node)
    readonly property int iconSize: large ? 22 : 18

    implicitHeight: layout.implicitHeight

    PwNodePeakMonitor {
        id: peakMonitor
        node: row.node
        enabled: row.meterActive && row.node !== null && !row.muted
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                Layout.alignment: Qt.AlignVCenter
                source: {
                    if (row.micIcon)
                        return row.muted ? Paths.icon("microphone-muted") : Paths.icon("microphone");
                    return row.muted ? Paths.icon("volume-muted") : Paths.icon("volume");
                }
                width: row.iconSize
                height: row.iconSize
                sourceSize.width: row.iconSize
                sourceSize.height: row.iconSize
                fillMode: Image.PreserveAspectFit
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: row.muted ? Theme.outline : Theme.primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    color: row.muted ? Theme.on_surface_variant : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: row.large ? 15 : 13
                    font.bold: row.large
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: row.subtitle !== ""
                    text: row.subtitle
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Text {
                text: AudioState.volumePercent(row.node) + "%"
                color: row.muted ? Theme.outline : (row.modelVolume > 1 ? Theme.tertiary : Theme.primary)
                font.family: Theme.fontFamily
                font.pixelSize: row.large ? 14 : 12
                font.bold: true
                horizontalAlignment: Text.AlignRight
                Layout.minimumWidth: 40
            }

            Button {
                implicitWidth: 28
                implicitHeight: 28
                enabled: row.node !== null
                onClicked: AudioState.toggleMute(row.node)
                background: Rectangle {
                    radius: 6
                    color: row.muted ? Theme.error_container : "transparent"
                    border.color: row.muted ? Theme.error_container : Theme.outline_variant
                    border.width: 1
                }
                contentItem: Text {
                    text: row.muted ? "✕" : "◉"
                    color: row.muted ? Theme.on_error_container : Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            Layout.leftMargin: row.iconSize + 8
            implicitHeight: row.large ? 26 : 22
            from: 0
            to: AudioState.maxVolume
            enabled: row.node !== null
            stepSize: 0.01

            // Track the model unless the user is actively dragging, so the
            // slider follows external volume changes without fighting them.
            Component.onCompleted: value = row.modelVolume
            onMoved: AudioState.setVolume(row.node, value)

            Connections {
                target: row
                function onModelVolumeChanged() {
                    if (!slider.pressed)
                        slider.value = row.modelVolume;
                }
            }

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + (slider.availableHeight - height) / 2
                width: slider.availableWidth
                height: row.large ? 7 : 5
                radius: height / 2
                color: Theme.surface_container_highest

                // Marks unity gain; everything past it is amplification.
                Rectangle {
                    x: parent.width / AudioState.maxVolume - width / 2
                    width: 2
                    height: parent.height
                    color: Theme.outline
                    opacity: 0.9
                }

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: row.muted ? Theme.outline : (slider.value > 1 ? Theme.tertiary : Theme.primary)
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + (slider.availableHeight - height) / 2
                implicitWidth: row.large ? 16 : 13
                implicitHeight: row.large ? 16 : 13
                radius: width / 2
                color: Theme.background
                border.color: row.muted ? Theme.outline : (slider.value > 1 ? Theme.tertiary : Theme.primary)
                border.width: 2
            }
        }

        // Peak meter.
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: row.iconSize + 8
            Layout.bottomMargin: 2
            implicitHeight: 3
            radius: 1.5
            color: Theme.surface_container_highest
            opacity: row.meterActive ? 1 : 0

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, peakMonitor.peak))
                height: parent.height
                radius: parent.radius
                color: row.muted ? Theme.outline : Theme.primary
                opacity: 0.85
                Behavior on width {
                    NumberAnimation {
                        duration: 60
                    }
                }
            }
        }
    }
}
