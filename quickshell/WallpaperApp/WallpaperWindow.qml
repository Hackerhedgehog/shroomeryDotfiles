import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Qt.labs.folderlistmodel
import qs.shared
import qs.shared.ui
import qs.WallpaperApp

// Wallpaper picker, in the middle of the screen: Static/Animated tabs (Tab
// switches), search and Random in the header, the tab's wallpapers as a grid
// (click one to set it), and a side column with the current wallpaper and the
// options (transition, effect, monitor, positioning, theming, random rotation,
// folder). Animated wallpapers are the videos/GIFs in the folder's animated/.
CenterPanel {
    id: root
    ipcTarget: "wallpaper"
    cardWidth: 1140
    cardHeight: 720
    escapeHandler: function () {
        if (WallpaperState.query !== "") {
            search.text = "";
            return true;
        }
        return false;
    }

    readonly property var monitorLabels: {
        const list = ["All"];
        const mons = Hyprland.monitors.values;
        for (let i = 0; i < mons.length; i++)
            list.push(mons[i].name);
        return list;
    }

    readonly property int monitorIndex: {
        const idx = monitorLabels.indexOf(WallpaperState.selectedMonitor);
        return idx < 0 ? 0 : idx;
    }

    readonly property bool searching: WallpaperState.query.trim() !== ""
    readonly property bool empty: folderModel.status === FolderListModel.Ready && folderModel.count === 0

    readonly property bool animated: WallpaperState.animatedTab
    readonly property var tabNames: ["Static", "Animated"]

    readonly property string countLabel: {
        if (WallpaperState.applying)
            return "Applying…";
        if (empty)
            return searching ? "No match" : "Empty";
        return folderModel.count + (searching ? " matches" : (animated ? " videos" : " images"));
    }

    readonly property string statusText: {
        if (WallpaperState.errorMessage !== "")
            return WallpaperState.errorMessage;
        if (WallpaperState.applying)
            return "Setting wallpaper…";
        if (WallpaperState.bannerMessage !== "")
            return WallpaperState.bannerMessage;
        if (WallpaperState.folderName === "")
            return "Pick an image for your desktop";
        return "From " + WallpaperState.folderName + (animated ? "/animated" : "");
    }

    onIsOpenChanged: {
        if (isOpen) {
            WallpaperState.panelOpen = true;
            search.text = "";
            WallpaperState.reloadFolder();
            search.focusField();
        } else {
            WallpaperState.panelOpen = false;
            search.text = "";
        }
    }

    // Keyboard selection (grid.currentIndex): the current wallpaper when it is listed, else the first image.
    function resetSelection() {
        if (folderModel.count === 0)
            return;
        const idx = WallpaperState.currentWallpaper !== "" ? folderModel.indexOf("file://" + WallpaperState.currentWallpaper) : -1;
        grid.currentIndex = idx >= 0 ? idx : 0;
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    function moveSelection(step) {
        const count = folderModel.count;
        if (count === 0)
            return;
        const cols = Math.max(1, Math.floor(grid.width / grid.cellWidth));
        const from = Math.max(0, grid.currentIndex);
        let next = from + step;
        // Down from a row above a shorter last row lands on the last image.
        if (next >= count)
            next = Math.floor(from / cols) < Math.floor((count - 1) / cols) ? count - 1 : from;
        if (next < 0)
            next = step < -1 ? from % cols : from;
        grid.currentIndex = next;
        grid.positionViewAtIndex(next, GridView.Contain);
    }

    // Arrows move the selection, Page Up/Down by three rows, Return applies it, Tab switches tabs.
    function handleKey(event) {
        const cols = Math.max(1, Math.floor(grid.width / grid.cellWidth));
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            WallpaperState.animatedTab = !WallpaperState.animatedTab;
        else if (event.key === Qt.Key_Left)
            moveSelection(-1);
        else if (event.key === Qt.Key_Right)
            moveSelection(1);
        else if (event.key === Qt.Key_Up)
            moveSelection(-cols);
        else if (event.key === Qt.Key_Down)
            moveSelection(cols);
        else if (event.key === Qt.Key_PageUp)
            moveSelection(-3 * cols);
        else if (event.key === Qt.Key_PageDown)
            moveSelection(3 * cols);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (grid.currentIndex >= 0 && grid.currentIndex < folderModel.count)
                WallpaperState.applyPath(folderModel.get(grid.currentIndex, "filePath"));
        } else
            return;
        event.accepted = true;
    }

    FolderListModel {
        id: folderModel
        onStatusChanged: if (status === FolderListModel.Ready) root.resetSelection()
        folder: {
            const _e = WallpaperState.folderEpoch;
            if (_e % 2 === 1)
                return "";
            return WallpaperState.activeFolder !== "" ? "file://" + WallpaperState.activeFolder : "";
        }
        showDirs: false
        caseSensitive: false
        sortField: FolderListModel.Name
        nameFilters: {
            const s = WallpaperState.query.trim().replace(/[\\*?\[\]]/g, "");
            const exts = root.animated ? WallpaperState.animatedExtensions : WallpaperState.imageExtensions;
            return exts.map(ext => "*" + s + (s !== "" ? "*." : ".") + ext);
        }
    }

    // Marks an animated wallpaper (grid tile, current preview).
    component PlayBadge: Rectangle {
        width: 24
        height: 24
        radius: 12
        color: Qt.rgba(Theme.surface_container_lowest.r, Theme.surface_container_lowest.g, Theme.surface_container_lowest.b, 0.82)
        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 1
            text: String.fromCodePoint(0xF040A)   // play
            color: Theme.on_surface
            font.family: Theme.iconFontFamily
            font.pixelSize: 15
        }
    }

    // A label over a full-width control, for the options column.
    component Field: ColumnLayout {
        property string label: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 6
        FieldLabel {
            text: parent.label
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF02F9)   // image-multiple
            title: "Wallpaper"
            subtitle: root.statusText
            subtitleColor: WallpaperState.errorMessage !== "" ? Theme.error : Theme.on_surface_variant

            TabPills {
                model: root.tabNames
                currentIndex: root.animated ? 1 : 0
                onActivated: index => {
                    WallpaperState.animatedTab = index === 1;
                    search.focusField();
                }
            }

            SearchField {
                id: search
                Layout.preferredWidth: 260
                placeholderText: root.animated ? "Search videos" : "Search images"
                onTextChanged: WallpaperState.query = text
                onKeyPressed: event => root.handleKey(event)
            }

            StatusChip {
                text: root.countLabel
                tone: root.empty ? "error" : (WallpaperState.applying ? "busy" : "normal")
            }

            PanelButton {
                text: "Random"
                glyph: String.fromCodePoint(0xF049F)   // shuffle-variant
                tonal: true
                enabled: !WallpaperState.applying && !root.empty
                onClicked: WallpaperState.applyRandom(WallpaperState.activeFolder)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // --- Images ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 360)
                    spacing: 10
                    visible: root.empty

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 72
                        implicitHeight: 72
                        radius: 36
                        color: Theme.surface_container_high
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(root.searching ? 0xF0349 : (root.animated ? 0xF0567 : 0xF0976))   // magnify / video-outline / image-outline
                            color: Theme.primary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 34
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.searching ? (root.animated ? "No matching videos" : "No matching images") : (root.animated ? "No animated wallpapers" : "No wallpapers found")
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.searching ? "Try a different file name." : root.animated ? "Put videos or GIFs in the folder's animated/ subfolder." : "The folder is empty or the path is wrong. Change it on the right."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.rightMargin: -8
                    visible: folderModel.count > 0
                    clip: true
                    cacheBuffer: 3000
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor(width / 4)
                    cellHeight: Math.round(cellWidth * 0.68)
                    model: folderModel

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: tile
                        readonly property string tilePath: model.filePath
                        readonly property string tileName: model.fileName
                        // False for a moment after a tab switch, while the rows still list the other tab's files.
                        readonly property bool inFolder: tilePath.substring(0, tilePath.lastIndexOf("/")) === WallpaperState.activeFolder.replace(/\/+$/, "")
                        readonly property string thumbSource: inFolder ? WallpaperState.thumbnailUrl(model.fileName, model.fileSize) : ""
                        // Set when the cached preview is missing; the original is loaded only if
                        // the thumbnail script is not (or no longer) running.
                        property bool thumbMissing: false
                        readonly property bool current: WallpaperState.isCurrent(tilePath)
                        readonly property bool busy: WallpaperState.pendingPath === tilePath
                        readonly property bool selected: grid.currentIndex === index
                        readonly property bool highlighted: hover.hovered || selected
                        width: grid.cellWidth
                        height: grid.cellHeight

                        onThumbSourceChanged: thumbMissing = false

                        Connections {
                            target: WallpaperState
                            function onThumbnailEpochChanged() {
                                tile.thumbMissing = false;
                            }
                        }

                        Item {
                            id: card
                            anchors.fill: parent
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 8
                            opacity: WallpaperState.applying && !tile.busy ? 0.6 : 1
                            scale: tile.highlighted && !WallpaperState.applying ? 1.03 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160 } }

                            HoverHandler {
                                id: hover
                                cursorShape: WallpaperState.applying ? Qt.BusyCursor : Qt.PointingHandCursor
                            }

                            TapHandler {
                                enabled: !WallpaperState.applying
                                onTapped: {
                                    grid.currentIndex = index;
                                    WallpaperState.applyPath(tile.tilePath);
                                }
                            }

                            Rectangle {
                                id: contentMask
                                anchors.fill: parent
                                radius: 14
                                visible: false
                            }

                            Item {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: contentMask
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.surface_container_high
                                }

                                Image {
                                    id: thumbnail
                                    anchors.fill: parent
                                    source: !tile.thumbMissing ? tile.thumbSource : (WallpaperState.thumbnailsRunning || root.animated || !tile.inFolder) ? "" : "file://" + tile.tilePath
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 280
                                    sourceSize.height: 280
                                    opacity: status === Image.Ready ? 1 : 0
                                    onStatusChanged: {
                                        if (status === Image.Error && source.toString() === tile.thumbSource)
                                            tile.thumbMissing = true;
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 250
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    running: thumbnail.status === Image.Loading || tile.busy || (tile.thumbMissing && WallpaperState.thumbnailsRunning)
                                    opacity: running ? 0.8 : 0
                                }

                                // File name, shown on hover and on the keyboard selection.
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 30
                                    color: Qt.rgba(Theme.surface_container_lowest.r, Theme.surface_container_lowest.g, Theme.surface_container_lowest.b, 0.82)
                                    opacity: tile.highlighted ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        text: tile.tileName
                                        color: Theme.on_surface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            PlayBadge {
                                visible: root.animated
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 8
                            }

                            // Ring + check on the current wallpaper; a plain ring on the keyboard selection.
                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                color: "transparent"
                                border.color: tile.current ? Theme.primary : Theme.on_surface
                                border.width: 3
                                visible: tile.current || tile.selected
                            }
                            Rectangle {
                                visible: tile.current
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                width: 24
                                height: 24
                                radius: 12
                                color: Theme.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF012C)   // check
                                    color: Theme.on_primary
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 15
                                }
                            }
                        }
                    }
                }
            }

            // --- Current wallpaper + options ---
            Card {
                Layout.preferredWidth: 330
                Layout.fillHeight: true

                Flickable {
                    id: optionsFlick
                    anchors.fill: parent
                    anchors.margins: 16
                    clip: true
                    contentWidth: width
                    contentHeight: optionsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: optionsFlick.contentHeight > optionsFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: optionsColumn
                        width: optionsFlick.width
                        spacing: 14

                        // Current wallpaper.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: Math.round(width * 0.48)

                            Rectangle {
                                id: previewMask
                                anchors.fill: parent
                                radius: 12
                                visible: false
                            }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: previewMask
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.surface_container_high
                                }
                                Image {
                                    anchors.fill: parent
                                    source: {
                                        const still = WallpaperState.stillWallpaper;
                                        if (WallpaperState.currentAnimated)
                                            return still !== "" ? "file://" + still : "";
                                        return WallpaperState.currentWallpaper !== "" ? "file://" + WallpaperState.currentWallpaper : "";
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 600
                                    cache: false
                                }
                                PlayBadge {
                                    visible: WallpaperState.currentAnimated
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: -4
                            spacing: 0
                            FieldLabel {
                                text: "Current"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: WallpaperState.currentName !== "" ? WallpaperState.currentName : "—"
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideMiddle
                            }
                        }

                        SectionHeader {
                            label: "Apply"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Field {
                                label: "Transition"
                                FieldCombo {
                                    Layout.fillWidth: true
                                    compact: true
                                    // Animated wallpapers start without a transition.
                                    enabled: !root.animated
                                    model: WallpaperState.transitionEffects
                                    boundIndex: WallpaperState.transitionIndex
                                    onActivated: index => WallpaperState.setTransition(WallpaperState.transitionEffects[index])
                                }
                            }
                            Field {
                                label: "Effect"
                                FieldCombo {
                                    Layout.fillWidth: true
                                    compact: true
                                    // Effects only apply to still images.
                                    enabled: !WallpaperState.applying && !root.animated
                                    model: WallpaperState.wallpaperEffects
                                    boundIndex: WallpaperState.effectIndex
                                    onActivated: index => WallpaperState.setEffect(WallpaperState.wallpaperEffects[index])
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Field {
                                label: "Monitor"
                                FieldCombo {
                                    Layout.fillWidth: true
                                    compact: true
                                    model: root.monitorLabels
                                    boundIndex: root.monitorIndex
                                    onActivated: index => WallpaperState.setMonitor(root.monitorLabels[index])
                                }
                            }
                            Field {
                                label: "Positioning"
                                FieldCombo {
                                    Layout.fillWidth: true
                                    compact: true
                                    model: WallpaperState.cropGravities
                                    boundIndex: WallpaperState.cropIndex
                                    onActivated: index => WallpaperState.setCropGravity(WallpaperState.cropGravities[index])
                                }
                            }
                        }

                        SettingRow {
                            label: "Theme from wallpaper"
                            hint: "Recolor the desktop with matugen"
                            ToggleSwitch {
                                checked: WallpaperState.updateTheming
                                onClicked: WallpaperState.updateTheming = checked
                            }
                        }

                        SettingRow {
                            label: "Random rotation"
                            ToggleSwitch {
                                checked: WallpaperState.randomEnabled
                                onClicked: WallpaperState.setRandomEnabled(checked)
                            }
                        }

                        SettingRow {
                            visible: WallpaperState.randomEnabled
                            label: "Change every"
                            // Commits on Enter or focus loss; reverts to the stored
                            // value if what was typed is not a whole number.
                            FieldInput {
                                id: intervalField
                                implicitWidth: 80
                                implicitHeight: 32
                                horizontalAlignment: Text.AlignRight
                                validator: IntValidator {
                                    bottom: 1
                                }
                                Component.onCompleted: text = String(WallpaperState.randomInterval)
                                onEditingFinished: {
                                    const n = parseInt(text, 10);
                                    if (!isNaN(n))
                                        WallpaperState.setRandomInterval(n);
                                    text = String(isNaN(n) ? WallpaperState.randomInterval : Math.max(WallpaperState.minRandomInterval, n));
                                }
                                Connections {
                                    target: WallpaperState
                                    function onRandomIntervalChanged() {
                                        if (!intervalField.activeFocus)
                                            intervalField.text = String(WallpaperState.randomInterval);
                                    }
                                }
                            }
                            FieldLabel {
                                text: "s"
                            }
                        }

                        SectionHeader {
                            label: "Folder"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            FieldInput {
                                id: folderField
                                Layout.fillWidth: true
                                implicitHeight: 34
                                font.pixelSize: 12
                                placeholderText: "Full path to your wallpaper folder"
                                ToolTip.visible: activeFocus
                                ToolTip.text: "Press Return to use this folder"
                                // Show the start of a long path while not editing.
                                onTextChanged: if (!activeFocus) cursorPosition = 0
                                onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                Component.onCompleted: text = WallpaperState.folderSettingText
                                onAccepted: WallpaperState.setFolder(text)
                                Connections {
                                    target: WallpaperState
                                    function onFolderSettingTextChanged() {
                                        if (!folderField.activeFocus)
                                            folderField.text = WallpaperState.folderSettingText;
                                    }
                                }
                            }
                            ActionIcon {
                                implicitWidth: 34
                                implicitHeight: 34
                                iconTxt: String.fromCodePoint(0xF0450)   // refresh
                                iconPixelSize: 18
                                onClicked: WallpaperState.reloadFolder()
                                ToolTip.visible: hovered
                                ToolTip.delay: 500
                                ToolTip.text: "Reload images"
                            }
                        }
                        PanelButton {
                            Layout.fillWidth: true
                            text: "Clear wallpaper cache"
                            glyph: String.fromCodePoint(0xF00E2)   // broom
                            compact: true
                            enabled: !WallpaperState.applying
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: "Deletes the generated wallpaper copies in ~/.cache/shroomery and restores the default wallpaper"
                            onClicked: WallpaperState.clearCache()
                        }
                    }
                }
            }
        }
    }
}
