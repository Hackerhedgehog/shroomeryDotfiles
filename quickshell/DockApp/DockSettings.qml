pragma Singleton

import Quickshell
import Quickshell.Io
import qs.shared
// The dock's settings file, its parsed contents and the writes back into it.
//
// This lives outside DockWindow because the "enabled" flag decides whether a
// DockWindow exists at all: DockLoader reads it here to instantiate the dock
// (or not), and the dock IPC — which has to work while the dock is disabled —
// writes it here.
Singleton {
    id: root

    // The settings file is shroomery/settings/dock.json (Paths.dockSettings),
    // merged over the built-in defaults below, so a partial or missing file
    // still leaves every value defined. Pin/unpin, enable and autohide write
    // back into it. DockApp/dock.json documents these defaults and must be kept
    // in sync with them.
    readonly property var defaultSettings: ({
        "dock":   { "enabled": true, "autohide": false, "iconSize": 32,
                    "spacing": 8, "marginBottom": 10, "reserveSpace": true },
        "pill":   { "radius": 16, "padding": 12, "animationDuration": 350 },
        "border": { "width": 2, "colorTop": "", "colorBottom": "" },
        "opacity":{ "normal": 0.7 },
        "apps":   { "pinned": [] }
    })

    property var settings: defaultSettings

    readonly property bool enabled: settings.dock.enabled
    readonly property bool autohide: settings.dock.autohide

    FileView {
        id: settingsFile
        path: Paths.dockSettings
        blockLoading: true
        printErrors: false
        onLoaded: root.applySettings()
        onLoadFailed: root.applySettings()
    }

    function reloadSettings(): void {
        settingsFile.reload()
        console.log("Dock reload: re-reading dock settings")
        applySettings()
    }

    // Parse a settings document that may carry a /* ... */ comment block and —
    // being hand-edited — trailing commas, which strict JSON.parse rejects.
    // Returns undefined when the text is empty or unparseable. Never throws.
    function parseSettings(src) {
        if (!src)
            return undefined
        let raw = src.replace(/\/\*[\s\S]*?\*\//g, "")
        if (raw.trim() === "")
            return undefined
        try {
            return JSON.parse(raw)
        } catch (e) {
            try {
                return JSON.parse(raw.replace(/,(\s*[}\]])/g, "$1"))
            } catch (e2) {
                console.warn("dock settings: could not parse a file,"
                    + " ignoring it:", e2)
                return undefined
            }
        }
    }

    // Merge one settings document (as text) over an already-built settings
    // object, key by key. Empty or unparseable text is ignored so a
    // missing/partial file never clears previously merged values.
    function mergeSettings(merged, src): void {
        let parsed = parseSettings(src)
        if (parsed === undefined)
            return
        for (let group in parsed)
            for (let key in parsed[group])
                if (merged[group] !== undefined)
                    merged[group][key] = parsed[group][key]
    }

    // Rebuild the settings object: built-in defaults with the settings file merged
    // on top. An explicit masterText can be passed (e.g. right after a write) so
    // the merge does not depend on the FileView buffer having refreshed yet.
    function applySettings(masterText): void {
        let merged = JSON.parse(JSON.stringify(root.defaultSettings))
        let text = (masterText !== undefined) ? masterText : settingsFile.text()
        mergeSettings(merged, text)
        root.settings = merged
    }

    // Persist a dock.<key> boolean into the settings file and return the updated
    // text. A regex replace keeps the file's formatting and comments intact when
    // the key is already present; otherwise the parsed document is rewritten. An
    // unparseable, non-empty file is left untouched rather than overwritten.
    function persistDockFlag(key, on): string {
        let file = settingsFile
        let src = file.text()
        let re = new RegExp('("' + key + '"\\s*:\\s*)(true|false)')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, "$1" + (on ? "true" : "false"))
        } else {
            let obj = root.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                console.warn("dock settings: settings file is not valid JSON;"
                    + " leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj.dock === undefined)
                obj.dock = {}
            obj.dock[key] = on
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    // Persist the pinned app list into the settings file. Unlike the boolean flags
    // this always rewrites the JSON document (an array cannot be patched in
    // place with a regex without mangling hand-formatted files), so a comment
    // block in the settings file is lost on the first pin/unpin. An unparseable,
    // non-empty file is left untouched.
    function persistPinned(list): void {
        let file = settingsFile
        let src = file.text()
        let obj = root.parseSettings(src)
        if (obj === undefined && src && src.trim() !== "") {
            console.warn("dock settings: settings file is not valid JSON;"
                + " not writing the pinned list.")
            return
        }
        if (typeof obj !== "object" || obj === null)
            obj = {}
        if (obj.apps === undefined)
            obj.apps = {}
        obj.apps.pinned = list
        let updated = JSON.stringify(obj, null, 4) + "\n"
        file.setText(updated)
        applySettings(updated)
    }

    function setEnabled(on: bool): void {
        applySettings(persistDockFlag("enabled", on))
    }

    function setAutohide(on: bool): void {
        applySettings(persistDockFlag("autohide", on))
    }
}
