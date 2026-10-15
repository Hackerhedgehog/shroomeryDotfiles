import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.shared
import qs.shared.ui
import qs.KeybindsApp
import "KeybindsLogic.js" as Logic

// Keybinds, in the middle of the screen: search and New keybind in the header,
// the sections of keybindings.lua on the left (click to filter; hover for
// rename / delete; New section at the bottom) and the binds on the right.
//
// Left click a bind (or Return) opens the editor and starts recording its new
// shortcut (keys, a mouse button or the wheel, with modifiers); description,
// command and section can be changed there too. When another bind already uses
// the shortcut the editor says so and offers Cancel, Clear other or Keep both.
// Right click (or Ctrl+Return) runs the bind's command. Up/Down/PageUp/PageDown
// move the selection. Every change is written to keybindings.lua (KeybindsState).
CenterPanel {
    id: root
    ipcTarget: "keybinds"
    cardWidth: 1060
    cardHeight: 720
    escapeHandler: function () {
        if (KeybindsState.recording) {
            KeybindsState.stopRecording();
            return true;
        }
        if (KeybindsState.editorOpen) {
            if (!KeybindsState.saving)
                KeybindsState.closeEditor();
            return true;
        }
        if (root.deletingSection !== "") {
            root.deletingSection = "";
            return true;
        }
        if (root.renamingSection !== "" || root.addingSection) {
            root.renamingSection = "";
            root.addingSection = false;
            search.focusField();
            return true;
        }
        if (KeybindsState.query !== "") {
            search.text = "";
            return true;
        }
        if (KeybindsState.section !== "") {
            KeybindsState.section = "";
            return true;
        }
        return false;
    }

    property int selectedIndex: 0
    readonly property var selectedBind: {
        const rows = KeybindsState.rows;
        return selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex].bind : null;
    }

    // Sidebar state: the section being renamed inline, whether the "new
    // section" field shows, and the section the delete dialog is about.
    property string renamingSection: ""
    property bool addingSection: false
    property string deletingSection: ""

    readonly property var sectionItems: [{ "label": "", "name": "All shortcuts", "count": KeybindsState.count, "editable": false }]
        .concat(KeybindsState.sections.map(s => ({
            "label": s.label,
            "name": s.label,
            "count": s.binds.length,
            "editable": s.offset >= 0
        })))
    readonly property var sectionLabels: KeybindsState.sections.map(s => s.label)

    readonly property string subtitle: {
        if (KeybindsState.banner !== "")
            return KeybindsState.banner;
        if (KeybindsState.errorMessage !== "")
            return KeybindsState.errorMessage;
        return "Left click a shortcut to change it, right click to run it";
    }

    onIsOpenChanged: {
        if (isOpen) {
            KeybindsState.panelOpen = true;
            search.text = "";
            KeybindsState.section = "";
            selectedIndex = 0;
            renamingSection = "";
            addingSection = false;
            deletingSection = "";
            KeybindsState.refresh();
            search.focusField();
        } else {
            KeybindsState.closeEditor();
            KeybindsState.panelOpen = false;
            search.text = "";
        }
    }

    onSelectedIndexChanged: Qt.callLater(() => bindList.positionViewAtIndex(selectedIndex, ListView.Contain))

    Connections {
        target: KeybindsState
        function onQueryChanged() { root.selectedIndex = 0; }
        function onSectionChanged() { root.selectedIndex = 0; }
        function onRowsChanged() {
            root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, KeybindsState.rows.length - 1));
        }
        function onEditorOpenChanged() {
            if (KeybindsState.editorOpen)
                editor.load();
            else
                search.focusField();
        }
        function onRecordingChanged() {
            if (KeybindsState.recording)
                keyCatcher.forceActiveFocus();
        }
    }

    function runBind(bind) {
        if (KeybindsState.run(bind))
            root.close();
        else
            KeybindsState.notify(bind && bind.mouse ? "Mouse drag binds only work with the mouse" : "This bind has nothing that can be run from here", true);
    }

    function moveSelection(step) {
        const count = KeybindsState.rows.length;
        if (count > 0)
            selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + step));
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down)
            moveSelection(1);
        else if (event.key === Qt.Key_Up)
            moveSelection(-1);
        else if (event.key === Qt.Key_PageDown)
            moveSelection(8);
        else if (event.key === Qt.Key_PageUp)
            moveSelection(-8);
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ctrl)
            runBind(selectedBind);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            KeybindsState.openEditor(selectedBind);
        else
            return;
        event.accepted = true;
    }

    // A combo as key caps: modifiers in a neutral tone, the key in primary.
    component KeyCaps: Row {
        id: caps
        property var chips: []
        property bool unbound: false
        property int pixelSize: 11
        readonly property int capHeight: Math.round(pixelSize * 2.4)

        spacing: Math.round(pixelSize * 0.4)

        Repeater {
            model: caps.unbound ? [] : caps.chips
            delegate: Rectangle {
                id: cap
                required property var modelData
                required property int index
                readonly property bool isKey: index === caps.chips.length - 1
                width: Math.max(caps.capHeight, capText.implicitWidth + caps.pixelSize * 1.4)
                height: caps.capHeight
                radius: Math.round(caps.capHeight * 0.3)
                color: isKey ? Theme.primary_container : Theme.surface_container_highest
                // A darker bottom edge, like a key.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.radius
                    radius: parent.radius
                    color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.18)
                    z: -1
                    anchors.bottomMargin: -2
                }
                Text {
                    id: capText
                    anchors.centerIn: parent
                    text: cap.modelData
                    color: cap.isKey ? Theme.on_primary_container : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: caps.pixelSize
                    font.bold: true
                }
            }
        }

        Rectangle {
            visible: caps.unbound
            width: unboundText.implicitWidth + caps.pixelSize * 1.6
            height: caps.capHeight
            radius: Math.round(caps.capHeight * 0.3)
            color: "transparent"
            border.color: Theme.outline_variant
            border.width: 1
            Text {
                id: unboundText
                anchors.centerIn: parent
                text: "Not bound"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: caps.pixelSize
                font.italic: true
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF030C)   // keyboard
            title: "Keybinds"
            subtitle: root.subtitle
            subtitleColor: (KeybindsState.banner !== "" ? KeybindsState.bannerError : KeybindsState.errorMessage !== "")
                ? Theme.error : Theme.on_surface_variant

            SearchField {
                id: search
                Layout.preferredWidth: 300
                placeholderText: "Search keys, actions or commands"
                onTextChanged: KeybindsState.query = text
                onKeyPressed: event => root.handleKey(event)
            }

            PanelButton {
                text: "New keybind"
                glyph: String.fromCodePoint(0xF0415)   // plus
                filled: true
                focusPolicy: Qt.NoFocus
                enabled: KeybindsState.count > 0 || KeybindsState.sections.length > 0
                onClicked: KeybindsState.newBind()
            }

            StatusChip {
                text: KeybindsState.statusLabel
                tone: KeybindsState.statusLabel === "Unavailable" ? "error"
                    : (KeybindsState.refreshing ? "busy" : "normal")
            }

            ActionIcon {
                implicitWidth: 34
                implicitHeight: 34
                iconTxt: String.fromCodePoint(0xF0450)   // refresh
                iconPixelSize: 18
                onClicked: KeybindsState.refresh()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Read keybindings.lua again"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // --- Sections + mouse legend ---
            Card {
                Layout.preferredWidth: 250
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    FieldLabel {
                        Layout.leftMargin: 6
                        text: "Sections"
                    }

                    ListView {
                        id: sectionList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.sectionItems
                        ScrollBar.vertical: ScrollBar {
                            policy: sectionList.contentHeight > sectionList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        }

                        delegate: Rectangle {
                            id: sectionRow
                            required property var modelData
                            readonly property bool selected: KeybindsState.section === modelData.label
                            readonly property bool renaming: root.renamingSection !== "" && root.renamingSection === modelData.label
                            width: ListView.view.width
                            height: 36
                            radius: 18
                            color: selected && !renaming ? Theme.primary_container
                                : (sectionHover.hovered && !renaming ? Theme.surface_container_high : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler {
                                id: sectionHover
                                cursorShape: sectionRow.renaming ? Qt.IBeamCursor : Qt.PointingHandCursor
                            }
                            TapHandler {
                                enabled: !sectionRow.renaming
                                onTapped: {
                                    KeybindsState.section = sectionRow.modelData.label;
                                    search.focusField();
                                }
                            }

                            RowLayout {
                                visible: !sectionRow.renaming
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 8
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: sectionRow.modelData.name
                                    color: sectionRow.selected ? Theme.on_primary_container : Theme.on_surface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                // Rename / delete on hover, the bind count otherwise.
                                ActionIcon {
                                    visible: sectionHover.hovered && sectionRow.modelData.editable
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    iconTxt: String.fromCodePoint(0xF03EB)   // pencil
                                    iconPixelSize: 14
                                    iconColor: sectionRow.selected ? Theme.on_primary_container : Theme.on_surface_variant
                                    focusPolicy: Qt.NoFocus
                                    onClicked: {
                                        root.addingSection = false;
                                        root.renamingSection = sectionRow.modelData.label;
                                    }
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 500
                                    ToolTip.text: "Rename section"
                                }
                                ActionIcon {
                                    visible: sectionHover.hovered && sectionRow.modelData.editable
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    iconTxt: String.fromCodePoint(0xF01B4)   // delete
                                    iconPixelSize: 14
                                    iconColor: sectionRow.selected ? Theme.on_primary_container : Theme.on_surface_variant
                                    focusPolicy: Qt.NoFocus
                                    onClicked: root.deletingSection = sectionRow.modelData.label
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 500
                                    ToolTip.text: "Delete section"
                                }
                                Text {
                                    visible: !(sectionHover.hovered && sectionRow.modelData.editable)
                                    Layout.rightMargin: 4
                                    text: sectionRow.modelData.count
                                    color: sectionRow.selected ? Theme.on_primary_container : Theme.on_surface_variant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // Inline rename: Return saves, Escape or leaving the field cancels.
                            FieldInput {
                                id: renameField
                                visible: sectionRow.renaming
                                anchors.fill: parent
                                implicitHeight: 36
                                onVisibleChanged: {
                                    if (visible) {
                                        text = sectionRow.modelData.label;
                                        forceActiveFocus();
                                        selectAll();
                                    }
                                }
                                onAccepted: {
                                    KeybindsState.renameSection(sectionRow.modelData.label, text);
                                    root.renamingSection = "";
                                }
                                onActiveFocusChanged: if (!activeFocus && sectionRow.renaming) root.renamingSection = ""
                            }

                            ToolTip.visible: sectionHover.hovered && !renaming && sectionRow.modelData.name.length > 22
                            ToolTip.delay: 600
                            ToolTip.text: sectionRow.modelData.name
                        }
                    }

                    // New section: a button that turns into a name field.
                    PanelButton {
                        Layout.fillWidth: true
                        visible: !root.addingSection
                        compact: true
                        text: "New section"
                        glyph: String.fromCodePoint(0xF0415)   // plus
                        focusPolicy: Qt.NoFocus
                        enabled: !KeybindsState.saving
                        onClicked: {
                            root.renamingSection = "";
                            root.addingSection = true;
                            newSectionField.text = "";
                            newSectionField.forceActiveFocus();
                        }
                    }
                    FieldInput {
                        id: newSectionField
                        Layout.fillWidth: true
                        visible: root.addingSection
                        placeholderText: "Section name, then Return"
                        onAccepted: {
                            KeybindsState.addSection(text);
                            root.addingSection = false;
                            search.focusField();
                        }
                        onActiveFocusChanged: if (!activeFocus) root.addingSection = false
                    }

                    // How to use the list.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: legend.implicitHeight + 24
                        radius: 12
                        color: Theme.surface_container_high

                        ColumnLayout {
                            id: legend
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 14
                            spacing: 8

                            Repeater {
                                model: [
                                    { "glyph": 0xF03EB, "label": "Edit, record shortcut", "hint": "Left click · Return" },   // pencil
                                    { "glyph": 0xF040A, "label": "Run it now", "hint": "Right click · Ctrl+Return" }    // play
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: String.fromCodePoint(parent.modelData.glyph)
                                        color: Theme.primary
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 16
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: parent.parent.modelData.label
                                            color: Theme.on_surface
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: parent.parent.modelData.hint
                                            color: Theme.on_surface_variant
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- Binds ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: bindList
                    anchors.fill: parent
                    anchors.rightMargin: -8
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: KeybindsState.rows
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: false
                    ScrollBar.vertical: ScrollBar {
                        policy: bindList.contentHeight > bindList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var bind: modelData.bind
                        readonly property bool selected: root.selectedIndex === index
                        readonly property int headerHeight: modelData.header !== "" ? (index === 0 ? 30 : 40) : 0

                        width: ListView.view.width - 14
                        height: headerHeight + tile.height

                        Text {
                            visible: row.headerHeight > 0
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: tile.top
                            anchors.bottomMargin: 8
                            anchors.leftMargin: 4
                            text: row.modelData.header
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: tile
                            y: row.headerHeight
                            width: parent.width
                            height: 58
                            radius: 14
                            color: tileMouse.containsMouse ? Theme.surface_container_high : Theme.surface_container
                            border.color: row.selected ? Theme.primary : Theme.outline_variant
                            border.width: row.selected ? 2 : 1
                            opacity: row.bind.unbound ? 0.8 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    root.selectedIndex = row.index;
                                    if (mouse.button === Qt.RightButton)
                                        root.runBind(row.bind);
                                    else
                                        KeybindsState.openEditor(row.bind);
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 14

                                Item {
                                    Layout.preferredWidth: 190
                                    Layout.fillHeight: true
                                    clip: true
                                    KeyCaps {
                                        anchors.verticalCenter: parent.verticalCenter
                                        chips: Logic.chips(row.bind.keys)
                                        unbound: !!row.bind.unbound
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.bind.description
                                        color: Theme.on_surface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.bind.command || ""
                                        color: Theme.on_surface_variant
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                }

                                // Can't be edited here: a lock with the reason on hover.
                                Text {
                                    visible: !row.bind.editable
                                    text: String.fromCodePoint(0xF033E)   // lock
                                    color: Theme.on_surface_variant
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 15
                                    HoverHandler {
                                        id: lockHover
                                    }
                                    ToolTip.visible: lockHover.hovered
                                    ToolTip.delay: 300
                                    ToolTip.text: row.bind.reason || ""
                                }

                                // What the buttons do, on hover.
                                Row {
                                    spacing: 10
                                    opacity: tileMouse.containsMouse || row.selected ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Text {
                                        visible: row.bind.editable
                                        text: String.fromCodePoint(0xF03EB)   // pencil
                                        color: Theme.primary
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 15
                                    }
                                    Text {
                                        visible: row.bind.runnable
                                        text: String.fromCodePoint(0xF040A)   // play
                                        color: Theme.on_surface_variant
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 15
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty / error state.
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 380)
                    spacing: 10
                    visible: KeybindsState.rows.length === 0 && !(KeybindsState.refreshing && KeybindsState.count === 0)

                    readonly property bool failed: KeybindsState.errorMessage !== "" && KeybindsState.count === 0

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 72
                        implicitHeight: 72
                        radius: 36
                        color: Theme.surface_container_high
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(parent.parent.failed ? 0xF0026 : 0xF0349)   // alert / magnify
                            color: parent.parent.failed ? Theme.error : Theme.primary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 34
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.failed ? "Could not load keybinds" : "No matching keybinds"
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.failed ? KeybindsState.errorMessage : "Try a different key, action or command."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }


    // --- Dialogs ---

    // A dialog over the card: dims it, and a click beside the box dismisses.
    component Dialog: Item {
        id: dialog
        property bool shown: false
        property int boxWidth: 520
        default property alias content: dialogColumn.data
        signal dismissed()

        anchors.fill: parent
        z: 10
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Qt.rgba(Theme.scrim.r, Theme.scrim.g, Theme.scrim.b, 0.5)
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onClicked: dialog.dismissed()
            onWheel: wheel => wheel.accepted = true
        }

        Rectangle {
            anchors.centerIn: parent
            width: dialog.boxWidth
            height: Math.min(dialogColumn.implicitHeight + 48, dialog.height - 24)
            radius: 22
            color: Theme.surface_container
            border.color: Theme.outline_variant
            border.width: 1
            scale: dialog.shown ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => wheel.accepted = true
            }

            ColumnLayout {
                id: dialogColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 14
            }
        }
    }

    // Title row of a dialog: a round glyph badge, a small label and a title.
    component DialogTitle: RowLayout {
        id: dialogTitle
        property string glyph: ""
        property string label: ""
        property string title: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: 14

        Rectangle {
            implicitWidth: 44
            implicitHeight: 44
            radius: 22
            color: Theme.primary_container
            Text {
                anchors.centerIn: parent
                text: dialogTitle.glyph
                color: Theme.on_primary_container
                font.family: Theme.iconFontFamily
                font.pixelSize: 20
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            FieldLabel {
                text: dialogTitle.label
            }
            Text {
                Layout.fillWidth: true
                text: dialogTitle.title
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: dialogTitle.detail
                color: Theme.on_surface_variant
                font.family: Theme.iconFontFamily
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }
        }
    }

    // Receives the keys while a shortcut is recorded, and Return in the editor.
    Item {
        id: keyCatcher
        Keys.onShortcutOverride: event => {
            event.accepted = KeybindsState.recording
                && !(event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier);
        }
        Keys.onPressed: event => {
            if (KeybindsState.recording) {
                event.accepted = KeybindsState.captureKey(event, true);
            } else if (KeybindsState.editorOpen && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                if (!editor.hasClash)
                    editor.submit("keep");
                event.accepted = true;
            }
        }
        Keys.onReleased: event => {
            if (KeybindsState.recording)
                event.accepted = KeybindsState.captureKey(event, false);
        }
        // Clicking into a text field ends the recording (and lets Hyprland's binds work again).
        onActiveFocusChanged: if (!activeFocus && KeybindsState.recording) KeybindsState.stopRecording()
    }

    // --- Bind editor ---
    Dialog {
        id: editor
        shown: KeybindsState.editorOpen
        boxWidth: 600
        onDismissed: if (!KeybindsState.saving) KeybindsState.closeEditor()

        readonly property var bind: KeybindsState.editing
        readonly property bool isNew: KeybindsState.isNew
        readonly property bool recording: KeybindsState.recording
        readonly property bool commandEditable: isNew || !!(bind && bind.kind === "exec")
        readonly property bool hasClash: !recording && KeybindsState.combo !== null && KeybindsState.clashes.length > 0
        readonly property bool canSave: !KeybindsState.saving && !recording && KeybindsState.comboProblem === ""
            && (!isNew || (KeybindsState.combo !== null && commandField.text.trim() !== ""))
        property int sectionIndex: 0
        property bool confirmDelete: false

        function load() {
            confirmDelete = false;
            descField.text = bind ? (bind.hasDescription ? bind.description : "") : "";
            commandField.text = bind && bind.kind === "exec" ? bind.command : "";
            const labels = root.sectionLabels;
            const label = bind ? bind.section
                : (KeybindsState.section !== "" ? KeybindsState.section : (labels.length > 0 ? labels[labels.length - 1] : ""));
            sectionIndex = Math.max(0, labels.indexOf(label));
            if (isNew)
                descField.forceActiveFocus();
        }

        function submit(mode) {
            if (!canSave)
                return;
            KeybindsState.save({
                "description": descField.text,
                "command": commandField.text,
                "section": root.sectionLabels[sectionIndex] || ""
            }, mode);
        }

        DialogTitle {
            glyph: String.fromCodePoint(editor.isNew ? 0xF0415 : 0xF03EB)   // plus / pencil
            label: editor.isNew ? "New keybind" : "Edit keybind"
            title: editor.isNew ? (descField.text.trim() || commandField.text.trim() || "Run a command")
                : (editor.bind ? editor.bind.description : "")
            detail: editor.bind && !editor.commandEditable ? (editor.bind.command || "") : ""
        }

        // Shortcut: click to record, then press keys, click or scroll in here.
        RowLayout {
            Layout.fillWidth: true
            FieldLabel {
                Layout.fillWidth: true
                text: "Shortcut"
            }
            FieldLabel {
                visible: !editor.isNew && !!editor.bind && KeybindsState.combo !== null
                text: "Was"
            }
            KeyCaps {
                visible: !editor.isNew && !!editor.bind && KeybindsState.combo !== null
                chips: editor.bind ? Logic.chips(editor.bind.keys) : []
                unbound: !!(editor.bind && editor.bind.unbound)
            }
        }

        Rectangle {
            id: zone
            Layout.fillWidth: true
            implicitHeight: 112
            radius: 18
            color: zoneMouse.containsMouse && !editor.recording ? Theme.surface_container_highest : Theme.surface_container_high
            border.width: 2
            border.color: editor.recording ? Theme.primary
                : ((KeybindsState.comboProblem !== "" || editor.hasClash) ? Theme.error : Theme.outline_variant)
            Behavior on color { ColorAnimation { duration: 120 } }

            // Set when a press was recorded, so its click doesn't start recording again.
            property bool swallowClick: false

            // Breathing ring while listening.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -5
                radius: parent.radius + 5
                color: "transparent"
                border.color: Theme.primary
                border.width: 2
                visible: editor.recording
                SequentialAnimation on opacity {
                    running: editor.recording
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.5; to: 0; duration: 1100; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 200 }
                }
            }

            MouseArea {
                id: zoneMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                cursorShape: editor.recording ? Qt.CrossCursor : Qt.PointingHandCursor
                onPressed: mouse => {
                    zone.swallowClick = KeybindsState.captureMouse(mouse.button, mouse.modifiers);
                }
                onClicked: mouse => {
                    if (!zone.swallowClick && mouse.button === Qt.LeftButton && !KeybindsState.saving)
                        KeybindsState.startRecording();
                    zone.swallowClick = false;
                }
                onWheel: wheel => {
                    KeybindsState.captureWheel(wheel.angleDelta.x, wheel.angleDelta.y, wheel.modifiers);
                    wheel.accepted = true;
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 10

                KeyCaps {
                    Layout.alignment: Qt.AlignHCenter
                    visible: chips.length > 0
                    pixelSize: 17
                    chips: editor.recording ? KeybindsState.heldMods : Logic.chips(KeybindsState.shownKeys)
                }

                Text {
                    Layout.fillWidth: true
                    visible: editor.recording ? KeybindsState.heldMods.length === 0 : KeybindsState.shownKeys === ""
                    text: editor.recording ? "Press keys, click or scroll here" : "Click to record a shortcut"
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (editor.recording)
                            return KeybindsState.dragBind ? "Hold the modifiers, then click a mouse button · Esc stops"
                                : "Hold the modifiers, then a key, mouse button or wheel · Esc stops";
                        if (KeybindsState.comboProblem !== "")
                            return KeybindsState.comboProblem;
                        if (KeybindsState.combo === null)
                            return editor.isNew ? "Keys, mouse buttons (thumb buttons too) and the wheel all work" : "Click to record a new one";
                        if (KeybindsState.comboUnchanged)
                            return "That is already its shortcut";
                        if (editor.hasClash)
                            return "Already used by another bind";
                        return "Free to use · click to record again";
                    }
                    color: (KeybindsState.comboProblem !== "" || editor.hasClash) && !editor.recording ? Theme.error : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Clash warning.
        Rectangle {
            Layout.fillWidth: true
            visible: editor.hasClash
            implicitHeight: clashColumn.implicitHeight + 24
            radius: 14
            color: Theme.error_container

            ColumnLayout {
                id: clashColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    spacing: 8
                    Text {
                        text: String.fromCodePoint(0xF0026)   // alert
                        color: Theme.on_error_container
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 16
                    }
                    Text {
                        text: KeybindsState.clashes.length === 1 ? "This shortcut is already used by"
                            : "This shortcut is already used by " + KeybindsState.clashes.length + " binds"
                        color: Theme.on_error_container
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                Repeater {
                    model: editor.hasClash ? KeybindsState.clashes : []
                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        text: modelData.description + "  ·  " + modelData.section + (modelData.clearable ? "" : "  ·  can't be cleared here")
                        color: Theme.on_error_container
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: KeybindsState.canClearClashes
                        ? "Clear other takes the shortcut off the bind above. Keep both makes it run both."
                        : "Keep both makes it run both; the other bind can only be changed in keybindings.lua."
                    color: Theme.on_error_container
                    opacity: 0.85
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        // Description + section.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                spacing: 6
                FieldLabel {
                    text: "Description"
                }
                FieldInput {
                    id: descField
                    Layout.fillWidth: true
                    placeholderText: "What it does, e.g. Open the terminal"
                    onAccepted: if (!editor.hasClash) editor.submit("keep")
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                spacing: 6
                FieldLabel {
                    text: "Section"
                }
                FieldCombo {
                    Layout.fillWidth: true
                    model: root.sectionLabels
                    boundIndex: editor.sectionIndex
                    enabled: editor.isNew || !!(editor.bind && editor.bind.movable)
                    onActivated: index => editor.sectionIndex = index
                }
            }
        }

        // Command: a shell command for exec binds, read-only for Hyprland actions.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            FieldLabel {
                text: editor.commandEditable ? "Command" : "Hyprland action"
            }
            FieldInput {
                id: commandField
                Layout.fillWidth: true
                visible: editor.commandEditable
                font.family: Theme.iconFontFamily
                font.pixelSize: 12
                placeholderText: "Shell command to run, e.g. kitty or ~/.config/hypr/scripts/foo.sh"
                onAccepted: if (!editor.hasClash) editor.submit("keep")
            }
            Rectangle {
                Layout.fillWidth: true
                visible: !editor.commandEditable
                implicitHeight: actionText.implicitHeight + 18
                radius: 10
                color: Theme.surface_container_high
                Text {
                    id: actionText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    text: (editor.bind ? editor.bind.command : "") + "\nChange the action itself in keybindings.lua."
                    color: Theme.on_surface_variant
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: KeybindsState.editError !== ""
            text: KeybindsState.editError
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        // Actions.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            PanelButton {
                visible: !editor.isNew && !!editor.bind && !editor.bind.unbound && editor.bind.clearable && !KeybindsState.saving
                compact: true
                text: "Unbind"
                glyph: String.fromCodePoint(0xF0156)   // close
                focusPolicy: Qt.NoFocus
                onClicked: KeybindsState.unbindEditing()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "Keep the bind but take its shortcut away"
            }
            PanelButton {
                visible: !editor.isNew && !!editor.bind && editor.bind.movable && !KeybindsState.saving
                compact: true
                text: editor.confirmDelete ? "Click again to delete" : "Delete"
                glyph: String.fromCodePoint(0xF01B4)   // delete
                focusPolicy: Qt.NoFocus
                onClicked: {
                    if (editor.confirmDelete)
                        KeybindsState.deleteEditing();
                    else
                        editor.confirmDelete = true;
                }
            }
            RowLayout {
                visible: KeybindsState.saving
                spacing: 8
                BusyIndicator {
                    implicitWidth: 24
                    implicitHeight: 24
                    running: KeybindsState.saving
                }
                FieldLabel {
                    text: "Saving and reloading Hyprland…"
                }
            }

            Item {
                Layout.fillWidth: true
            }

            PanelButton {
                text: "Cancel"
                enabled: !KeybindsState.saving
                focusPolicy: Qt.NoFocus
                onClicked: KeybindsState.closeEditor()
            }
            PanelButton {
                visible: editor.hasClash
                text: "Keep both"
                tonal: true
                enabled: editor.canSave
                focusPolicy: Qt.NoFocus
                onClicked: editor.submit("keep")
            }
            PanelButton {
                visible: editor.hasClash
                text: "Clear other"
                filled: true
                enabled: editor.canSave && KeybindsState.canClearClashes
                focusPolicy: Qt.NoFocus
                onClicked: editor.submit("clear")
            }
            PanelButton {
                visible: !editor.hasClash
                text: editor.isNew ? "Add" : "Save"
                filled: true
                enabled: editor.canSave
                focusPolicy: Qt.NoFocus
                onClicked: editor.submit("keep")
            }
        }
    }

    // --- Delete section ---
    Dialog {
        id: sectionDialog
        shown: root.deletingSection !== ""
        boxWidth: 480
        onDismissed: root.deletingSection = ""

        readonly property var sec: KeybindsState.sections.find(s => s.label === root.deletingSection) || null
        readonly property int count: sec ? sec.binds.length : 0
        readonly property bool removable: !!(sec && sec.removable)
        readonly property var targets: root.sectionLabels.filter(l => l !== root.deletingSection)
        readonly property var choices: targets.map(l => "Move them to " + l).concat(["Delete them too"])
        property int choice: 0
        onShownChanged: if (shown) choice = 0

        DialogTitle {
            glyph: String.fromCodePoint(0xF01B4)   // delete
            label: "Delete section"
            title: root.deletingSection
        }

        Text {
            Layout.fillWidth: true
            text: !sectionDialog.removable
                ? "It holds binds set by the workspace loop, which can only be changed in keybindings.lua."
                : (sectionDialog.count === 0 ? "Its heading comment is removed from keybindings.lua."
                    : "It holds " + sectionDialog.count + (sectionDialog.count === 1 ? " bind." : " binds."))
            color: sectionDialog.removable ? Theme.on_surface_variant : Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        FieldCombo {
            Layout.fillWidth: true
            visible: sectionDialog.removable && sectionDialog.count > 0
            model: sectionDialog.choices
            boundIndex: sectionDialog.choice
            onActivated: index => sectionDialog.choice = index
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
                focusPolicy: Qt.NoFocus
                onClicked: root.deletingSection = ""
            }
            PanelButton {
                text: "Delete"
                filled: true
                enabled: sectionDialog.removable && !KeybindsState.saving
                focusPolicy: Qt.NoFocus
                onClicked: {
                    const moveTo = sectionDialog.count > 0 && sectionDialog.choice < sectionDialog.targets.length
                        ? sectionDialog.targets[sectionDialog.choice] : "";
                    KeybindsState.deleteSection(root.deletingSection, moveTo);
                    root.deletingSection = "";
                }
            }
        }
    }
}
