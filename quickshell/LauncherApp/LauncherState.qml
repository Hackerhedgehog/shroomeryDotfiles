pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared

// The launcher's view settings: whether the apps and emoji tabs show a grid or
// a list. Kept in shroomery/settings/launcher-view.json
// (Paths.launcherViewSettings), e.g. { "appsGrid": false, "emojiGrid": true };
// a missing key or file means the default. Toggled from the SettingsApp.
Singleton {
    id: root

    property bool appsGrid: false
    property bool emojiGrid: true

    function setAppsGrid(on: bool): void {
        appsGrid = on;
        save();
    }

    function setEmojiGrid(on: bool): void {
        emojiGrid = on;
        save();
    }

    function save(): void {
        viewFile.setText(JSON.stringify({ "appsGrid": appsGrid, "emojiGrid": emojiGrid }, null, 4) + "\n");
    }

    function apply(raw: string): void {
        let parsed = {};
        try {
            parsed = JSON.parse(raw) || {};
        } catch (e) {
            console.warn("launcher-view.json: " + e);
        }
        appsGrid = parsed.appsGrid === true;
        emojiGrid = parsed.emojiGrid !== false;
    }

    FileView {
        id: viewFile
        path: Paths.launcherViewSettings
        blockLoading: true
        printErrors: false
        watchChanges: true
        onLoaded: root.apply(text())
        onFileChanged: reload()
    }
}
