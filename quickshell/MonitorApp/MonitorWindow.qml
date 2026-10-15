import Quickshell
import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls
import qs.shared
import qs.shared.ui
import qs.MonitorApp

// Display settings, in the middle of the screen: the arrangement canvas on
// the left (drag to move, click to select), the selected display's settings
// on the right, the default rule and switched-off displays as chips under
// the canvas, and Revert / Apply / Save at the bottom. Layout profiles live
// in the header's Profiles menu.
CenterPanel {
    id: root
    ipcTarget: "monitors"
    cardWidth: 1000
    cardHeight: 660
    escapeHandler: function () {
        if (root.promptKind !== "") {
            root.promptKind = "";
            return true;
        }
        if (root.propertiesOpen) {
            root.propertiesOpen = false;
            return true;
        }
        return false;
    }

    property string promptKind: ""
    property string promptTitle: ""
    property string promptLabel: ""
    property string promptSeed: ""
    property bool propertiesOpen: false

    readonly property bool canEdit: !MonitorState.busy && MonitorState.selected !== null && !MonitorState.selected.disabled

    readonly property string activeProfileName: {
        const list = MonitorState.profiles;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === MonitorState.activeProfileId)
                return list[i].name;
        }
        return "";
    }

    onIsOpenChanged: {
        if (isOpen) {
            promptKind = "";
            propertiesOpen = false;
            MonitorState.refresh();
        }
    }

    function openPrompt(kind, title, label, seed) {
        promptKind = kind;
        promptTitle = title;
        promptLabel = label;
        promptSeed = seed;
        promptField.text = seed;
        promptField.forceActiveFocus();
    }

    function commitPrompt() {
        const value = promptField.text.trim();
        const kind = promptKind;
        promptKind = "";
        if (value === "")
            return;
        if (kind === "scale") {
            const n = parseFloat(value);
            if (n > 0)
                MonitorState.setScale(n);
        } else if (kind === "profile") {
            MonitorState.saveProfileAs(value);
        } else if (kind === "defaultMode") {
            MonitorState.setDefaultRuleField("mode", value);
        } else if (kind === "defaultPosition") {
            MonitorState.setDefaultRuleField("position", value);
        } else if (kind === "defaultScale") {
            MonitorState.setDefaultRuleField("scale", value);
        }
    }

    // A selectable pill under the canvas (default rule, a switched-off display).
    component Chip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property string detail: ""
        property bool picked: false
        signal clicked()
        default property alias trailing: chipTrailing.data

        implicitHeight: 44
        implicitWidth: chipRow.implicitWidth + 28
        radius: 22
        color: picked ? Theme.primary_container : (chipHover.hovered ? Theme.surface_container_highest : Theme.surface_container_high)
        Behavior on color { ColorAnimation { duration: 150 } }

        HoverHandler {
            id: chipHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: chip.clicked()
        }

        RowLayout {
            id: chipRow
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            spacing: 10

            Text {
                text: chip.glyph
                color: chip.picked ? Theme.on_primary_container : Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: chip.label
                    color: chip.picked ? Theme.on_primary_container : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    visible: text !== ""
                    text: chip.detail
                    color: chip.picked ? Theme.on_primary_container : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Layout.maximumWidth: 220
                    elide: Text.ElideRight
                }
            }
            RowLayout {
                id: chipTrailing
                spacing: 6
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF037A)   // monitor-multiple
            title: "Displays"
            subtitle: "Arrangement, mode and scale"

            PanelButton {
                id: profilesButton
                compact: true
                glyph: String.fromCodePoint(0xF00C3)   // bookmark-outline
                text: root.activeProfileName !== "" ? root.activeProfileName : "Profiles"
                onClicked: profileMenu.open()

                PanelMenu {
                    id: profileMenu
                    implicitWidth: 260

                    Instantiator {
                        model: MonitorState.profiles
                        delegate: MenuEntry {
                            required property var modelData
                            text: (MonitorState.activeProfileId === modelData.id ? "✓  " : "     ") + modelData.name
                            onTriggered: MonitorState.applyProfile(modelData.id)
                        }
                        onObjectAdded: (index, object) => profileMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => profileMenu.removeItem(object)
                    }

                    MenuEntry {
                        text: "Save current layout…"
                        onTriggered: root.openPrompt("profile", "Save layout profile", "Profile name", "")
                    }
                }
            }

            ActionIcon {
                implicitWidth: 34
                implicitHeight: 34
                iconTxt: String.fromCodePoint(0xF0450)   // refresh
                iconPixelSize: 18
                enabled: !MonitorState.busy
                onClicked: MonitorState.refresh()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Re-read the displays from Hyprland"
            }
        }

        // Error, or no monitors.lua yet.
        Rectangle {
            Layout.fillWidth: true
            visible: MonitorState.errorMessage !== "" || MonitorState.configMissing
            implicitHeight: bannerText.implicitHeight + 20
            radius: 12
            color: MonitorState.errorMessage !== "" ? Theme.error_container : Theme.tertiary_container

            Text {
                id: bannerText
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                text: MonitorState.errorMessage !== "" ? MonitorState.errorMessage
                    : "No monitors config yet — Save will create " + Paths.hyprMonitors
                color: MonitorState.errorMessage !== "" ? Theme.on_error_container : Theme.on_tertiary_container
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // --- Left: arrangement + chips ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                ArrangementCanvas {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        visible: parent.names.length > 0
                        text: "Drag to arrange · click to select"
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        opacity: 0.8
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Chip {
                        glyph: String.fromCodePoint(0xF062E)   // tune
                        label: "Default rule"
                        detail: MonitorState.defaultRule.mode + " · " + MonitorState.defaultRule.position
                        picked: MonitorState.defaultRuleSelected
                        onClicked: MonitorState.selectDefaultRule()
                    }

                    // Disabled outputs are not drawn on the canvas (Hyprland
                    // gives them no size or position), so they are chips here.
                    Repeater {
                        model: MonitorState.disabledMonitors

                        delegate: Chip {
                            id: offChip
                            required property var modelData
                            glyph: String.fromCodePoint(0xF0D90)   // monitor-off
                            label: modelData.name
                            detail: modelData.description !== "" ? modelData.description : "Off"
                            picked: !MonitorState.defaultRuleSelected && MonitorState.selectedName === modelData.name
                            onClicked: MonitorState.select(modelData.name)

                            PanelButton {
                                compact: true
                                tonal: !offChip.picked
                                filled: offChip.picked
                                text: "Enable"
                                enabled: !MonitorState.busy
                                onClicked: {
                                    MonitorState.select(offChip.modelData.name);
                                    MonitorState.setEnabled(true);
                                }
                            }
                        }
                    }
                }
            }

            // --- Right: settings of the selection ---
            Card {
                Layout.preferredWidth: 360
                Layout.fillHeight: true

                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    anchors.margins: 18
                    clip: true
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: settingsFlick.contentHeight > settingsFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: settingsColumn
                        width: settingsFlick.width
                        spacing: 14

                        // Nothing selected.
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 40
                            visible: !MonitorState.defaultRuleSelected && MonitorState.selected === null
                            horizontalAlignment: Text.AlignHCenter
                            text: "Select a display to change it"
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                        }

                        // --- One display ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            visible: !MonitorState.defaultRuleSelected && MonitorState.selected !== null

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: MonitorState.selected ? MonitorState.selected.name : ""
                                        color: Theme.on_surface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 18
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: MonitorState.selected ? MonitorState.selected.description : ""
                                        color: Theme.on_surface_variant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                ActionIcon {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    iconTxt: String.fromCodePoint(0xF02FD)   // information-outline
                                    iconPixelSize: 18
                                    onClicked: root.propertiesOpen = true
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 500
                                    ToolTip.text: "All properties"
                                }
                            }

                            SettingRow {
                                label: "Enabled"
                                ToggleSwitch {
                                    checked: MonitorState.selected ? !MonitorState.selected.disabled : false
                                    enabled: !MonitorState.busy
                                    onClicked: MonitorState.setEnabled(checked)
                                }
                            }

                            // A switched-off output cannot be primary.
                            SettingRow {
                                id: primaryRow
                                readonly property string monName: MonitorState.selected ? MonitorState.selected.name : ""
                                readonly property bool picked: monName !== "" && MonitorState.draftPrimary === monName
                                readonly property bool live: monName !== "" && MonitorState.primaryName === monName

                                visible: MonitorState.selected !== null && !MonitorState.selected.disabled
                                label: "Primary"

                                StatusChip {
                                    visible: primaryRow.picked
                                    text: primaryRow.live ? "Primary" : "On apply"
                                    tone: primaryRow.live ? "good" : "busy"
                                }
                                PanelButton {
                                    visible: !primaryRow.picked
                                    compact: true
                                    text: "Make primary"
                                    enabled: !MonitorState.busy
                                    onClicked: MonitorState.setPrimary(primaryRow.monName)
                                }
                            }

                            SettingRow {
                                label: "Resolution"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.resolutionModel
                                    boundIndex: MonitorState.resolutionIndex
                                    enabled: root.canEdit
                                    onActivated: index => MonitorState.setResolution(MonitorState.resolutionModel[index])
                                }
                            }

                            SettingRow {
                                label: "Refresh rate"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.refreshLabels
                                    boundIndex: MonitorState.refreshIndex
                                    enabled: root.canEdit
                                    onActivated: index => MonitorState.setRefreshByIndex(index)
                                }
                            }

                            SettingRow {
                                label: "Scale"
                                hint: "Needs a whole-pixel size"
                                FieldCombo {
                                    id: scaleCombo
                                    Layout.preferredWidth: 170
                                    model: MonitorState.scaleModel
                                    boundIndex: MonitorState.scaleIndex
                                    enabled: root.canEdit
                                    onActivated: index => {
                                        if (!MonitorState.setScaleByIndex(index)) {
                                            syncIndex();
                                            root.openPrompt("scale", "Custom scale", "Scale", MonitorState.selected ? MonitorState.formatScale(MonitorState.selected.scale) : "1");
                                        }
                                    }
                                }
                            }

                            SettingRow {
                                label: "Rotation"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.transformLabels
                                    boundIndex: MonitorState.selected ? MonitorState.selected.transform : 0
                                    enabled: root.canEdit
                                    onActivated: index => MonitorState.setTransform(index)
                                }
                            }

                            SettingRow {
                                label: "Mirror of"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.mirrorLabels
                                    boundIndex: MonitorState.mirrorIndex
                                    enabled: root.canEdit
                                    onActivated: index => MonitorState.setMirrorByIndex(index)
                                }
                            }
                        }

                        // --- Default rule ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            visible: MonitorState.defaultRuleSelected

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Default rule"
                                    color: Theme.on_surface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Used by any display without a rule of its own"
                                    color: Theme.on_surface_variant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }

                            SettingRow {
                                label: "Mode"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.defaultModeModel
                                    boundIndex: MonitorState.defaultModeIndex
                                    enabled: !MonitorState.busy
                                    onActivated: index => {
                                        const items = MonitorState.defaultModeModel;
                                        if (items[index] === "Custom…") {
                                            root.openPrompt("defaultMode", "Custom mode", "Mode", MonitorState.defaultRule.mode);
                                            return;
                                        }
                                        MonitorState.setDefaultRuleField("mode", items[index]);
                                    }
                                }
                            }

                            SettingRow {
                                label: "Position"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.defaultPositionModel
                                    boundIndex: MonitorState.defaultPositionIndex
                                    enabled: !MonitorState.busy
                                    onActivated: index => {
                                        const items = MonitorState.defaultPositionModel;
                                        if (items[index] === "Custom…") {
                                            root.openPrompt("defaultPosition", "Custom position", "Position", MonitorState.defaultRule.position);
                                            return;
                                        }
                                        MonitorState.setDefaultRuleField("position", items[index]);
                                    }
                                }
                            }

                            SettingRow {
                                label: "Scale"
                                FieldCombo {
                                    Layout.preferredWidth: 170
                                    model: MonitorState.defaultScaleModel
                                    boundIndex: MonitorState.defaultScaleIndex
                                    enabled: !MonitorState.busy
                                    onActivated: index => {
                                        const items = MonitorState.defaultScaleModel;
                                        if (items[index] === "Custom…") {
                                            root.openPrompt("defaultScale", "Custom scale", "Scale", String(MonitorState.defaultRule.scale));
                                            return;
                                        }
                                        MonitorState.setDefaultRuleField("scale", items[index]);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Footer ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: MonitorState.statusText
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            PanelButton {
                text: "Revert"
                glyph: String.fromCodePoint(0xF054C)   // undo
                enabled: MonitorState.isDirty && !MonitorState.busy
                onClicked: MonitorState.revert()
            }
            PanelButton {
                text: "Apply"
                glyph: String.fromCodePoint(0xF012C)   // check
                tonal: true
                enabled: MonitorState.isDirty && !MonitorState.busy
                onClicked: MonitorState.apply()
            }
            PanelButton {
                text: "Save"
                glyph: String.fromCodePoint(0xF0193)   // content-save
                filled: true
                enabled: MonitorState.canSave && !MonitorState.busy
                onClicked: MonitorState.save()
            }
        }
    }

    // --- Dialogs: scrim, text prompt, properties ---

    Rectangle {
        anchors.fill: parent
        visible: root.promptKind !== "" || root.propertiesOpen
        color: Qt.rgba(Theme.scrim.r, Theme.scrim.g, Theme.scrim.b, 0.5)
        radius: 24
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.promptKind = "";
                root.propertiesOpen = false;
            }
        }
    }

    Card {
        visible: root.promptKind !== ""
        anchors.centerIn: parent
        width: 400
        implicitHeight: promptColumn.implicitHeight + 40
        radius: 20

        ColumnLayout {
            id: promptColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: root.promptTitle
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
            }
            FieldLabel {
                text: root.promptLabel
            }
            FieldInput {
                id: promptField
                Layout.fillWidth: true
                Keys.onReturnPressed: root.commitPrompt()
                Keys.onEnterPressed: root.commitPrompt()
                Keys.onEscapePressed: root.promptKind = ""
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Item {
                    Layout.fillWidth: true
                }
                PanelButton {
                    text: "Cancel"
                    onClicked: root.promptKind = ""
                }
                PanelButton {
                    text: "Use"
                    filled: true
                    onClicked: root.commitPrompt()
                }
            }
        }
    }

    Card {
        visible: root.propertiesOpen && MonitorState.selected !== null
        anchors.centerIn: parent
        width: 560
        height: Math.min(parent.height - 80, propertiesColumn.implicitHeight + 40)
        radius: 20
        clip: true

        ColumnLayout {
            id: propertiesColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: MonitorState.selected ? MonitorState.selected.name : "Properties"
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                }
                ActionIcon {
                    implicitWidth: 32
                    implicitHeight: 32
                    iconTxt: String.fromCodePoint(0xF0156)   // close
                    iconPixelSize: 18
                    onClicked: root.propertiesOpen = false
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: {
                    const m = MonitorState.selected;
                    if (!m)
                        return [];
                    const modes = (m.availableModes || []).map(mode => mode.width + "x" + mode.height + "@" + MonitorState.formatRefresh(mode.refreshRate)).join(", ");
                    return [
                        { k: "Connector", v: m.name },
                        { k: "Make", v: m.make || "—" },
                        { k: "Model", v: m.model || "—" },
                        { k: "Serial", v: m.serial || "—" },
                        { k: "Description", v: m.description || "—" },
                        { k: "Mode", v: m.width + "x" + m.height + "@" + MonitorState.formatRefresh(m.refreshRate) },
                        { k: "Position", v: m.x + "x" + m.y },
                        { k: "Layout size", v: MonitorState.layoutWidth(m) + "x" + MonitorState.layoutHeight(m) },
                        { k: "Scale", v: MonitorState.formatScale(m.scale) },
                        { k: "Rotation", v: MonitorState.transformLabels[m.transform] || String(m.transform) },
                        { k: "Mirror of", v: m.mirrorOf || "—" },
                        { k: "Enabled", v: m.disabled ? "no" : "yes" },
                        { k: "DPMS", v: m.dpmsStatus ? "on" : "off" },
                        { k: "VRR", v: m.vrr ? "on" : "off" },
                        { k: "Focused", v: m.focused ? "yes" : "no" },
                        { k: "Primary", v: MonitorState.primaryName === m.name ? "yes" : (MonitorState.draftPrimary === m.name ? "on apply" : "no") },
                        { k: "Available modes", v: modes || "—" }
                    ];
                }
                spacing: 8
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 12
                    Text {
                        Layout.preferredWidth: 120
                        Layout.alignment: Qt.AlignTop
                        text: modelData.k
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.v
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
