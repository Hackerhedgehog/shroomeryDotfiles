import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The power-profile switch popup: power-saver / balanced / performance.
// Read and written through `powerprofilesctl` (power-profiles-daemon). Anchored
// under whatever item opened it (the SettingsApp squircle). The status bar's
// battery panel uses Quickshell's PowerProfiles instead.
Item {
    id: menuRoot

    // The item the popup hangs under. Must be set by the parent.
    property var anchorItem: null
    // Whether the popup is shown. The parent both sets and reads this.
    property bool open: false
    // Emitted when the popup dismissed itself (outside click or Escape) so the
    // parent can clear its own "menu open" highlight.
    signal closed()

    // Current profile name as reported by `powerprofilesctl get`.
    property string currentName: "balanced"
    // Whether the daemon offers a performance profile (some machines don't).
    property bool hasPerformance: true
    // Staging value for the setter Process command binding.
    property string pendingProfile: "balanced"

    // The three selectable profiles, in ascending-power order. Performance is
    // dropped when the daemon does not expose it.
    readonly property var profiles: {
        let list = [
            { "value": "power-saver", "label": "Power Saver",  "icon": "icons/profile-power-saver.svg" },
            { "value": "balanced",    "label": "Balanced",     "icon": "icons/profile-balanced.svg" }
        ]
        if (menuRoot.hasPerformance)
            list.push({ "value": "performance", "label": "Performance", "icon": "icons/profile-performance.svg" })
        return list
    }

    // Icon for the currently active profile, for the caller to show in its
    // button. Resolved against this file's directory, so it works from any
    // consumer regardless of where that consumer lives.
    readonly property string currentIcon: {
        switch (menuRoot.currentName) {
        case "power-saver": return Qt.resolvedUrl("icons/profile-power-saver.svg")
        case "performance": return Qt.resolvedUrl("icons/profile-performance.svg")
        default:            return Qt.resolvedUrl("icons/profile-balanced.svg")
        }
    }

    function refresh(): void {
        getter.running = false
        getter.running = true
        lister.running = false
        lister.running = true
    }

    // Apply a profile and close the menu. Only emits closed() — never writes
    // menuRoot.open directly. open is a one-way binding supplied by the
    // consumer (e.g. `open: profileRoot.menuOpen`); an imperative assignment
    // here would sever that binding permanently (QML replaces a bound
    // property's binding with the last imperative write to it), leaving the
    // popup unable to reopen for the lifetime of this component. The parent's
    // onClosed handler is expected to push the state back down through the
    // still-intact binding.
    function setProfile(value: string): void {
        menuRoot.pendingProfile = value
        // Flip the icon immediately; refreshCurrent reconciles after the set.
        menuRoot.currentName = value
        setter.running = false
        setter.running = true
        menuRoot.closed()
    }

    Process {
        id: getter
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = this.text.trim()
                if (name === "power-saver" || name === "balanced" || name === "performance")
                    menuRoot.currentName = name
            }
        }
    }

    Process {
        id: lister
        command: ["powerprofilesctl", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                // `powerprofilesctl list` marks each available profile with a
                // trailing colon (`performance:`, `* performance:`, …).
                menuRoot.hasPerformance = /performance:/.test(this.text)
            }
        }
    }

    Process {
        id: setter
        command: ["powerprofilesctl", "set", menuRoot.pendingProfile]
        onExited: menuRoot.refresh()
    }

    onOpenChanged: {
        if (open)
            menuRoot.refresh()
    }

    // The Item itself takes no space; only the popup is visible.
    implicitWidth: 0
    implicitHeight: 0

    PopupWindow {
        id: popup
        anchor.item: menuRoot.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        // Center the popup under the anchor.
        anchor.rect.x: menuRoot.anchorItem
            ? menuRoot.anchorItem.width / 2 - popup.width / 2
            : 0

        visible: menuRoot.open && menuRoot.anchorItem !== null

        // Grab input while open so a click anywhere outside the popup dismisses
        // it — the same primitive the status bar itself uses. Only emits
        // closed() — see the comment on setProfile() above for why this must
        // not also assign menuRoot.open.
        HyprlandFocusGrab {
            windows: [popup]
            active: popup.visible
            onCleared: menuRoot.closed()
        }

        implicitWidth: 220
        implicitHeight: menuColumn.implicitHeight + 16
        color: "transparent"

        // Take keyboard focus while open so Escape closes the menu.
        // forceActiveFocus on show because the popup surface is only created
        // once visible.
        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            // Only emits closed() — see the comment on setProfile() above.
            Keys.onEscapePressed: menuRoot.closed()
        }

        onVisibleChanged: {
            if (visible)
                keyScope.forceActiveFocus()
        }

        // Card background, matching the settings panel's context menus: flat
        // background with a thin accent border.
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.background
            border.color: Theme.primary
            border.width: 1
        }

        ColumnLayout {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Repeater {
                model: menuRoot.profiles
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: modelData.value === menuRoot.currentName
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 4
                    color: rowMouse.containsMouse || selected ? Theme.primary : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutQuint }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: modelData.icon
                            width: 16
                            height: 16
                            sourceSize.width: 16
                            sourceSize.height: 16
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: (rowMouse.containsMouse || selected) ? Theme.background : Theme.primary
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            text: modelData.label
                            color: (rowMouse.containsMouse || selected) ? Theme.background : Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: selected
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menuRoot.setProfile(modelData.value)
                    }
                }
            }
        }
    }
}
