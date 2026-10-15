import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.VisualizerApp
import "VisualizerLogic.js" as Logic

// Visualizer setup (Super+Alt+V): style, look and placement with a live
// preview. Start saves the settings and starts visualizer mode; Esc, an
// outside click or Super+Alt+V close it without saving.
CenterPanel {
    id: root
    ipcTarget: "visualizer-setup"
    cardWidth: 900
    cardHeight: 640

    // Working copy of the settings, written to visualizer.json on Start.
    property var work: Logic.normalizeSettings({})
    function set(changes) {
        work = Logic.normalizeSettings(Object.assign({}, work, changes));
    }
    function one(key, value) {
        const c = {};
        c[key] = value;
        set(c);
    }

    readonly property var screens: Array.from(Quickshell.screens)
    readonly property var screenNames: screens.map(s => s.name)
    readonly property var chosen: screens.find(s => s.name === work.monitor) ?? screens[0]

    // VisualizerState.setupOpen <-> this panel's open state.
    Connections {
        target: VisualizerState
        function onSetupOpenChanged() {
            if (VisualizerState.setupOpen && !root.isOpen)
                root.open();
            else if (!VisualizerState.setupOpen && root.isOpen)
                root.close();
        }
    }
    onIsOpenChanged: {
        if (isOpen) {
            const w = Object.assign({}, VisualizerState.cfg);
            w.monitor = Logic.pickMonitor(w.monitor, screenNames,
                Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
            work = Logic.normalizeSettings(w);
        }
        if (VisualizerState.setupOpen !== isOpen)
            VisualizerState.setupOpen = isOpen;
    }

    CavaSpectrum {
        id: preview
        barCount: 96
        framerate: 30
        active: root.isOpen
    }

    component Choice: PanelButton {
        property string value
        property string current
        compact: true
        filled: value === current
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF0387)   // md-music_note
            title: "Visualizer"
            subtitle: "Audio visualizer over what's playing"

            StatusChip {
                text: VisualizerState.active ? "Running on " + VisualizerState.monitorName : "Off"
                tone: VisualizerState.active ? "good" : "normal"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 12

                MiniScreen {
                    live: root.isOpen
                    monitor: root.work.monitor
                    cfg: root.work
                    screenW: root.chosen ? root.chosen.width : 1920
                    screenH: root.chosen ? root.chosen.height : 1080
                    bars: preview.bars
                    onEdited: changes => root.set(changes)
                }

                SettingRow {
                    Layout.fillWidth: true
                    label: "Monitor"
                    FieldCombo {
                        Layout.preferredWidth: 160
                        model: root.screenNames
                        boundIndex: Math.max(0, root.screenNames.indexOf(root.work.monitor))
                        onActivated: index => root.one("monitor", root.screenNames[index])
                    }
                }

                PanelButton {
                    Layout.alignment: Qt.AlignRight
                    text: "Start"
                    glyph: String.fromCodePoint(0xF040A)   // md-play
                    filled: true
                    onClicked: VisualizerState.start(root.work)
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: 12

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: styleCol.implicitHeight + 28
                        ColumnLayout {
                            id: styleCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8
                            FieldLabel { text: "Style" }
                            RowLayout {
                                spacing: 6
                                Repeater {
                                    model: [{ v: "center-out", t: "Center out" }, { v: "center-in", t: "Center in" }, { v: "border", t: "Border" }]
                                    delegate: Choice {
                                        required property var modelData
                                        value: modelData.v
                                        current: root.work.style
                                        text: modelData.t
                                        onClicked: root.one("style", value)
                                    }
                                }
                            }
                            RowLayout {
                                spacing: 6
                                Repeater {
                                    model: [{ v: "bars", t: "Bars" }, { v: "wave", t: "Wave" }, { v: "line", t: "Line" }]
                                    delegate: Choice {
                                        required property var modelData
                                        value: modelData.v
                                        current: root.work.draw
                                        text: modelData.t
                                        onClicked: root.one("draw", value)
                                    }
                                }
                            }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: lookCol.implicitHeight + 28
                        ColumnLayout {
                            id: lookCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6
                            FieldLabel { text: "Look" }
                            ParamRow { Layout.fillWidth: true; label: "Bar width"; unit: "px"; decimals: 0; from: 1; to: 12; stepSize: 1; value: root.work.barWidth; onMoved: v => root.one("barWidth", Math.round(v)) }
                            ParamRow { Layout.fillWidth: true; label: "Spacing"; unit: "px"; decimals: 0; from: 0; to: 12; stepSize: 1; value: root.work.barSpacing; onMoved: v => root.one("barSpacing", Math.round(v)) }
                            ParamRow { Layout.fillWidth: true; enabled: root.work.draw === "line"; opacity: enabled ? 1 : 0.45; label: "Line thickness"; unit: "px"; decimals: 0; from: 1; to: 8; stepSize: 1; value: root.work.lineWidth; onMoved: v => root.one("lineWidth", Math.round(v)) }
                            ParamRow { Layout.fillWidth: true; label: "Minimum length"; unit: "px"; decimals: 0; from: 0; to: 40; stepSize: 1; value: root.work.minLength; onMoved: v => root.one("minLength", Math.round(v)) }
                            ParamRow { Layout.fillWidth: true; label: "Sensitivity"; unit: "%"; decimals: 0; from: 50; to: 200; stepSize: 5; value: root.work.sensitivity * 100; onMoved: v => root.one("sensitivity", Math.round(v) / 100) }
                            ParamRow { Layout.fillWidth: true; label: "Smoothness"; unit: "%"; decimals: 0; from: 0; to: 100; stepSize: 5; value: root.work.smoothness * 100; onMoved: v => root.one("smoothness", Math.round(v) / 100) }
                            ParamRow { Layout.fillWidth: true; label: "Outline (0 = off)"; unit: "px"; decimals: 1; from: 0; to: 6; stepSize: 0.5; value: root.work.outline; onMoved: v => root.one("outline", Math.round(v * 2) / 2) }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: colorsCol.implicitHeight + 28
                        ColumnLayout {
                            id: colorsCol
                            anchors.fill: parent
                            anchors.margins: 14
                            FieldLabel { text: "Colors" }
                            SettingRow {
                                Layout.fillWidth: true
                                label: "Wallpaper only"
                                hint: "Ignore windows; take colors from the wallpaper"
                                ToggleSwitch {
                                    checked: root.work.wallpaperOnly
                                    onToggled: {
                                        root.one("wallpaperOnly", checked)
                                        checked = Qt.binding(() => root.work.wallpaperOnly)
                                    }
                                }
                            }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: controllerCol.implicitHeight + 28
                        ColumnLayout {
                            id: controllerCol
                            anchors.fill: parent
                            anchors.margins: 14
                            FieldLabel { text: "Controller" }
                            SettingRow {
                                Layout.fillWidth: true
                                label: "Protocol"
                                hint: "LED controller support isn't built yet."
                                FieldCombo {
                                    Layout.preferredWidth: 140
                                    enabled: false
                                    model: ["WebSocket", "UDP (DDP)", "Serial"]
                                }
                                PanelButton { compact: true; enabled: false; text: "Connect" }
                            }
                        }
                    }
                }
            }
        }
    }
}
