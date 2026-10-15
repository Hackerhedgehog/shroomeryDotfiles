import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.SettingsApp

// Accent palette. Every choice regenerates the whole matugen palette through
// apply-theme.sh, which records it in shroomery/settings/ (so it survives a
// reboot): one of the wallpaper's own colors (most dominant first), a fixed
// color, and the scheme type the palette is built with. The live choice wears
// a ring.
ColumnLayout {
    id: picker
    spacing: 10

    readonly property var swatches: [
        "#fc2f04", "#e8590c", "#f59f00", "#74b816",
        "#37b24d", "#0ca678", "#1098ad", "#1c7ed6",
        "#4263eb", "#7048e8", "#ae3ec9", "#d6336c"
    ]

    component Swatch: Rectangle {
        id: swatch
        property bool selected: false
        signal clicked()

        width: 28
        height: 28
        radius: 14
        border.color: Theme.on_background
        border.width: selected || swatchMouse.containsMouse ? 2 : 0

        // Inner ring: keeps the selection visible on swatches close to the
        // border color.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            color: "transparent"
            border.color: Theme.background
            border.width: 2
            visible: swatch.selected
        }

        MouseArea {
            id: swatchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: swatch.clicked()
        }
    }

    Text {
        text: "Accent"
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 16
    }

    FieldLabel { text: "From the wallpaper" }

    Flow {
        Layout.fillWidth: true
        spacing: 10

        Repeater {
            model: SettingsState.wallpaperColors
            delegate: Swatch {
                required property string modelData
                required property int index
                color: modelData
                selected: SettingsState.accentSource === "wallpaper" && SettingsState.accentIndex === index
                onClicked: SettingsState.applyWallpaperAccent(index)
            }
        }

        // No color list yet (wallpaper.sh writes it): one "wallpaper" swatch.
        Swatch {
            visible: SettingsState.wallpaperColors.length === 0
            color: Theme.primary
            selected: SettingsState.accentSource === "wallpaper"
            onClicked: SettingsState.applyWallpaperAccent(0)
        }
    }

    FieldLabel { text: "Fixed color" }

    Flow {
        Layout.fillWidth: true
        spacing: 10

        Repeater {
            model: picker.swatches
            delegate: Swatch {
                required property string modelData
                color: modelData
                selected: SettingsState.accentSource === modelData
                onClicked: SettingsState.applyAccent(modelData)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FieldLabel {
            text: "Style"
            Layout.fillWidth: true
        }

        FieldCombo {
            Layout.preferredWidth: 160
            compact: true
            model: SettingsState.accentSchemes.map(s => s.label)
            boundIndex: SettingsState.accentSchemeIndex
            onActivated: index => SettingsState.applyAccentScheme(SettingsState.accentSchemes[index].value)
        }
    }
}
