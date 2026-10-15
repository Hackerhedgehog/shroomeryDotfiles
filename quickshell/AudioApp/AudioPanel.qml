import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.AudioApp

PopoutPanel {
    id: root

    implicitWidth: standardWidth
    // Sized to the current tab's content, up to the screen; then it scrolls.
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 36)

    // 0 Output, 1 Mixer, 2 Input
    property int currentTab: 0

    // While the compressor runs, Pipewire.defaultAudioSink is the virtual
    // node, which has no card — profile/port lookups against it come back
    // empty and ChoiceRow hides itself. Card-bearing controls read the real
    // device instead. (The default-sink VolumeRow deliberately does not: the
    // virtual sink's volume is the one applications play into.)
    readonly property var realSink: {
        if (!LoudnessState.running)
            return AudioState.defaultSink;
        const nodes = AudioState.sinks;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].name === LoudnessState.targetSinkName)
                return nodes[i];
        }
        return AudioState.defaultSink;
    }

    component EmptyNote: Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    // A labelled combo over {name, description} options, driven by whichever
    // option is currently active rather than by its own selection state.
    component ChoiceRow: RowLayout {
        id: choice
        property string label: ""
        property var options: []
        property string activeName: ""
        signal picked(string name)

        Layout.fillWidth: true
        spacing: 8
        visible: options.length > 1

        Text {
            text: choice.label
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 12
            Layout.minimumWidth: 52
        }

        FieldCombo {
            id: combo
            Layout.fillWidth: true
            model: choice.options.map(option => option.description)

            readonly property int desiredIndex: {
                for (let i = 0; i < choice.options.length; i++) {
                    if (choice.options[i].name === choice.activeName)
                        return i;
                }
                return -1;
            }

            onDesiredIndexChanged: currentIndex = desiredIndex
            Component.onCompleted: currentIndex = desiredIndex
            onActivated: index => {
                if (index >= 0 && index < choice.options.length)
                    choice.picked(choice.options[index].name);
            }
        }
    }

    // One selectable output/input device.
    component DeviceCard: Rectangle {
        id: card
        property var node: null
        property bool active: false

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 8
        color: active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Theme.surface_container_low
        border.color: active ? Theme.primary : Theme.outline_variant
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Text {
                text: card.active ? "◉" : "○"
                color: card.active ? Theme.primary : Theme.outline
                font.pixelSize: 13
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: AudioState.displayName(card.node)
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: AudioState.describeDevice(card.node)
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            PanelButton {
                text: card.active ? "Active" : "Select"
                enabled: !card.active
                tonal: card.active
                onClicked: {
                    if (card.node.isSink) {
                        // While the compressor is running it — not the physical
                        // device — is the default sink, so picking a device
                        // re-points the chain rather than bypassing it.
                        if (LoudnessState.running)
                            LoudnessState.retarget(card.node);
                        else
                            AudioState.selectSink(card.node);
                    } else
                        AudioState.selectSource(card.node);
                }
            }
        }
    }

    component TabScroll: ScrollView {
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Theme.primary
                opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Audio"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }
                Text {
                    text: "Outputs, app volumes and microphones"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: Math.min(200, chipText.implicitWidth + 20)
                radius: 13
                color: AudioState.ready ? Theme.primary_container : Theme.error_container
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    width: parent.width - 16
                    text: {
                        if (!AudioState.ready)
                            return "PipeWire offline";
                        const sink = AudioState.defaultSink;
                        if (!sink)
                            return "No output";
                        return sink.nickname || AudioState.displayName(sink);
                    }
                    color: AudioState.ready ? Theme.on_primary_container : Theme.on_error_container
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }

        // Tab bar.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: 10
            color: Theme.surface_container_low
            border.color: Theme.outline_variant
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 3

                Repeater {
                    model: ["Output", "Mixer", "Input"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: root.currentTab === index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: current ? Theme.primary_container : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.current ? Theme.on_primary_container : Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: parent.current
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = parent.index
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: AudioState.errorMessage !== ""
            text: AudioState.errorMessage
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            visible: !AudioState.ready
            text: "PipeWire is not available. Start the pipewire and wireplumber user services to control audio."
            color: Theme.tertiary
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // StackLayout reports its tallest tab; size to the current one so
            // switching tabs resizes the panel.
            Layout.preferredHeight: [outputScroll, mixerScroll, inputScroll][root.currentTab].implicitHeight
            currentIndex: root.currentTab

            // ------------------------------------------------- Output tab
            TabScroll {
                id: outputScroll

                ColumnLayout {
                    width: outputScroll.availableWidth
                    spacing: 10

                    VolumeRow {
                        Layout.fillWidth: true
                        node: AudioState.defaultSink
                        large: true
                        meterActive: root.active && root.currentTab === 0
                        title: AudioState.defaultSink ? AudioState.displayName(AudioState.defaultSink) : "No output device"
                        subtitle: AudioState.defaultSink ? AudioState.describeDevice(AudioState.defaultSink) : ""
                    }

                    // Balance.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: AudioState.supportsBalance(root.realSink)

                        Text {
                            text: "Balance"
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            Layout.minimumWidth: 52
                        }

                        Slider {
                            id: balanceSlider
                            Layout.fillWidth: true
                            implicitHeight: 22
                            from: -1
                            to: 1
                            stepSize: 0.01

                            readonly property real modelBalance: AudioState.balanceOf(root.realSink)
                            onModelBalanceChanged: {
                                if (!pressed)
                                    value = modelBalance;
                            }
                            Component.onCompleted: value = modelBalance
                            onMoved: AudioState.setBalance(root.realSink, value)

                            background: Rectangle {
                                x: balanceSlider.leftPadding
                                y: balanceSlider.topPadding + (balanceSlider.availableHeight - height) / 2
                                width: balanceSlider.availableWidth
                                height: 5
                                radius: 2.5
                                color: Theme.surface_container_highest
                                Rectangle {
                                    x: parent.width / 2 - 1
                                    width: 2
                                    height: parent.height
                                    color: Theme.outline
                                }
                            }

                            handle: Rectangle {
                                x: balanceSlider.leftPadding + balanceSlider.visualPosition * (balanceSlider.availableWidth - width)
                                y: balanceSlider.topPadding + (balanceSlider.availableHeight - height) / 2
                                implicitWidth: 13
                                implicitHeight: 13
                                radius: 6.5
                                color: Theme.background
                                border.color: Theme.primary
                                border.width: 2
                            }
                        }

                        PanelButton {
                            text: "Center"
                            onClicked: AudioState.setBalance(root.realSink, 0)
                        }
                    }

                    ChoiceRow {
                        label: "Profile"
                        options: AudioState.profilesForNode(root.realSink)
                        activeName: AudioState.activeProfileForNode(root.realSink)
                        onPicked: name => AudioState.setCardProfile(root.realSink, name)
                    }

                    ChoiceRow {
                        label: "Port"
                        options: AudioState.portsForNode(root.realSink)
                        activeName: AudioState.activePortForNode(root.realSink)
                        onPicked: name => AudioState.setPort(root.realSink, name)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: 1
                        color: Theme.primary
                        opacity: 0.3
                    }

                    SectionHeader {
                        label: "Output devices"
                    }

                    Repeater {
                        model: AudioState.sinks
                        delegate: DeviceCard {
                            required property var modelData
                            node: modelData
                            // While the compressor runs, the default sink
                            // is the hidden virtual node, so the device
                            // that is really in use is the one the chain
                            // feeds — not whatever PipeWire calls default.
                            active: LoudnessState.running
                                ? modelData.name === LoudnessState.targetSinkName
                                : AudioState.isDefaultSink(modelData)
                        }
                    }

                    EmptyNote {
                        visible: AudioState.sinks.length === 0
                        text: "No output devices found."
                    }

                    LoudnessCard {
                        Layout.fillWidth: true
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // -------------------------------------------------- Mixer tab
            TabScroll {
                id: mixerScroll

                ColumnLayout {
                    width: mixerScroll.availableWidth
                    spacing: 8

                    SectionHeader {
                        label: "Playing"
                    }

                    Repeater {
                        model: AudioState.outputStreams
                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: streamRow.implicitHeight + 20
                            radius: 8
                            color: Theme.surface_container_low
                            border.color: Theme.outline_variant
                            border.width: 1

                            VolumeRow {
                                id: streamRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                node: parent.modelData
                                meterActive: root.active && root.currentTab === 1
                                title: AudioState.displayName(parent.modelData)
                                subtitle: AudioState.streamDetail(parent.modelData)
                            }
                        }
                    }

                    EmptyNote {
                        visible: AudioState.outputStreams.length === 0
                        text: "No apps are playing audio."
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // -------------------------------------------------- Input tab
            TabScroll {
                id: inputScroll

                ColumnLayout {
                    width: inputScroll.availableWidth
                    spacing: 10

                    VolumeRow {
                        Layout.fillWidth: true
                        node: AudioState.defaultSource
                        large: true
                        micIcon: true
                        meterActive: root.active && root.currentTab === 2
                        title: AudioState.defaultSource ? AudioState.displayName(AudioState.defaultSource) : "No input device"
                        subtitle: AudioState.defaultSource ? AudioState.describeDevice(AudioState.defaultSource) : ""
                    }

                    ChoiceRow {
                        label: "Port"
                        options: AudioState.portsForNode(AudioState.defaultSource)
                        activeName: AudioState.activePortForNode(AudioState.defaultSource)
                        onPicked: name => AudioState.setPort(AudioState.defaultSource, name)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: 1
                        color: Theme.primary
                        opacity: 0.3
                    }

                    SectionHeader {
                        label: "Input devices"
                    }

                    Repeater {
                        model: AudioState.sources
                        delegate: DeviceCard {
                            required property var modelData
                            node: modelData
                            active: AudioState.isDefaultSource(modelData)
                        }
                    }

                    EmptyNote {
                        visible: AudioState.sources.length === 0
                        text: "No input devices found."
                    }

                    SectionHeader {
                        label: "Recording"
                        visible: AudioState.inputStreams.length > 0
                    }

                    Repeater {
                        model: AudioState.inputStreams
                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: recordRow.implicitHeight + 20
                            radius: 8
                            color: Theme.surface_container_low
                            border.color: Theme.outline_variant
                            border.width: 1

                            VolumeRow {
                                id: recordRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                node: parent.modelData
                                micIcon: true
                                meterActive: root.active && root.currentTab === 2
                                title: AudioState.displayName(parent.modelData)
                                subtitle: AudioState.streamDetail(parent.modelData)
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
        }
    }
}
