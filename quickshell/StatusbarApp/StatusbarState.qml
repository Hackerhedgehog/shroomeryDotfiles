pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
// Owns the status bar's settings file. Split out of StatusbarWindow so the
// bar can be instantiated once per monitor (see StatusbarBars.qml) while the
// file is still read and written exactly once.
//
// The file is shroomery/settings/statusbar.json (Paths.statusbarSettings),
// merged over the built-in defaults below, so a partial or missing file still
// leaves every value defined. The SettingsApp switches write enabled /
// alwaysExpanded back into it. StatusbarApp/statusbar.json documents every key.
QtObject {
    id: root

    readonly property var defaultSettings: ({
        "bar":    { "height": 40, "reservedHeight":72, "enabled": true, "alwaysExpanded": true },
        "pill":   { "collapsedWidth": 0, "expandedWidth": 680, "radius": 12, "animationDuration": 350 },
        // centerLeft/centerRight flank the center group, which stays centered
        // on the bar.
        "modules":{ "left": ["workspaces"],
                    "centerLeft": ["launcher", "taskbar"],
                    "center": ["clock"],
                    "centerRight": ["systemtray"],
                    "right": ["battery", "volume", "notifications", "bluetooth", "network", "settings", "power"] },
        "border": { "width": 2, "colorTop": "", "colorBottom": "" },
        "opacity":{ "collapsed": 0.6, "expanded": 0.8 },
        // format: time everywhere (bar, dashboard, notifications; set in the
        // TimeApp), dateFormat: the bar's date, longDateFormat: the dashboard's.
        "clock":  { "format": "HH:mm", "dateFormat": "ddd, dd MMM", "longDateFormat": "dddd, d MMMM yyyy" },
        "taskbar":{ "enabled": true, "iconSize": 22, "pinned": [] }
    })

    property var settings: defaultSettings

    // Changes made by hand are not picked up automatically; re-read with
    //   qs ipc call statusbar reload
    property FileView settingsFile: FileView {
        id: settingsFile
        path: Paths.statusbarSettings
        blockLoading: true
        printErrors: false
        onLoaded: root.applySettings()
        onLoadFailed: root.applySettings()
    }

    function reloadSettings(): void {
        settingsFile.reload()
        applySettings()
    }

    // Parse a settings JSON document that may contain a /* ... */ comment block
    // and — being hand-edited — trailing commas before a closing } or ], which
    // strict JSON.parse rejects. Returns the parsed object, or undefined when the
    // text is empty or cannot be parsed even after that cleanup. Never throws.
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
                // Tolerate trailing commas: ",}" / ",]" (optional whitespace).
                return JSON.parse(raw.replace(/,(\s*[}\]])/g, "$1"))
            } catch (e2) {
                console.warn("statusbar settings: could not parse a file,"
                    + " ignoring it:", e2)
                return undefined
            }
        }
    }

    // Merge one JSON document (given as text) over an already-built settings
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

    // Rebuild the settings object: the built-in defaults with the file merged
    // on top. An explicit masterText can be passed (e.g. right after a switch
    // writes the file) so the merge does not depend on the FileView buffer
    // having refreshed yet.
    function applySettings(masterText): void {
        let merged = JSON.parse(JSON.stringify(root.defaultSettings))
        let text = (masterText !== undefined) ? masterText : settingsFile.text()
        mergeSettings(merged, text)
        root.settings = merged
    }

    // Persist a bar.<key> boolean into the settings file and return the updated
    // text. A regex replace is used when the key is already present (so the
    // file's formatting/comments are kept); when the key is missing it falls
    // back to a JSON rewrite of the parsed document. If the file cannot be
    // parsed at all the write is skipped rather than replaced with an empty
    // object, so a malformed hand-edited file is never wiped — its current text
    // is returned unchanged.
    function persistBarFlag(key, on): string {
        let file = settingsFile
        let src = file.text()
        let re = new RegExp('("' + key + '"\\s*:\\s*)(true|false)')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, "$1" + (on ? "true" : "false"))
        } else {
            let obj = root.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                // Unparseable and non-empty: don't destroy the user's file.
                console.warn("statusbar settings: settings file is not valid"
                    + " JSON; leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj.bar === undefined)
                obj.bar = {}
            obj.bar[key] = on
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    // Persist the enabled state into the settings file and apply it. applySettings re-parses the
    // updated text, which updates settings.bar.enabled and therefore the
    // barEnabled binding in the window.
    function setEnabled(on: bool): void {
        applySettings(persistBarFlag("enabled", on))
    }

    // Rewrite one group.key of the settings file through a JSON round trip and
    // apply it. Used for the taskbar values: unlike persistBarFlag this cannot
    // patch the text in place ("enabled" also exists under "bar", and the pinned
    // list is an array), so a comment block in the file is lost. An unparseable,
    // non-empty file is left untouched.
    function persistValue(group, key, value): void {
        let src = settingsFile.text()
        let obj = root.parseSettings(src)
        if (obj === undefined && src && src.trim() !== "") {
            console.warn("statusbar settings: settings file is not valid JSON;"
                + " not writing " + group + "." + key + ".")
            return
        }
        if (typeof obj !== "object" || obj === null)
            obj = {}
        if (obj[group] === undefined)
            obj[group] = {}
        obj[group][key] = value
        let updated = JSON.stringify(obj, null, 4) + "\n"
        settingsFile.setText(updated)
        applySettings(updated)
    }

    // Show/hide the taskbar module (SettingsApp switch).
    function setTaskbarEnabled(on: bool): void {
        persistValue("taskbar", "enabled", on)
    }

    // Persist the taskbar's own pinned app list.
    function setTaskbarPinned(list): void {
        persistValue("taskbar", "pinned", list)
    }

    // Persist the alwaysExpanded state into the settings file and apply it.
    // Mirrors setEnabled.
    function setAlwaysExpanded(on: bool): void {
        applySettings(persistBarFlag("alwaysExpanded", on))
    }
}
