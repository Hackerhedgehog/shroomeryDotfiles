pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared

// Accent palette state shared by the QuickSettingsPanel and the SettingsApp.
// apply-theme.sh records each choice in shroomery/settings/ once matugen
// accepted it; the files are watched, so the picker shows what is live.
QtObject {
    id: root

    readonly property var accentSchemes: [
        { value: "scheme-tonal-spot", label: "Tonal spot" },
        { value: "scheme-vibrant", label: "Vibrant" },
        { value: "scheme-expressive", label: "Expressive" },
        { value: "scheme-content", label: "Content" },
        { value: "scheme-fidelity", label: "Fidelity" },
        { value: "scheme-fruit-salad", label: "Fruit salad" },
        { value: "scheme-rainbow", label: "Rainbow" },
        { value: "scheme-neutral", label: "Neutral" },
        { value: "scheme-monochrome", label: "Monochrome" }
    ]
    // "wallpaper" or a #rrggbb color.
    readonly property string accentSource: {
        const v = accentFile.text().trim().toLowerCase()
        return /^#[0-9a-f]{6}$/.test(v) ? v : "wallpaper"
    }
    readonly property int accentIndex: {
        const v = parseInt(accentIndexFile.text().trim())
        return isNaN(v) ? 0 : v
    }
    readonly property int accentSchemeIndex: {
        const v = accentSchemeFile.text().trim()
        return Math.max(0, root.accentSchemes.findIndex(s => s.value === v))
    }
    // The current wallpaper's candidate colors, most dominant first.
    readonly property var wallpaperColors: wallpaperColorsFile.text().split("\n")
        .map(s => s.trim()).filter(s => /^#[0-9A-Fa-f]{6}$/.test(s))

    property FileView accentFile: FileView {
        path: Paths.accentSetting
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    property FileView accentIndexFile: FileView {
        path: Paths.accentIndexSetting
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    property FileView accentSchemeFile: FileView {
        path: Paths.accentSchemeSetting
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    // Replaced by rename, and missing until the first wallpaper.sh run, so it
    // is also re-read whenever a picker is shown.
    property FileView wallpaperColorsFile: FileView {
        path: Paths.wallpaperColors
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    function reload(): void {
        accentFile.reload()
        accentIndexFile.reload()
        accentSchemeFile.reload()
        wallpaperColorsFile.reload()
    }

    function applyAccent(hex: string): void {
        Quickshell.execDetached([Paths.applyTheme, "--color", hex])
    }

    function applyWallpaperAccent(index: int): void {
        Quickshell.execDetached([Paths.applyTheme, "--wallpaper", String(index)])
    }

    function applyAccentScheme(scheme: string): void {
        Quickshell.execDetached([Paths.applyTheme, "--scheme", scheme])
    }
}
