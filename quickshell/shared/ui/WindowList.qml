import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.shared
// The open windows of one app, one row per window title with its workspace
// number in front (a WorkspaceBadge, filled when it is the focused workspace) —
// e.g. the taskbar's hover list. Left click a row to focus that window (a
// minimized one is brought back first), right click to minimize it or bring it
// back without focusing it, middle click to close it. Styled like InlineMenu; a plain Item, so the caller decides which
// window or popup hosts it.
//
// "Minimized" means parked on the special:minimized workspace, the same place
// the SUPER + X keybind (~/.config/hypr/keybindings.lua) sends a window.
Item {
    id: list

    // The app's Toplevels (AppButton.windows).
    property var windows: []
    // Fixed width for the same reason as InlineMenu: sizing to the longest
    // title would loop the layout. Long titles elide.
    property int listWidth: 320
    // Draw the menu-style border and background. Off inside a card that
    // already has its own (a status bar popout panel).
    property bool framed: true
    // Whether the pointer is over the list (rows included), so the host can
    // keep it open while the pointer moves from the icon onto it.
    readonly property bool hovered: listHover.hovered

    readonly property string minimizedWorkspace: "special:minimized"

    signal closeRequested()

    implicitWidth: list.listWidth
    implicitHeight: listColumn.implicitHeight + 16
    width: implicitWidth
    height: implicitHeight

    // Make sure every window's workspace is current before it is shown.
    onWindowsChanged: if (list.windows.length > 0) Hyprland.refreshToplevels()

    // The Hyprland side of a Wayland toplevel (workspace, address), or null.
    function hyprlandWindow(toplevel: var): var {
        const all = Hyprland.toplevels.values
        for (let i = 0; i < all.length; i++)
            if (all[i].wayland === toplevel)
                return all[i]
        return null
    }

    function selector(hyprWindow: var): string {
        const address = `${hyprWindow.address}`
        return "address:" + (address.startsWith("0x") ? address : "0x" + address)
    }

    // Move a window to a workspace. With follow the window also gets focus
    // (and the view goes along) — one dispatch, so the focus cannot race ahead
    // of the move.
    function moveTo(hyprWindow: var, workspace: string, follow: bool): void {
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = '${workspace}', window = '${list.selector(hyprWindow)}', follow = ${follow} })`)
        else
            Hyprland.dispatch(`${follow ? "movetoworkspace" : "movetoworkspacesilent"} ${workspace},${list.selector(hyprWindow)}`)
    }

    function minimize(hyprWindow: var): void {
        list.moveTo(hyprWindow, list.minimizedWorkspace, false)
    }

    // Bring a minimized window back onto the focused workspace, optionally
    // focusing it.
    function restore(hyprWindow: var, focus: bool): void {
        const target = Hyprland.focusedWorkspace
        if (target)
            list.moveTo(hyprWindow, `${target.id}`, focus)
    }

    HoverHandler {
        id: listHover
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: list.framed ? Theme.background : "transparent"
        border.width: list.framed ? 1 : 0
        border.color: Theme.primary

        Column {
            id: listColumn
            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 2

            Repeater {
                model: list.windows

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    readonly property var hyprWindow: list.hyprlandWindow(row.modelData)
                    readonly property var workspace: row.hyprWindow ? row.hyprWindow.workspace : null
                    readonly property bool minimized: row.workspace !== null
                        && row.workspace.name === list.minimizedWorkspace
                    readonly property bool active:
                        ToplevelManager.activeToplevel === row.modelData

                    // Text color flips on hover, like InlineMenu.
                    readonly property color fg: rowMouse.containsMouse ? Theme.background : Theme.primary

                    width: listColumn.width
                    height: 36
                    radius: 4
                    color: rowMouse.containsMouse ? Theme.primary : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutQuint }
                    }

                    // Workspace number: a dash for a minimized window, the
                    // first letter for another special workspace (e.g. the
                    // scratchpad).
                    WorkspaceBadge {
                        id: badge
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 5
                        label: {
                            const ws = row.workspace
                            if (!ws)
                                return "?"
                            if (row.minimized)
                                return "–"
                            if (ws.name.startsWith("special:"))
                                return ws.name.charAt(8).toUpperCase()
                            return `${ws.id}`
                        }
                        filled: row.workspace !== null
                            && row.workspace === Hyprland.focusedWorkspace
                        inverted: rowMouse.containsMouse
                        opacity: row.minimized ? 0.6 : 1
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: badge.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: row.modelData.title || row.modelData.appId
                        color: row.fg
                        opacity: row.minimized ? 0.6 : 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: row.active
                        font.italic: row.minimized
                        elide: Text.ElideRight

                        Behavior on color {
                            ColorAnimation { duration: 200; easing.type: Easing.OutQuint }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                        onClicked: (mouse) => {
                            // Grab everything before acting: closing the window
                            // removes it from the model and tears this delegate
                            // down.
                            const window = row.modelData
                            const hyprWindow = row.hyprWindow
                            const minimized = row.minimized
                            if (mouse.button === Qt.LeftButton) {
                                list.closeRequested()
                                // A minimized window comes back to this
                                // workspace rather than pulling the special
                                // workspace up.
                                if (minimized && hyprWindow)
                                    list.restore(hyprWindow, true)
                                else
                                    window.activate()
                            } else if (mouse.button === Qt.RightButton) {
                                if (!hyprWindow)
                                    return
                                if (minimized)
                                    list.restore(hyprWindow, false)
                                else
                                    list.minimize(hyprWindow)
                            } else {
                                window.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
