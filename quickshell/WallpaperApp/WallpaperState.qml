pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.shared
// Wallpaper folder, transition, current image and apply actions used by the panel.
// Two tabs: Static (images in the folder) and Animated (videos/GIFs in its animated/
// subfolder, played by mpvpaper through shroomery's animated-wallpaper.sh).
Singleton {
    id: root

    readonly property string defaultFolder: Paths.wallpaperDefaultFolder
    readonly property string folderSettingPath: Paths.wallpaperFolderSetting
    readonly property string transitionSettingPath: Paths.wallpaperTransitionSetting
    readonly property string currentCachePath: Paths.wallpaperCache
    readonly property string wallpaperScript: Paths.setWallpaper
    readonly property string effectSettingPath: Paths.wallpaperEffectSetting
    readonly property string randomSettingPath: Paths.wallpaperRandomSetting
    readonly property string effectsDir: Paths.wallpaperEffectsDir
    readonly property string clearCacheScript: Paths.clearWallpaperCache
    readonly property string thumbnailsDir: Paths.wallpaperThumbnails
    readonly property string thumbnailsScript: Paths.wallpaperThumbnailsScript
    readonly property var transitionEffects: ["simple", "left", "right", "top", "bottom", "center", "any", "random", "none"]
    // Same list as shroomery lib.sh is_animated.
    readonly property var animatedExtensions: ["mp4", "webm", "mkv", "mov", "m4v", "avi", "gif"]
    readonly property var imageExtensions: ["jpg", "jpeg", "png"]
    readonly property var cropGravities: ["center", "top-left", "top", "top-right", "left", "right", "bottom-left", "bottom", "bottom-right"]

    property bool panelOpen: false
    property bool applying: false
    property bool updateTheming: true
    property string wallpaperFolder: defaultFolder
    property string folderSettingText: defaultFolder
    property string transitionEffect: "simple"
    // "off" first, then the scripts in shroomery/effects/.
    property var wallpaperEffects: ["off"]
    property string wallpaperEffect: "off"
    // Re-apply a random wallpaper every randomInterval seconds while enabled.
    readonly property int defaultRandomInterval: 300
    readonly property int minRandomInterval: 10
    property bool randomEnabled: false
    property int randomInterval: defaultRandomInterval
    property string currentWallpaper: ""
    // A still of it (the animated wallpaper's first frame) for the preview.
    property string stillWallpaper: ""
    readonly property bool currentAnimated: isAnimated(currentWallpaper)
    // The panel's tab; Random picks from this tab's folder.
    property bool animatedTab: false
    readonly property string animatedFolder: wallpaperFolder.replace(/\/+$/, "") + "/animated"
    readonly property string activeFolder: animatedTab ? animatedFolder : wallpaperFolder
    property string query: ""
    property string selectedMonitor: "All"
    property string cropGravity: "center"
    property string pendingPath: ""
    property string errorMessage: ""
    property string bannerMessage: ""
    property int folderEpoch: 0
    // Bumped when wallpaper-thumbnails.sh finishes, so tiles retry thumbnails that were missing.
    property int thumbnailEpoch: 0
    readonly property bool thumbnailsRunning: thumbProc.running
    property bool _thumbnailsDirty: false
    property string _applyStderr: ""

    readonly property int transitionIndex: {
        const idx = transitionEffects.indexOf(transitionEffect);
        return idx < 0 ? 0 : idx;
    }

    readonly property int effectIndex: {
        const idx = wallpaperEffects.indexOf(wallpaperEffect);
        return idx < 0 ? 0 : idx;
    }

    readonly property int cropIndex: {
        const idx = cropGravities.indexOf(cropGravity);
        return idx < 0 ? 0 : idx;
    }

    readonly property string currentName: {
        const path = currentWallpaper;
        if (path === "")
            return "";
        const parts = path.split("/");
        return parts[parts.length - 1];
    }

    readonly property string folderName: {
        const path = wallpaperFolder.replace(/\/+$/, "");
        if (path === "")
            return "";
        const parts = path.split("/");
        return parts[parts.length - 1];
    }

    FileView {
        id: folderFile
        path: root.folderSettingPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: root._ingestFolder(text())
        onFileChanged: reload()
        onSaved: root._ingestFolder(text())
    }

    FileView {
        id: transitionFile
        path: root.transitionSettingPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: root._ingestTransition(text())
        onFileChanged: reload()
        onSaved: root._ingestTransition(text())
    }

    FileView {
        id: effectFile
        path: root.effectSettingPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        // The re-apply right after setEffect() must see the new value.
        blockWrites: true
        onLoaded: root._ingestEffect(text())
        onFileChanged: reload()
        onSaved: root._ingestEffect(text())
        onLoadFailed: root.wallpaperEffect = "off"
    }

    FileView {
        id: randomFile
        path: root.randomSettingPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: root._ingestRandom(text())
        onFileChanged: reload()
        onSaved: root._ingestRandom(text())
    }

    Timer {
        id: randomTimer
        interval: root.randomInterval * 1000
        repeat: true
        running: root.randomEnabled
        onTriggered: root.applyRandom()
    }

    Process {
        id: effectsProc
        command: ["find", root.effectsDir, "-maxdepth", "1", "-type", "f", "-printf", "%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").map(n => n.trim()).filter(n => n !== "").sort();
                root.wallpaperEffects = ["off"].concat(names);
            }
        }
    }

    Process {
        id: clearProc
        onExited: exitCode => {
            root.applying = false;
            currentFile.reload();
            root.refreshThumbnails();
            root.errorMessage = exitCode === 0 ? "" : "Could not clear the wallpaper cache.";
            root.bannerMessage = exitCode === 0 ? "Cache cleared, default wallpaper restored." : "";
        }
    }

    FileView {
        id: stillFile
        path: Paths.stillWallpaper
        watchChanges: true
        printErrors: false
        onLoaded: root.stillWallpaper = root.expandPath(text())
        onFileChanged: reload()
        onLoadFailed: root.stillWallpaper = ""
    }

    FileView {
        id: currentFile
        path: root.currentCachePath
        watchChanges: true
        printErrors: false
        onLoaded: root._ingestCurrent(text())
        onFileChanged: reload()
        onLoadFailed: root.currentWallpaper = ""
    }

    Process {
        id: thumbProc
        onExited: {
            root.thumbnailEpoch++;
            if (root._thumbnailsDirty)
                root.refreshThumbnails();
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: applyErr
            onStreamFinished: root._applyStderr = text
        }
        onExited: exitCode => {
            root.applying = false;
            root.pendingPath = "";
            currentFile.reload();
            if (exitCode !== 0) {
                const detail = root._applyStderr.trim();
                root.errorMessage = detail !== "" ? detail.split("\n").pop() : "Could not set the wallpaper.";
                return;
            }
            root.errorMessage = "";
            root.bannerMessage = "Wallpaper updated.";
        }
    }

    function expandPath(value) {
        return String(value || "").trim().replace(/^file:\/\//, "").replace(/~|\$HOME/g, Paths.home);
    }

    function isAnimated(filePath) {
        const m = String(filePath || "").toLowerCase().match(/\.([a-z0-9]+)$/);
        return m !== null && animatedExtensions.indexOf(m[1]) >= 0;
    }

    function isCurrent(filePath) {
        if (currentWallpaper === "" || !filePath)
            return false;
        return expandPath(filePath) === expandPath(currentWallpaper);
    }

    function setFolder(value) {
        const raw = String(value || "").trim();
        if (raw === "")
            return;
        folderFile.setText(raw + "\n");
    }

    function setTransition(effect) {
        const cleaned = String(effect || "").trim();
        const next = transitionEffects.indexOf(cleaned) >= 0 ? cleaned : "simple";
        transitionFile.setText(next + "\n");
    }

    function setMonitor(name) {
        selectedMonitor = name && name !== "" ? name : "All";
    }

    function setCropGravity(value) {
        cropGravity = cropGravities.indexOf(value) >= 0 ? value : "center";
    }

    function reloadFolder() {
        folderEpoch++;
        Qt.callLater(() => {
            folderEpoch++;
        });
        currentFile.reload();
        stillFile.reload();
        folderFile.reload();
        transitionFile.reload();
        effectFile.reload();
        effectsProc.running = true;
        refreshThumbnails();
    }

    // Renders missing grid previews in the background; reruns once if asked again meanwhile.
    function refreshThumbnails() {
        if (thumbProc.running) {
            _thumbnailsDirty = true;
            return;
        }
        _thumbnailsDirty = false;
        thumbProc.exec(["bash", thumbnailsScript, activeFolder]);
    }

    // Same layout as wallpaper-thumbnails.sh: md5(folder)/md5("<file name>:<size in bytes>").jpg.
    readonly property string _thumbnailFolderDir: thumbnailsDir + "/" + Qt.md5(activeFolder)
    function thumbnailUrl(fileName, fileSize) {
        return "file://" + _thumbnailFolderDir + "/" + Qt.md5(fileName + ":" + fileSize) + ".jpg";
    }

    function applyPath(filePath) {
        if (applying || !filePath)
            return;
        applying = true;
        errorMessage = "";
        bannerMessage = "";
        pendingPath = filePath;
        _applyStderr = "";
        applyProc.exec(["bash", wallpaperScript, filePath].concat(_optionArgs()));
    }

    function _optionArgs() {
        const args = [];
        if (selectedMonitor !== "" && selectedMonitor !== "All")
            args.push("--monitor", selectedMonitor);
        args.push("--crop-gravity", cropGravity);
        if (!updateTheming)
            args.push("--skip-theming");
        return args;
    }

    // Random rotation stays with the kind of wallpaper on screen; the Random button uses the tab.
    function applyRandom(folder) {
        if (applying)
            return;
        const from = folder || (currentAnimated ? animatedFolder : wallpaperFolder);
        applying = true;
        errorMessage = "";
        bannerMessage = "";
        pendingPath = "";
        _applyStderr = "";
        applyProc.exec(["bash", wallpaperScript, "--random", from].concat(_optionArgs()));
    }

    // Store the effect and re-apply the current wallpaper so it shows at once.
    function setEffect(effect) {
        const next = wallpaperEffects.indexOf(effect) >= 0 ? effect : "off";
        if (next === wallpaperEffect)
            return;
        effectFile.setText(next + "\n");
        // Effects only apply to still images.
        if (currentWallpaper !== "" && !currentAnimated)
            applyPath(currentWallpaper);
    }

    function setRandomEnabled(enabled) {
        _writeRandom(!!enabled, randomInterval);
    }

    function setRandomInterval(seconds) {
        const n = Math.round(Number(seconds));
        _writeRandom(randomEnabled, isNaN(n) ? defaultRandomInterval : Math.max(minRandomInterval, n));
    }

    function _writeRandom(enabled, interval) {
        randomFile.setText(JSON.stringify({
            enabled: enabled,
            interval: interval
        }, null, 2) + "\n");
    }

    // Removes ~/.cache/shroomery (blurred/square variants, effect copies) and
    // restores the default wallpaper.
    function clearCache() {
        if (applying)
            return;
        applying = true;
        errorMessage = "";
        bannerMessage = "";
        clearProc.exec(["bash", clearCacheScript]);
    }

    onActiveFolderChanged: refreshThumbnails()

    Component.onCompleted: effectsProc.running = true

    function _ingestFolder(raw) {
        const rawText = String(raw || "").trim();
        folderSettingText = rawText !== "" ? rawText : defaultFolder;
        const next = expandPath(folderSettingText);
        wallpaperFolder = next !== "" ? next : defaultFolder;
    }

    function _ingestTransition(raw) {
        const cleaned = String(raw || "").trim();
        transitionEffect = transitionEffects.indexOf(cleaned) >= 0 ? cleaned : "simple";
    }

    function _ingestEffect(raw) {
        const cleaned = String(raw || "").trim();
        wallpaperEffect = cleaned !== "" ? cleaned : "off";
    }

    function _ingestRandom(raw) {
        let data = {};
        try {
            data = JSON.parse(String(raw || "{}"));
        } catch (e) {}
        randomEnabled = data.enabled === true;
        const n = Number(data.interval);
        randomInterval = isNaN(n) || n <= 0 ? defaultRandomInterval : Math.max(minRandomInterval, Math.round(n));
    }

    function _ingestCurrent(raw) {
        currentWallpaper = expandPath(raw);
    }
}
