import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.StatusbarApp
import qs.LauncherApp
import qs.VisualizerApp

// Settings window: the persistent options, grouped in tabs. The status bar's
// QuickSettingsPanel holds the quick actions and opens this with "All
// settings". Switches bind straight to the owning singletons, which persist
// into shroomery/settings/*; after a click the binding is re-asserted so
// external changes (keybinds, IPC) keep showing up live.
CenterPanel {
    id: root
    ipcTarget: "settings"
    cardWidth: 760
    cardHeight: 620

    readonly property var tabs: ["Appearance", "Bar & Dock", "Launcher", "Night light", "System"]
    property int tab: 0

    onIsOpenChanged: if (isOpen) tab = 0

    // Night light polls hyprsunset only while this window is open.
    Binding {
        target: NightLightState
        property: "panelOpen"
        value: root.isOpen
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        AppHeader {
            glyph: String.fromCodePoint(0xF0493)
            title: "Settings"
            subtitle: "Appearance, bar, launcher, night light and system"
        }

        TabPills {
            model: root.tabs
            currentIndex: root.tab
            onActivated: index => root.tab = index
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 14

                // --- APPEARANCE ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tab === 0
                    spacing: 14

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: accent.implicitHeight + 24
                        AccentPicker {
                            id: accent
                            anchors.fill: parent
                            anchors.margins: 12
                        }
                    }
                    SettingRow {
                        label: "GTK / Qt themes"
                        hint: "Open the theme tools"
                        PanelButton {
                            compact: true
                            text: "GTK"
                            onClicked: { root.close(); Quickshell.execDetached(["nwg-look"]) }
                        }
                        PanelButton {
                            compact: true
                            text: "Qt"
                            onClicked: { root.close(); Quickshell.execDetached(["qt6ct"]) }
                        }
                        PanelButton {
                            compact: true
                            text: "Refresh GTK"
                            onClicked: Quickshell.execDetached(["bash", "-c", Paths.hyprGtk])
                        }
                    }
                    SettingRow {
                        label: "Wallpaper"
                        PanelButton {
                            compact: true
                            text: "Choose"
                            onClicked: {
                                root.close()
                                Quickshell.execDetached(["qs", "ipc", "call", "wallpaper", "open"])
                            }
                        }
                    }
                }

                // --- BAR & DOCK ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tab === 1
                    spacing: 14

                    SettingRow {
                        label: "Status bar"
                        ToggleSwitch {
                            checked: StatusbarState.settings.bar.enabled
                            onToggled: {
                                StatusbarState.setEnabled(checked)
                                checked = Qt.binding(() => StatusbarState.settings.bar.enabled)
                            }
                        }
                        PanelButton {
                            compact: true
                            text: "Reload"
                            onClicked: StatusbarState.reloadSettings()
                        }
                        PanelButton {
                            compact: true
                            text: "Edit"
                            onClicked: {
                                root.close()
                                Quickshell.execDetached([Paths.editor, Paths.statusbarSettings])
                            }
                        }
                    }
                    SettingRow {
                        label: "Status bar expanded"
                        ToggleSwitch {
                            checked: StatusbarState.settings.bar.alwaysExpanded
                            onToggled: {
                                StatusbarState.setAlwaysExpanded(checked)
                                checked = Qt.binding(() => StatusbarState.settings.bar.alwaysExpanded)
                            }
                        }
                    }
                    SettingRow {
                        label: "Taskbar"
                        hint: "Pinned apps are edited in statusbar.json"
                        ToggleSwitch {
                            checked: StatusbarState.settings.taskbar.enabled
                            onToggled: {
                                StatusbarState.setTaskbarEnabled(checked)
                                checked = Qt.binding(() => StatusbarState.settings.taskbar.enabled)
                            }
                        }
                        PanelButton {
                            compact: true
                            text: "Edit pinned apps"
                            onClicked: {
                                root.close()
                                Quickshell.execDetached([Paths.editor, Paths.statusbarSettings])
                            }
                        }
                    }
                }

                // --- LAUNCHER ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tab === 2
                    spacing: 14

                    SettingRow {
                        label: "Grid apps"
                        ToggleSwitch {
                            checked: LauncherState.appsGrid
                            onToggled: {
                                LauncherState.setAppsGrid(checked)
                                checked = Qt.binding(() => LauncherState.appsGrid)
                            }
                        }
                    }
                    SettingRow {
                        label: "Grid emojis"
                        ToggleSwitch {
                            checked: LauncherState.emojiGrid
                            onToggled: {
                                LauncherState.setEmojiGrid(checked)
                                checked = Qt.binding(() => LauncherState.emojiGrid)
                            }
                        }
                    }
                }

                // --- NIGHT LIGHT ---
                NightLightSection {
                    Layout.fillWidth: true
                    visible: root.tab === 3
                }

                // --- SYSTEM ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tab === 4
                    spacing: 14

                    // hypr/scripts/gamemode.sh flips Hyprland and the flag file.
                    SettingRow {
                        label: "Gamemode"
                        ToggleSwitch {
                            id: gamemodeSwitch
                            property bool ready: false
                            Process {
                                command: ["test", "-f", Paths.gamemodeEnabled]
                                running: root.isOpen
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
                    }
                    // On unless the hide-fastfetch flag file exists.
                    SettingRow {
                        label: "Fastfetch"
                        hint: "Show fastfetch in new terminals"
                        ToggleSwitch {
                            id: fastfetchSwitch
                            property bool ready: false
                            Process {
                                command: ["test", "-f", Paths.hideFastfetch]
                                running: root.isOpen
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
                    }
                    SettingRow {
                        label: "Visualizer mode"
                        ToggleSwitch {
                            checked: VisualizerState.active
                            onToggled: {
                                if (checked) {
                                    root.close()
                                    VisualizerState.openSetup()
                                } else {
                                    VisualizerState.disable()
                                }
                                checked = Qt.binding(() => VisualizerState.active)
                            }
                        }
                    }
                }
            }
        }
    }
}
