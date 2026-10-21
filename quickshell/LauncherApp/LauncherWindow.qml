import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Qt.labs.folderlistmodel
import qs.shared
import qs.shared.ui
import qs.LauncherApp
import "Calculator.js" as Calculator
import "Search.js" as Search
import "Emoji.js" as Emoji

// Application launcher (SUPER+E via hypr/scripts/launcher.sh): the blurred
// wallpaper on the left with the search pill on top and the mode buttons at
// the bottom, the results on the right.
// Modes: apps, files, windows, run, emoji (a grid with category tabs above it;
// picking one copies it). The search field doubles as a calculator
// (+ - * / ^ ( ) [ ]): a complete expression shows its answer on the left,
// and Return or a click on it copies the answer.
//
// The apps and emoji tabs show a list or a grid (LauncherState, toggled in the
// SettingsApp).
//
// Keys: Up/Down/PageUp/PageDown move, Return runs the selection, Ctrl+Return
// runs the typed text (run mode), Alt+Return runs an app or
// command as root via pkexec (in a terminal with sudo for terminal apps), a right click opens a menu
// (Run as sudo, Open file location, Uninstall), Tab/Shift+Tab switch mode, Backspace in an
// empty search goes up a folder (files mode), Escape closes. Left/Right move
// within a grid and switch mode in a list (Ctrl+Left/Right move the text
// cursor by word); past the edge of the emoji grid they continue in the
// neighbouring category. PageUp/PageDown switch the emoji category.
SlidePanel {
    id: root
    ipcTarget: "launcher"
    edge: "top"
    fullHeight: false

    // Everything is sized in em of an 11pt font.
    readonly property int em: 15
    readonly property int shadowMargin: 16
    panelWidth: 56 * em + 2 * shadowMargin
    implicitHeight: 35 * em + 2 * shadowMargin
    // Slide down to the middle of the screen.
    topMargin: screen ? Math.max(0, Math.round((screen.height - implicitHeight) / 2)) : 200

    readonly property color tint: Qt.rgba(Theme.on_secondary.r, Theme.on_secondary.g, Theme.on_secondary.b, 0.7)

    readonly property var modes: [
        { key: "apps", glyph: "", label: "Apps" },
        { key: "files", glyph: "", label: "Files" },
        { key: "windows", glyph: "", label: "Windows" },
        { key: "run", glyph: "", label: "Run" },
        { key: "emoji", glyph: "", label: "Emoji" }
    ]
    property int modeIndex: 0
    readonly property string mode: modes[modeIndex].key

    property string query: ""
    property int selectedIndex: 0
    readonly property string answer: Calculator.answer(query)

    // Bumped on open so the backdrop picks up a new wallpaper.
    property int wallpaperRevision: 0

    // Executables on $PATH, loaded the first time run mode is shown.
    property var runItems: []
    property bool runLoaded: false

    property string filesFolder: Paths.home
    property var fileItems: []

    // All emoji (parsed from emojis.tsv the first time emoji mode is shown)
    // and the category tab shown while the search is empty.
    property var emojiItems: []
    property int emojiCategory: 0

    // Grid or list for the current tab, and the grid's width in cells.
    readonly property bool gridView: mode === "emoji" ? LauncherState.emojiGrid
        : (mode === "apps" && LauncherState.appsGrid)
    readonly property int gridColumns: mode === "emoji" ? 7 : 4
    readonly property bool searching: query.trim() !== ""

    // Uninstall flow (right-click menu): "" (none), "planning", "confirm",
    // "running" or "done". The panel over the results shows the script's
    // output; the default answer is the first button.
    property var uninstallItem: null
    property string uninstallPhase: ""
    property var uninstallLines: []
    property bool uninstallDefaultYes: false
    property bool uninstallOk: false
    property int uninstallChoice: 0
    readonly property var uninstallButtons: uninstallPhase === "confirm"
        ? (uninstallDefaultYes ? ["Yes", "No"] : ["No", "Yes"]) : ["Close"]

    escapeHandler: function () {
        if (root.uninstallPhase === "")
            return false;
        if (root.uninstallPhase !== "running" && root.uninstallPhase !== "planning")
            root.closeUninstall();
        return true;
    }

    onIsOpenChanged: {
        if (!isOpen)
            return;
        if (uninstallPhase !== "running" && uninstallPhase !== "planning")
            closeUninstall();
        modeIndex = 0;
        filesFolder = Paths.home;
        searchField.text = "";
        selectedIndex = 0;
        wallpaperRevision++;
        Hyprland.refreshToplevels();
        searchField.forceActiveFocus();
    }

    onModeChanged: {
        selectedIndex = 0;
        if (mode === "run" && !runLoaded) {
            runLoaded = true;
            pathScan.running = true;
        }
        if (mode === "emoji" && emojiItems.length === 0)
            loadEmoji();
    }
    onQueryChanged: selectedIndex = 0
    onEmojiCategoryChanged: selectedIndex = 0
    onSelectedIndexChanged: Qt.callLater(positionSelection)
    function positionSelection() {
        if (gridView)
            resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
        else
            resultList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    // Open on a mode, or close when already open on it (SUPER+. for emoji).
    function toggleMode(key) {
        const index = modes.findIndex(m => m.key === key);
        if (index < 0)
            return;
        if (isOpen && modeIndex === index) {
            close();
            return;
        }
        if (!isOpen)
            open();
        modeIndex = index;
    }

    IpcHandler {
        target: "launcher-mode"
        function toggle(mode: string): void { root.toggleMode(mode); }
    }

    FileView {
        id: emojiFile
        path: Quickshell.shellPath("LauncherApp/emojis.tsv")
        blockLoading: true
    }

    function loadEmoji() {
        emojiItems = Emoji.parse(emojiFile.text()).map(e => ({
            "kind": "emoji",
            "name": e.name,
            "emoji": e.emoji,
            "category": e.category,
            "fields": [e.keywords]
        }));
    }

    function cycleEmojiCategory(step) {
        const count = Emoji.CATEGORIES.length;
        emojiCategory = (emojiCategory + step + count) % count;
        searchField.text = "";
    }

    function setEmojiCategory(index) {
        emojiCategory = index;
        searchField.text = "";
        searchField.forceActiveFocus();
    }

    readonly property var appItems: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .map(e => ({
            "kind": "app",
            "name": e.name,
            "fields": [e.genericName, e.comment, Array.from(e.keywords || []).join(" "), e.id],
            "icon": AppList.iconFor(e, e.id),
            "entry": e
        }))
        .sort((a, b) => a.name.localeCompare(b.name))

    // One line per window: workspace · class · title.
    readonly property var windowItems: Hyprland.toplevels.values.map(t => {
        const appId = t.wayland ? t.wayland.appId : `${t.lastIpcObject?.class ?? ""}`;
        const workspace = t.workspace ? `${t.workspace.name}` : "";
        return {
            "kind": "window",
            "name": [workspace, appId, t.title].filter(s => s).join(" · "),
            "fields": [],
            "icon": AppList.iconFor(AppList.lookupEntry(appId), appId),
            "toplevel": t
        };
    })

    readonly property var items: {
        const q = root.query;
        const name = i => i.name;
        const fields = i => i.fields;
        switch (root.mode) {
        case "apps":
            return Search.filter(root.appItems, q, name, fields);
        case "windows":
            return Search.filter(root.windowItems, q, name, fields);
        case "run":
            return Search.filter(root.runItems, q, name, fields);
        case "emoji": {
            if (!root.searching) {
                const key = Emoji.CATEGORIES[root.emojiCategory].key;
                return root.emojiItems.filter(e => e.category === key);
            }
            return Search.filter(root.emojiItems, q, name, fields);
        }
        case "files": {
            const found = Search.filter(root.fileItems, q, name, fields);
            if (q.trim() === "" && root.filesFolder !== "/")
                found.unshift({ "kind": "up", "name": "..", "fields": [], "icon": Quickshell.iconPath("go-up", "folder") });
            return found;
        }
        }
        return [];
    }

    function cycleMode(step) {
        modeIndex = (modeIndex + step + modes.length) % modes.length;
    }

    function setMode(index) {
        modeIndex = index;
        searchField.forceActiveFocus();
    }

    function moveSelection(step) {
        selectedIndex = Emoji.gridMove(selectedIndex, step, items.length);
    }

    // Left/Right in a grid. In the emoji grid (not while searching) going past
    // the first or last column continues in the neighbouring category, on the
    // same row.
    function sideMove(dir) {
        if (mode !== "emoji" || searching) {
            moveSelection(dir);
            return;
        }
        const step = Emoji.sideStep(selectedIndex, dir, items.length, gridColumns);
        if (step.category === 0) {
            selectedIndex = step.index;
            return;
        }
        cycleEmojiCategory(dir);
        selectedIndex = Emoji.landing(step.row, dir, items.length, gridColumns);
    }

    function openFolder(path) {
        filesFolder = path;
        searchField.text = "";
    }

    function parentFolder() {
        const cut = filesFolder.lastIndexOf("/");
        return cut <= 0 ? "/" : filesFolder.slice(0, cut);
    }

    function displayFolder() {
        return filesFolder.startsWith(Paths.home) ? "~" + filesFolder.slice(Paths.home.length) : filesFolder;
    }

    function copyAnswer() {
        Quickshell.execDetached(["wl-copy", root.answer]);
        root.close();
    }

    // Runs argv as root through polkit (graphical password prompt). pkexec
    // drops the environment, so the display variables are passed back in for
    // GUI apps.
    function execRoot(argv) {
        Quickshell.execDetached(["sh", "-c",
            "exec pkexec env \"WAYLAND_DISPLAY=$WAYLAND_DISPLAY\" \"XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR\" \"DISPLAY=$DISPLAY\" \"$@\"",
            "sh"].concat(argv));
    }

    function runText(text, asRoot) {
        if (text.trim() === "")
            return;
        root.close();
        if (asRoot)
            root.execRoot(["sh", "-c", text]);
        else
            Quickshell.execDetached(["sh", "-c", text]);
    }

    // asRoot (right click, Alt+Return) only applies to apps and typed commands.
    function activate(item, asRoot) {
        if (!item)
            return;
        switch (item.kind) {
        case "app":
            root.close();
            if (item.entry.runInTerminal) {
                const cmd = Array.from(item.entry.command);
                Quickshell.execDetached([Paths.terminal].concat(asRoot ? ["sudo"].concat(cmd) : cmd));
            } else if (asRoot) {
                root.execRoot(Array.from(item.entry.command));
            } else {
                item.entry.execute();
            }
            break;
        case "window":
            root.close();
            if (item.toplevel.wayland)
                item.toplevel.wayland.activate();
            break;
        case "run":
            root.runText(item.name, asRoot);
            break;
        case "up":
            root.openFolder(root.parentFolder());
            break;
        case "dir":
            root.openFolder(item.path);
            break;
        case "file":
            root.close();
            Quickshell.execDetached(["xdg-open", item.path]);
            break;
        case "emoji":
            root.close();
            Quickshell.execDetached(["wl-copy", item.emoji]);
            break;
        }
    }

    // Folder holding an item: the parent of a file or folder, the directory of
    // the executable for an app.
    function openLocation(item) {
        if (item.kind === "file" || item.kind === "dir") {
            const dir = item.path.replace(/\/[^\/]*$/, "") || "/";
            Quickshell.execDetached(["xdg-open", dir]);
        } else if (item.kind === "app") {
            const cmd = Array.from(item.entry.command);
            Quickshell.execDetached(["sh", "-c",
                "p=$(command -v -- \"$1\") && exec xdg-open \"$(dirname -- \"$(readlink -f -- \"$p\")\")\"", "sh", cmd[0] ?? ""]);
        }
        root.close();
    }

    function closeUninstall() {
        root.uninstallPhase = "";
        root.uninstallItem = null;
        root.uninstallLines = [];
        searchField.forceActiveFocus();
    }

    function addUninstallLine(line) {
        root.uninstallLines = root.uninstallLines.concat([line]);
    }

    // First step: ask uninstall-app.sh what it would remove.
    function uninstall(item) {
        root.uninstallItem = item;
        root.uninstallLines = [];
        root.uninstallChoice = 0;
        root.uninstallOk = false;
        root.uninstallDefaultYes = false;
        root.uninstallPhase = "planning";
        planProc.command = [Paths.uninstallApp, "--plan", item.entry.id];
        planProc.running = true;
    }

    function confirmUninstall(yes) {
        if (!yes) {
            root.closeUninstall();
            return;
        }
        root.uninstallLines = [];
        root.uninstallPhase = "running";
        runProc.command = [Paths.uninstallApp, "--run", root.uninstallItem.entry.id];
        runProc.running = true;
    }

    // Enter on the highlighted button.
    function pressUninstallButton(index) {
        if (root.uninstallPhase === "confirm")
            root.confirmUninstall(root.uninstallButtons[index] === "Yes");
        else if (root.uninstallPhase === "done")
            root.closeUninstall();
    }

    function uninstallKey(event) {
        const k = event.key;
        if (root.uninstallPhase === "confirm") {
            if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down
                    || k === Qt.Key_Tab || k === Qt.Key_Backtab)
                root.uninstallChoice = 1 - root.uninstallChoice;
            else if (k === Qt.Key_Y)
                root.confirmUninstall(true);
            else if (k === Qt.Key_N)
                root.confirmUninstall(false);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                root.pressUninstallButton(root.uninstallChoice);
        } else if (root.uninstallPhase === "done" && (k === Qt.Key_Return || k === Qt.Key_Enter)) {
            root.closeUninstall();
        }
    }

    Process {
        id: planProc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("default="))
                    root.uninstallDefaultYes = line === "default=y";
                else
                    root.addUninstallLine(line);
            }
        }
        onExited: code => {
            root.uninstallOk = false;
            root.uninstallPhase = code === 0 ? "confirm" : "done";
        }
    }

    Process {
        id: runProc
        stdout: SplitParser {
            onRead: line => root.addUninstallLine(line)
        }
        onExited: code => {
            root.uninstallOk = code === 0;
            if (code !== 0)
                root.addUninstallLine("Failed (exit " + code + ").");
            root.uninstallChoice = 0;
            root.uninstallPhase = "done";
        }
    }

    // Right-click menu entries for an item (empty: nothing to offer).
    function menuActions(item) {
        const list = [];
        if (item.kind === "app" || item.kind === "run")
            list.push({ "label": "Run as sudo", "callback": () => root.activate(item, true) });
        if (item.kind === "app" || item.kind === "file" || item.kind === "dir")
            list.push({ "label": "Open file location", "callback": () => root.openLocation(item) });
        if (item.kind === "app")
            list.push({ "label": "Uninstall", "callback": () => root.uninstall(item) });
        return list;
    }

    function openMenu(item, pos) {
        const actions = root.menuActions(item);
        if (actions.length === 0)
            return;
        contextMenu.actions = actions;
        contextMenu.x = Math.max(8, Math.min(card.width - contextMenu.width - 8, pos.x));
        contextMenu.y = Math.max(8, Math.min(card.height - contextMenu.height - 8, pos.y));
        contextMenu.visible = true;
    }

    // Return: a finished calculation is copied, otherwise the selection runs
    // (in run mode, typed text with no match runs as a command).
    function accept(asRoot) {
        if (root.answer !== "")
            root.copyAnswer();
        else if (root.items.length > 0)
            root.activate(root.items[root.selectedIndex], asRoot);
        else if (root.mode === "run")
            root.runText(root.query, asRoot);
    }

    Process {
        id: pathScan
        command: ["bash", "-c", "IFS=:; for d in $PATH; do [ -d \"$d\" ] && find -L \"$d\" -maxdepth 1 -type f -executable -printf '%f\\n' 2>/dev/null; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icon = Quickshell.iconPath("utilities-terminal", "application-x-executable");
                root.runItems = this.text.split("\n").filter(s => s.length > 0)
                    .map(c => ({ "kind": "run", "name": c, "fields": [], "icon": icon }));
            }
        }
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + root.filesFolder
        showDirsFirst: true
        showHidden: false
        showDotAndDotDot: false
        sortCaseSensitive: false
        onStatusChanged: if (status === FolderListModel.Ready) root.collectFiles()
        onCountChanged: if (status === FolderListModel.Ready) root.collectFiles()
    }

    function collectFiles() {
        const dirIcon = Quickshell.iconPath("folder", "inode-directory");
        const fileIcon = Quickshell.iconPath("text-x-generic", "application-x-executable");
        let list = [];
        for (let i = 0; i < folderModel.count; i++) {
            const isDir = folderModel.get(i, "fileIsDir");
            list.push({
                "kind": isDir ? "dir" : "file",
                "name": folderModel.get(i, "fileName"),
                "fields": [],
                "icon": isDir ? dirIcon : fileIcon,
                "path": folderModel.get(i, "filePath")
            });
        }
        root.fileItems = list;
    }

    Item {
        id: card
        anchors.fill: parent
        anchors.margins: root.shadowMargin

        readonly property int radius: 2 * root.em

        RectangularShadow {
            anchors.fill: parent
            radius: card.radius
            blur: 15
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
        }

        // Backdrop: blurred wallpaper under everything, the list side tinted.
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.background
            }

            Image {
                anchors.fill: parent
                source: "file://" + Paths.blurredWallpaper + "?" + root.wallpaperRevision
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                horizontalAlignment: Image.AlignLeft
                cache: false
                asynchronous: true
            }

            Rectangle {
                x: parent.width / 2
                width: parent.width / 2
                height: parent.height
                color: root.tint
            }
        }

        Rectangle {
            id: cardMask
            anchors.fill: parent
            radius: card.radius
            visible: false
            layer.enabled: true
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Left: search pill, calculator answer, mode buttons.
            ColumnLayout {
                // Half the card, including the 20px margins.
                Layout.preferredWidth: card.width / 2 - 40
                Layout.maximumWidth: card.width / 2 - 40
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.margins: 20
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: root.em
                    implicitHeight: 3.2 * root.em
                    radius: height / 2
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 1.4 * root.em
                        anchors.rightMargin: root.em
                        spacing: 0.5 * root.em

                        Text {
                            text: ""
                            color: Theme.on_surface
                            font.family: Theme.iconFontFamily
                            font.pixelSize: root.em
                        }

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: root.em
                            placeholderText: root.mode === "files" ? "Search " + root.displayFolder() : "Search"
                            placeholderTextColor: Theme.on_surface
                            selectByMouse: true
                            leftPadding: 0
                            rightPadding: 0
                            background: Item {}
                            onTextChanged: root.query = text

                            Keys.onPressed: event => {
                                if (root.uninstallPhase !== "") {
                                    root.uninstallKey(event);
                                    event.accepted = true;
                                    return;
                                }
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                const alt = event.modifiers & Qt.AltModifier;
                                const grid = root.gridView;
                                const row = grid ? root.gridColumns : 1;
                                if (root.mode === "emoji" && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
                                    root.cycleEmojiCategory(event.key === Qt.Key_PageDown ? 1 : -1);
                                } else if (grid && !ctrl && (event.key === Qt.Key_Right || event.key === Qt.Key_Left)) {
                                    root.sideMove(event.key === Qt.Key_Right ? 1 : -1);
                                } else if (event.key === Qt.Key_Down) {
                                    root.moveSelection(row);
                                } else if (event.key === Qt.Key_Up) {
                                    root.moveSelection(-row);
                                } else if (event.key === Qt.Key_PageDown) {
                                    root.moveSelection(grid ? 3 * row : 8);
                                } else if (event.key === Qt.Key_PageUp) {
                                    root.moveSelection(grid ? -3 * row : -8);
                                } else if (event.key === Qt.Key_Tab || (event.key === Qt.Key_Right && !ctrl)) {
                                    root.cycleMode(1);
                                } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Left && !ctrl)) {
                                    root.cycleMode(-1);
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && alt) {
                                    root.accept(true);
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ctrl) {
                                    if (root.mode === "run")
                                        root.runText(root.query);
                                    else
                                        root.accept();
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.accept();
                                } else if (event.key === Qt.Key_Backspace && root.mode === "files"
                                           && searchField.text === "" && root.filesFolder !== "/") {
                                    root.openFolder(root.parentFolder());
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Calculator answer, and the selected emoji in emoji mode.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        readonly property var item: root.mode === "emoji" ? root.items[root.selectedIndex] : undefined
                        anchors.centerIn: parent
                        width: parent.width - 2 * root.em
                        spacing: 4
                        visible: !!item && root.answer === ""

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: parent.item ? parent.item.emoji : ""
                            font.family: "Noto Color Emoji"
                            font.pixelSize: 4.5 * root.em
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.item ? parent.item.name : ""
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: root.em
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            style: Text.Outline
                            styleColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                        }
                    }

                    Rectangle {
                        id: answerCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: root.em
                        implicitHeight: answerColumn.implicitHeight + 1.6 * root.em
                        radius: 1.5 * root.em
                        color: answerHover.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95) : root.tint
                        border.color: Theme.primary
                        border.width: 1
                        opacity: root.answer !== "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        // Keeps the last answer on screen while it fades out.
                        property string shown: ""
                        Connections {
                            target: root
                            function onAnswerChanged() {
                                if (root.answer !== "")
                                    answerCard.shown = root.answer;
                            }
                        }

                        HoverHandler {
                            id: answerHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: if (root.answer !== "") root.copyAnswer()
                        }

                        ColumnLayout {
                            id: answerColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 1.4 * root.em
                            anchors.rightMargin: 1.4 * root.em
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "="
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: root.em
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 2.6 * root.em
                                text: answerCard.shown
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 2.4 * root.em
                                font.bold: true
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: root.em
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Return or click to copy"
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // Mode buttons.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 1.5 * root.em
                    spacing: root.em

                    Repeater {
                        model: root.modes

                        delegate: Rectangle {
                            id: modeButton
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.modeIndex === index

                            Layout.fillWidth: true
                            implicitHeight: 3.2 * root.em
                            radius: height / 2
                            color: selected ? Theme.surface
                                : (modeHover.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5) : root.tint)

                            Text {
                                anchors.centerIn: parent
                                text: modeButton.modelData.glyph
                                color: Theme.on_surface
                                font.family: Theme.iconFontFamily
                                font.pixelSize: root.em
                            }

                            HoverHandler {
                                id: modeHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                onTapped: root.setMode(modeButton.index)
                            }
                            ToolTip.visible: modeHover.hovered
                            ToolTip.delay: 600
                            ToolTip.text: modeButton.modelData.label
                        }
                    }
                }
            }

            // Right: results as a list or a grid, under the emoji category
            // tabs in emoji mode.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 1.5 * root.em
                spacing: root.em

                // Category tabs; none is selected while searching (the
                // results then come from every category).
                RowLayout {
                    visible: root.mode === "emoji"
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: Emoji.CATEGORIES

                        delegate: Rectangle {
                            id: categoryTab
                            required property var modelData
                            required property int index
                            readonly property bool selected: !root.searching && root.emojiCategory === index

                            Layout.fillWidth: true
                            implicitHeight: 2.6 * root.em
                            radius: height / 2
                            color: selected ? Theme.surface
                                : (categoryHover.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.4) : "transparent")

                            Text {
                                anchors.centerIn: parent
                                text: categoryTab.modelData.icon
                                font.family: "Noto Color Emoji"
                                font.pixelSize: 1.2 * root.em
                                opacity: categoryTab.selected || categoryHover.hovered ? 1 : 0.7
                            }

                            HoverHandler {
                                id: categoryHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                onTapped: root.setEmojiCategory(categoryTab.index)
                            }
                            ToolTip.visible: categoryHover.hovered
                            ToolTip.delay: 600
                            ToolTip.text: categoryTab.modelData.label
                        }
                    }
                }

                ListView {
                    id: resultList
                    visible: !root.gridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0.5 * root.em
                    model: root.gridView ? [] : root.items
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.selectedIndex === index
                        readonly property bool isEmoji: modelData.kind === "emoji"

                        width: ListView.view.width
                        implicitHeight: 4 * root.em
                        radius: 1.5 * root.em
                        color: selected ? Theme.surface
                            : (rowHover.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.4) : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 0.5 * root.em
                            spacing: 10

                            Image {
                                visible: !row.isEmoji
                                Layout.preferredWidth: 3 * root.em
                                Layout.preferredHeight: 3 * root.em
                                source: row.isEmoji ? "" : (row.modelData.icon ?? "")
                                sourceSize.width: 3 * root.em
                                sourceSize.height: 3 * root.em
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            Text {
                                visible: row.isEmoji
                                Layout.preferredWidth: 3 * root.em
                                horizontalAlignment: Text.AlignHCenter
                                text: row.modelData.emoji ?? ""
                                font.family: "Noto Color Emoji"
                                font.pixelSize: 1.8 * root.em
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name ?? ""
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: root.em
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler {
                            id: rowHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                root.selectedIndex = row.index;
                                root.activate(row.modelData);
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => {
                                root.selectedIndex = row.index;
                                root.openMenu(row.modelData, row.mapToItem(card, eventPoint.position));
                            }
                        }
                    }
                }

                GridView {
                    id: resultGrid
                    visible: root.gridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: Math.floor(width / root.gridColumns)
                    // App cells leave room for two lines of name under the icon.
                    cellHeight: root.mode === "emoji" ? cellWidth : cellWidth + root.em
                    model: root.gridView ? root.items : []
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.selectedIndex === index
                        readonly property bool isEmoji: modelData.kind === "emoji"

                        width: resultGrid.cellWidth
                        height: resultGrid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: root.em
                            color: cell.selected ? Theme.surface
                                : (cellHover.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.4) : "transparent")
                        }

                        Text {
                            visible: cell.isEmoji
                            anchors.centerIn: parent
                            text: cell.modelData.emoji ?? ""
                            font.family: "Noto Color Emoji"
                            font.pixelSize: 1.8 * root.em
                        }

                        ColumnLayout {
                            visible: !cell.isEmoji
                            anchors.centerIn: parent
                            width: parent.width - root.em
                            spacing: 4

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 3 * root.em
                                Layout.preferredHeight: 3 * root.em
                                source: cell.isEmoji ? "" : (cell.modelData.icon ?? "")
                                sourceSize.width: 3 * root.em
                                sourceSize.height: 3 * root.em
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: cell.modelData.name ?? ""
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler {
                            id: cellHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                root.selectedIndex = cell.index;
                                root.activate(cell.modelData);
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => {
                                root.selectedIndex = cell.index;
                                root.openMenu(cell.modelData, cell.mapToItem(card, eventPoint.position));
                            }
                        }
                    }
                }
            }
        }

        // 1px primary border on top.
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.color: Theme.primary
            border.width: 1
        }

        // Uninstall: what the script says, and the confirmation buttons.
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: Theme.background
            visible: root.uninstallPhase !== ""

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 2 * root.em
                spacing: root.em

                Text {
                    Layout.fillWidth: true
                    text: root.uninstallPhase === "planning" ? "Checking…"
                        : (root.uninstallPhase === "confirm" ? (root.uninstallLines[0] ?? "")
                        : "Uninstall " + (root.uninstallItem?.name ?? ""))
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 1.4 * root.em
                    font.bold: true
                    elide: Text.ElideRight
                }

                ListView {
                    id: uninstallLog
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    // The first line is the title while confirming.
                    model: root.uninstallPhase === "confirm" ? root.uninstallLines.slice(1) : root.uninstallLines
                    onCountChanged: positionViewAtEnd()
                    delegate: Text {
                        required property string modelData
                        width: uninstallLog.width
                        text: modelData
                        wrapMode: Text.Wrap
                        color: root.uninstallPhase === "done" && !root.uninstallOk ? Theme.error : Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: root.em
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: root.em
                    visible: root.uninstallPhase === "confirm" || root.uninstallPhase === "done"

                    Repeater {
                        model: root.uninstallButtons

                        PanelButton {
                            required property int index
                            required property string modelData
                            text: modelData
                            filled: index === root.uninstallChoice
                            focusPolicy: Qt.NoFocus
                            onHoveredChanged: if (hovered) root.uninstallChoice = index
                            onClicked: root.pressUninstallButton(index)
                        }
                    }
                }
            }
        }

        // Closes the right-click menu on an outside click.
        MouseArea {
            anchors.fill: parent
            visible: contextMenu.visible
            acceptedButtons: Qt.AllButtons
            onPressed: contextMenu.visible = false
        }

        InlineMenu {
            id: contextMenu
            onCloseRequested: contextMenu.visible = false
        }
    }
}
