import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
// Hyprland workspace switcher.
RowLayout {
    id: wsRoot
    spacing: 6

    // The monitor this bar belongs to, so the delegate can highlight the
    // workspace that is active *here* rather than the globally focused one.
    property string screenName: ""

    // The individual workspace buttons, exposed so StatusbarWindow can splice
    // them into its keyboard-navigation list. Rebuilt whenever workspaces are
    // added or removed.
    property var navButtons: []

    function rebuildNavButtons(): void {
        let a = []
        for (let i = 0; i < rep.count; i++)
            a.push(rep.itemAt(i))
        wsRoot.navButtons = a
    }

    // The workspace ids to render: every workspace that is in use. Hyprland
    // only tracks workspaces that hold windows or are focused, so its list is
    // already "in use"; each monitor's active workspace is unioned in as well
    // so a focused-but-empty workspace cannot flicker out between events.
    // Special workspaces (negative ids, e.g. scratchpads) are excluded.
    readonly property var workspaceIds: {
        let seen = ({})
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++)
            if (list[i].id > 0)
                seen[list[i].id] = true
        const mons = Hyprland.monitors.values
        for (let m = 0; m < mons.length; m++) {
            const aw = mons[m].activeWorkspace
            if (aw && aw.id > 0)
                seen[aw.id] = true
        }
        let ids = []
        for (let key in seen)
            ids.push(parseInt(key))
        ids.sort((a, b) => a - b)
        return ids
    }

    // The id of the workspace active on this bar's own monitor, or -1.
    readonly property int localActiveId: {
        const mons = Hyprland.monitors.values
        for (let m = 0; m < mons.length; m++) {
            if (mons[m].name === wsRoot.screenName) {
                const aw = mons[m].activeWorkspace
                return aw ? aw.id : -1
            }
        }
        return -1
    }

    Repeater {
        id: rep
        model: wsRoot.workspaceIds

        onItemAdded: wsRoot.rebuildNavButtons()
        onItemRemoved: wsRoot.rebuildNavButtons()

        delegate: WorkspaceBadge {
            id: ws
            required property var modelData   // the workspace id (int)
            // Set by StatusbarWindow's keyboard navigation.
            property bool focused: false

            // Active on the monitor this bar is on: the filled circle.
            readonly property bool isActiveHere: wsRoot.localActiveId === ws.modelData
            // Active on some other monitor: outlined, not filled. This must be
            // "active on any monitor that is not this bar's", not "is the
            // globally focused workspace" — with the latter, the other
            // monitor's active workspace was indistinguishable from an idle
            // one on the focused monitor's bar, which is exactly the
            // per-monitor distinction this module exists to show.
            readonly property bool isActiveElsewhere: {
                if (ws.isActiveHere)
                    return false
                const mons = Hyprland.monitors.values
                for (let m = 0; m < mons.length; m++) {
                    if (mons[m].name === wsRoot.screenName)
                        continue
                    const aw = mons[m].activeWorkspace
                    if (aw && aw.id === ws.modelData)
                        return true
                }
                return false
            }

            // Run this workspace's action (mouse click or keyboard Return).
            // Hyprland with Lua dispatchers ignores the plain "workspace N"
            // string, so branch on usingLua the same way the overview does.
            function activate(): void {
                if (Hyprland.usingLua)
                    Hyprland.dispatch("hl.dsp.focus({workspace = '" + ws.modelData + "'})")
                else
                    Hyprland.dispatch("workspace " + ws.modelData)
            }

            // Every rendered workspace is in use, so nothing is dimmed; only
            // the fill distinguishes the active one.
            label: `${ws.modelData}`
            filled: ws.isActiveHere
            outlineWidth: ws.isActiveElsewhere ? 2 : 1
            hovered: wsMouse.containsMouse

            // Keyboard-selection ring, distinct from the active-workspace fill.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: width / 2
                color: "transparent"
                border.color: Theme.primary
                border.width: 2
                opacity: ws.focused ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ws.activate()
            }
        }
    }
}
