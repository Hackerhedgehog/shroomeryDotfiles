import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.VisualizerApp
import qs.shared
import qs.shared.ui
import qs.SettingsApp
import qs.StatusbarApp
import qs.LauncherApp

// Quick-settings panel: theme controls, night light, sliders, the accent
// palette, media players and the statusbar/taskbar/launcher grid/gamemode/
// fastfetch switches.
// The panel the status bar grows into from the gear button (hover), like
// AudioApp / BluetoothApp / NetworkApp.
PopoutPanel {
    id: root

    implicitWidth: standardWidth
    implicitHeight: Math.min(maxHeight, content.implicitHeight + 36)

    // --- AUDIO ---
    // The system default output/input nodes. Their audio binding is only valid
    // once the node is ready and is an audio node, so guard every access.
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool sinkReady: sink !== null && sink.ready && sink.audio !== null
    readonly property bool sourceReady: source !== null && source.ready && source.audio !== null
    readonly property int sinkPercent: sinkReady && !sink.audio.muted
        ? Math.round(sink.audio.volume * 100) : 0
    readonly property int sourcePercent: sourceReady && !source.audio.muted
        ? Math.round(source.audio.volume * 100) : 0

    // Set an absolute 0.0–1.0 volume, unmuting first so dragging the slider
    // while muted brings the sound back.
    function setSinkVolume(v: real): void {
        if (!root.sinkReady)
            return
        root.sink.audio.muted = false
        root.sink.audio.volume = Math.max(0, Math.min(1, v))
    }

    function setSourceVolume(v: real): void {
        if (!root.sourceReady)
            return
        root.source.audio.muted = false
        root.source.audio.volume = Math.max(0, Math.min(1, v))
    }

    // Every later task appends its section to this column.
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 18
        spacing: 20

        // --- HEADER: dark/light, color picker, screenshot, GTK/QT themes ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Settings"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            ActionIcon {
                iconSrc: Paths.icon("darklight")
                onClicked: SettingsState.toggleDarkLight()
            }

            ActionIcon {
                iconSrc: Paths.icon("picker")
                onClicked: {
                    root.closeRequested()
                    Quickshell.execDetached(["hyprpicker", "-a", "-f", "hex"])
                }
            }

            ActionIcon {
                iconSrc: Paths.icon("screenshot")
                onClicked: {
                    root.closeRequested()
                    Quickshell.execDetached(["bash", "-c", Paths.hyprScreenshot])
                }
            }

            ActionIcon {
                id: themeButton
                iconSrc: Paths.icon("theme")
                onClicked: themeMenu.open()

                PanelMenu {
                    id: themeMenu
                    y: parent.height
                    implicitWidth: 220


                    MenuEntry {
                        text: "Set GTK Theme"
                        onClicked: {
                            root.closeRequested()
                            Quickshell.execDetached(["nwg-look"])
                        }
                    }
                    MenuEntry {
                        text: "Set QT Theme"
                        onClicked: {
                            root.closeRequested()
                            Quickshell.execDetached(["qt6ct"])
                        }
                    }
                    MenuEntry {
                        text: "Refresh GTK Theme"
                        onClicked: {
                            root.closeRequested()
                            Quickshell.execDetached(["bash", "-c",
                                Paths.hyprGtk])
                        }
                    }
                }
            }
        }

        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: Theme.primary
                    opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                }
            }

            ColumnLayout {
                width: scrollView.availableWidth
                spacing: 20

                // --- NIGHT LIGHT ---
                NightLightSection {
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.primary
                    opacity: 0.3
                }

                // --- SLIDERS ---
                // Output and input volume come straight from the Pipewire service,
                // so external changes (wpctl, media keys) show up live without
                // polling. PwObjectTracker keeps each node's audio properties bound
                // and writable while this panel exists.
                PwObjectTracker {
                    objects: {
                        let list = []
                        if (root.sink)
                            list.push(root.sink)
                        if (root.source)
                            list.push(root.source)
                        return list
                    }
                }

                SliderRow {
                    Layout.fillWidth: true
                    iconSrc: root.sinkPercent <= 0
                        ? Paths.icon("volume-muted")
                        : Paths.icon("volume")
                    value: root.sinkPercent
                    available: root.sinkReady
                    onMoved: v => root.setSinkVolume(v / 100)
                    onIconClicked: {
                        if (root.sinkReady)
                            root.sink.audio.muted = !root.sink.audio.muted
                    }
                }

                SliderRow {
                    Layout.fillWidth: true
                    iconSrc: root.sourcePercent <= 0
                        ? Paths.icon("microphone-muted")
                        : Paths.icon("microphone")
                    value: root.sourcePercent
                    available: root.sourceReady
                    onMoved: v => root.setSourceVolume(v / 100)
                    onIconClicked: {
                        if (root.sourceReady)
                            root.source.audio.muted = !root.source.audio.muted
                    }
                }

                SliderRow {
                    Layout.fillWidth: true
                    iconSrc: Paths.icon("brightness")
                    value: SettingsState.brightness
                    minimum: SettingsState.minBrightness
                    available: SettingsState.hasBacklight
                    onMoved: v => SettingsState.setBrightness(v)
                    onIconClicked: SettingsState.toggleBrightness()
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.primary
                    opacity: 0.3
                }

                AccentPicker {
                    Layout.fillWidth: true
                }

                // --- MEDIA ---
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.primary
                    opacity: 0.3
                    visible: mediaPlayers.visible
                }

                MediaPlayers {
                    id: mediaPlayers
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.primary
                    opacity: 0.3
                }

                // --- DESKTOP ---
                // Switches bind straight to the owning singletons, which
                // persist into shroomery/settings/*.json. After a click the
                // binding is re-asserted so external changes (keybinds,
                // IPC) keep showing up live.
                SettingRow {
                    label: "Status Bar"
                    ToggleSwitch {
                        checked: StatusbarState.settings.bar.enabled
                        onToggled: {
                            StatusbarState.setEnabled(checked)
                            checked = Qt.binding(() => StatusbarState.settings.bar.enabled)
                        }
                    }
                    ActionIcon {
                        iconSrc: Paths.icon("settings")
                        onClicked: statusbarMenu.open()
                        PanelMenu {
                            id: statusbarMenu
                            y: parent.height
                            MenuEntry {
                                text: "Reload Status Bar"
                                onClicked: StatusbarState.reloadSettings()
                            }
                            MenuEntry {
                                text: "Edit Settings"
                                onClicked: {
                                    root.closeRequested()
                                    Quickshell.execDetached([Paths.editor, Paths.statusbarSettings])
                                }
                            }
                        }
                    }
                }

                SettingRow {
                    label: "Statusbar Expanded"
                    ToggleSwitch {
                        checked: StatusbarState.settings.bar.alwaysExpanded
                        onToggled: {
                            StatusbarState.setAlwaysExpanded(checked)
                            checked = Qt.binding(() => StatusbarState.settings.bar.alwaysExpanded)
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                SettingRow {
                    label: "Taskbar"
                    ToggleSwitch {
                        checked: StatusbarState.settings.taskbar.enabled
                        onToggled: {
                            StatusbarState.setTaskbarEnabled(checked)
                            checked = Qt.binding(() => StatusbarState.settings.taskbar.enabled)
                        }
                    }
                    ActionIcon {
                        iconSrc: Paths.icon("settings")
                        onClicked: taskbarMenu.open()
                        PanelMenu {
                            id: taskbarMenu
                            y: parent.height
                            MenuEntry {
                                text: "Reload Taskbar"
                                onClicked: StatusbarState.reloadSettings()
                            }
                            // The pins live in statusbar.json under
                            // taskbar.pinned; reload after saving.
                            MenuEntry {
                                text: "Edit Pinned Apps"
                                onClicked: {
                                    root.closeRequested()
                                    Quickshell.execDetached([Paths.editor, Paths.statusbarSettings])
                                }
                            }
                        }
                    }
                }

                // Launcher apps/emoji tabs: grid or list (LauncherState →
                // shroomery/settings/launcher-view.json).
                SettingRow {
                    label: "Grid Apps"
                    ToggleSwitch {
                        checked: LauncherState.appsGrid
                        onToggled: {
                            LauncherState.setAppsGrid(checked)
                            checked = Qt.binding(() => LauncherState.appsGrid)
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                SettingRow {
                    label: "Grid Emojis"
                    ToggleSwitch {
                        checked: LauncherState.emojiGrid
                        onToggled: {
                            LauncherState.setEmojiGrid(checked)
                            checked = Qt.binding(() => LauncherState.emojiGrid)
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                // hypr/scripts/gamemode.sh flips Hyprland and the flag file.
                SettingRow {
                    label: "Gamemode"
                    ToggleSwitch {
                        id: gamemodeSwitch
                        property bool ready: false
                        Process {
                            command: ["test", "-f", Paths.gamemodeEnabled]
                            running: root.active
                            onExited: exitCode => {
                                gamemodeSwitch.checked = exitCode === 0
                                gamemodeSwitch.ready = true
                            }
                        }
                        onToggled: {
                            if (ready)
                                Quickshell.execDetached(["bash", Paths.hyprGamemode])
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                // On unless the hide-fastfetch flag file exists.
                SettingRow {
                    label: "Fastfetch"
                    ToggleSwitch {
                        id: fastfetchSwitch
                        property bool ready: false
                        Process {
                            command: ["test", "-f", Paths.hideFastfetch]
                            running: root.active
                            onExited: exitCode => {
                                fastfetchSwitch.checked = exitCode !== 0
                                fastfetchSwitch.ready = true
                            }
                        }
                        onToggled: {
                            if (!ready)
                                return
                            Quickshell.execDetached(checked
                                ? ["rm", "-f", Paths.hideFastfetch]
                                : ["touch", Paths.hideFastfetch])
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                SettingRow {
                    label: "Visualizer mode"
                    ToggleSwitch {
                        checked: VisualizerState.active
                        onToggled: {
                            if (checked)
                                VisualizerState.openSetup()
                            else
                                VisualizerState.disable()
                            checked = Qt.binding(() => VisualizerState.active)
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                SettingRow {
                    label: "Wallpaper"
                    ActionIcon {
                        iconSrc: Paths.icon("wallpaper")
                        onClicked: {
                            root.closeRequested()
                            Quickshell.execDetached(["qs", "ipc", "call", "wallpaper", "open"])
                        }
                    }
                }
            }
        }
    }
}
