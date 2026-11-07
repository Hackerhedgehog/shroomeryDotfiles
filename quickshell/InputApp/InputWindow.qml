import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import "InputLogic.js" as Logic

// Keyboard layout and mouse speed (SUPER+I), in the middle of the screen.
// Settings live in shroomery/settings/input.json (Paths.inputSettings); every
// change is written there and applied by shroomery/scripts/input.sh, which
// also keeps a block in ~/.config/hypr/input.lua so it survives a restart.
// The mouse never accelerates. With "Scale with monitor" the speed is the one
// on a 1080p screen at scale 1 and each monitor gets it times its logical
// height / 1080 (listeners/input-speed.sh switches it as the cursor moves).
CenterPanel {
    id: root
    ipcTarget: "input"
    cardWidth: 820
    cardHeight: 600

    property var settings: Logic.DEFAULTS
    // input.sh info: the focused monitor, its factor, the speed in effect.
    property var info: null
    property var layouts: []
    // Variants of the current layout: [{ code, name }].
    property var variants: []

    property string status: ""
    property string statusTone: "normal"

    readonly property int variantIndex: {
        const i = variants.findIndex(v => v.code === settings.variant);
        return i < 0 ? 0 : i + 1;
    }

    function setStatus(text, tone) {
        status = text;
        statusTone = tone;
    }

    function load(raw) {
        // Caught mid-write (truncated, not yet filled): keep what we have.
        if (raw.trim() === "")
            return;
        let parsed = {};
        try {
            parsed = JSON.parse(raw) || {};
        } catch (e) {
            console.warn("input.json: " + e);
        }
        settings = Logic.normalize(parsed);
    }

    // Write the settings and apply them (debounced: one apply per pause in a
    // slider drag).
    function save(next) {
        settings = Logic.normalize(next);
        settingsFile.setText(JSON.stringify(settings, null, 4) + "\n");
        applyDebounce.restart();
    }

    function update(key, value) {
        const next = Object.assign({}, settings);
        next[key] = value;
        save(next);
    }

    function setLayout(code) {
        if (code === settings.layout)
            return;
        const next = Object.assign({}, settings);
        next.layout = code;
        next.variant = "";
        save(next);
    }

    // Keeps the cursor's speed on this monitor the same across the flip.
    function setScaleWithMonitor(on) {
        if (on === settings.scaleWithMonitor)
            return;
        const factor = info ? info.monitorFactor : 1;
        const next = Object.assign({}, settings);
        next.scaleWithMonitor = on;
        next.speed = Logic.rebase(settings.speed, factor, on);
        save(next);
    }

    function refreshInfo() {
        infoProc.running = false;
        infoProc.running = true;
    }

    onIsOpenChanged: {
        if (isOpen) {
            setStatus("", "normal");
            refreshInfo();
            if (layouts.length === 0)
                layoutsProc.running = true;
        }
    }

    onSettingsChanged: {
        if (variantsProc.layout !== settings.layout) {
            variantsProc.layout = settings.layout;
            variantsProc.running = false;
            variantsProc.running = true;
        }
    }

    Timer {
        id: applyDebounce
        interval: 150
        onTriggered: {
            applyProc.running = false;
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        command: [Paths.inputScript, "apply"]
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            if (code === 0) {
                root.setStatus("Applied", "good");
            } else {
                const msg = applyErr.text.replace(/\x1b\[[0-9;]*m/g, "").replace(/\[ERROR\]\s*/g, "").trim();
                root.setStatus(msg !== "" ? msg : "Couldn't apply (exit " + code + ")", "error");
            }
            root.refreshInfo();
        }
    }

    Process {
        id: infoProc
        command: [Paths.inputScript, "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(this.text);
                } catch (e) {
                    root.info = null;
                    return;
                }
                // No settings file yet: show what Hyprland uses now.
                if (!root.info.settingsExist && root.info.liveLayout !== "") {
                    const next = Object.assign({}, root.settings);
                    next.layout = root.info.liveLayout.split(",")[0];
                    next.variant = root.info.liveVariant.split(",")[0];
                    root.settings = Logic.normalize(next);
                }
            }
        }
    }

    Process {
        id: layoutsProc
        command: [Paths.inputScript, "layouts"]
        stdout: StdioCollector {
            onStreamFinished: root.layouts = Logic.layoutItems(this.text)
        }
    }

    Process {
        id: variantsProc
        property string layout: ""
        command: [Paths.inputScript, "variants", layout]
        stdout: StdioCollector {
            onStreamFinished: root.variants = Logic.parseCodes(this.text)
        }
    }

    FileView {
        id: settingsFile
        path: Paths.inputSettings
        blockLoading: true
        // input.sh reads the file right after a save.
        blockWrites: true
        printErrors: false
        watchChanges: true
        onLoaded: root.load(text())
        onFileChanged: reload()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF030C)   // keyboard
            title: "Input"
            subtitle: "Keyboard layout and mouse speed"

            StatusChip {
                visible: root.status !== ""
                text: root.status
                tone: root.statusTone
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // --- KEYBOARD ---
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    SectionHeader {
                        Layout.topMargin: 0
                        label: "Keyboard layout"

                        Text {
                            text: Logic.layoutName(root.layouts, root.settings.layout)
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.maximumWidth: 200
                        }
                    }

                    PickerList {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.layouts
                        currentKey: root.settings.layout
                        placeholderText: "Search layouts"
                        emptyText: root.layouts.length === 0 ? "Loading layouts…" : "No layout matches"
                        onPicked: key => root.setLayout(key)
                    }

                    SettingRow {
                        label: "Variant"
                        FieldCombo {
                            Layout.preferredWidth: 240
                            enabled: root.variants.length > 0
                            model: ["Default"].concat(root.variants.map(v => v.name))
                            boundIndex: root.variantIndex
                            onActivated: index => root.update("variant", index === 0 ? "" : root.variants[index - 1].code)
                        }
                    }

                    FieldInput {
                        Layout.fillWidth: true
                        placeholderText: "Type here to try the layout"
                    }
                }
            }

            // --- MOUSE ---
            Card {
                Layout.preferredWidth: 330
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    SectionHeader {
                        Layout.topMargin: 0
                        label: "Mouse speed"
                    }

                    ParamRow {
                        Layout.fillWidth: true
                        label: root.settings.scaleWithMonitor ? "Speed on a 1080p screen" : "Speed"
                        from: Logic.SPEED.min
                        to: Logic.SPEED.max
                        stepSize: 0.05
                        decimals: 2
                        unit: "×"
                        value: root.settings.speed
                        onMoved: v => root.update("speed", v)
                    }

                    SettingRow {
                        label: "Scale with monitor"
                        hint: "Same hand movement to cross any screen: faster on monitors with more logical pixels, measured against 1080p at scale 1"
                        ToggleSwitch {
                            checked: root.settings.scaleWithMonitor
                            onToggled: {
                                root.setScaleWithMonitor(checked);
                                checked = Qt.binding(() => root.settings.scaleWithMonitor);
                            }
                        }
                    }

                    // What this monitor gets.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: monitorInfo.implicitHeight + 24
                        radius: 12
                        color: Theme.surface_container_high
                        visible: root.info !== null && root.info.monitor !== ""

                        ColumnLayout {
                            id: monitorInfo
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                text: Logic.describeMonitor(root.info)
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: root.settings.scaleWithMonitor
                                text: root.info ? "Gets " + Logic.formatSpeed(root.info.monitorFactor) + " the 1080p speed" : ""
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.info ? "Speed now: " + Logic.formatSpeed(root.info.speed) : ""
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        text: "No acceleration: the same hand movement always moves the cursor the same distance."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
