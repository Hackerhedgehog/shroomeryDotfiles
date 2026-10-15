import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui

// Taskbar: the pinned apps (taskbar.pinned in statusbar.json) plus the running
// ones, as a row of app buttons. Independent of the DockApp, which keeps its own
// pins; both build their list with AppList. The right-click menu opens in a
// popup below the bar. Hovering a running app shows its windows in the panel
// the bar grows into (TaskbarWindowsPanel): click one to focus it, right click
// to minimize or restore it, middle click to close it.
RowLayout {
    id: taskbar
    spacing: 2

    property int iconSize: StatusbarState.settings.taskbar.iconSize

    readonly property var pinnedApps: StatusbarState.settings.taskbar.pinned
    readonly property var entries: AppList.entries(taskbar.pinnedApps)

    function pinApp(key: string): void {
        const list = AppList.withPinned(taskbar.pinnedApps, key)
        if (list)
            StatusbarState.setTaskbarPinned(list)
    }

    function unpinApp(key: string): void {
        if (key)
            StatusbarState.setTaskbarPinned(AppList.withoutPinned(taskbar.pinnedApps, key))
    }

    // The app buttons, exposed so StatusbarWindow can splice them into its
    // keyboard-navigation list. Rebuilt whenever apps come and go.
    property var navButtons: []

    function rebuildNavButtons(): void {
        let a = []
        for (let i = 0; i < rep.count; i++)
            a.push(rep.itemAt(i))
        taskbar.navButtons = a
    }

    // Collapse the slot when there is nothing to show (no pins, no windows).
    readonly property bool collapsed: rep.count === 0

    // --- CONTEXT MENU (AppButton's menuHost interface) ---
    property var menuItem: null
    readonly property bool menuOpen: menuItem !== null

    function openMenuFor(item, actions): void {
        PopoutState.closeIf("windows")
        menu.actions = actions
        taskbar.menuItem = item
    }

    function closeMenu(): void {
        taskbar.menuItem = null
    }

    // Moving the menu to another icon while it is open. Deferred: run straight
    // from this handler, it could beat the anchor.item binding to the new icon
    // and re-anchor to the old one — a same-sized popup then stayed put.
    onMenuItemChanged: Qt.callLater(() => { if (popup.visible) popup.anchor.updateAnchor() })

    // --- WINDOW LIST ---
    // Hovering a running app's button grows the bar into its window list
    // (TaskbarWindowsPanel, PopoutState name "windows").
    readonly property string barScreenName: QsWindow.window && QsWindow.window.screen
        ? QsWindow.window.screen.name : ""

    // The app button whose windows are listed, if it is one of this bar's
    // (AppButton.windowListOpen reads it).
    readonly property Item listItem: PopoutState.currentName === "windows"
        && taskbar.navButtons.indexOf(PopoutState.anchorItem) >= 0 ? PopoutState.anchorItem : null

    function setListHovered(item: Item, hovered: bool): void {
        if (hovered)
            PopoutState.hover(taskbar.barScreenName, "windows", item, true)
        else
            PopoutState.unhover(item)
    }

    Repeater {
        id: rep
        model: taskbar.entries

        delegate: AppButton {
            id: appButton
            required property var modelData

            entry: modelData
            iconSize: taskbar.iconSize
            menuHost: taskbar
            tooltipBelow: true
            pinTarget: "Taskbar"
            showTooltip: !running
            bubbleIndicator: true
            Layout.alignment: Qt.AlignVCenter

            onPinRequested: key => taskbar.pinApp(key)
            onUnpinRequested: key => taskbar.unpinApp(key)

            // Only running apps have a window list; none while the context
            // menu is up.
            readonly property bool listHovered: hovered && running && !taskbar.menuOpen
            onListHoveredChanged: taskbar.setListHovered(appButton, listHovered)
            Component.onDestruction: PopoutState.forget(appButton)
        }

        onItemAdded: Qt.callLater(taskbar.rebuildNavButtons)
        onItemRemoved: Qt.callLater(taskbar.rebuildNavButtons)
    }

    PopupWindow {
        id: popup
        anchor.item: taskbar.menuItem
        // A complete 1x1 anchor rect 10px below the item's center, with the
        // popup growing down and centered on it. Setting only anchor.rect.x
        // left the rect partial, which put the popup over the icon.
        anchor.rect: Qt.rect(taskbar.menuItem ? taskbar.menuItem.width / 2 : 0,
                             taskbar.menuItem ? taskbar.menuItem.height + 10 : 0, 1, 1)
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom

        visible: taskbar.menuItem !== null
        color: "transparent"
        implicitWidth: menu.implicitWidth
        implicitHeight: menu.implicitHeight

        // Dismiss on a click outside the menu, and give the menu the keyboard
        // (for Escape). Only the popup may be in the grab: with the bar window
        // listed too, a click on a menu entry cleared the grab (closing the
        // menu) before the entry received it.
        //
        // Started from onVisibleChanged one tick after the popup is shown, not
        // bound to popup.visible: the binding fired before the popup's surface
        // existed, the grab never started, and nothing retried it.
        HyprlandFocusGrab {
            id: grab
            windows: [popup]
            onCleared: taskbar.closeMenu()
        }

        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: taskbar.closeMenu()
        }

        onVisibleChanged: {
            if (visible) {
                keyScope.forceActiveFocus()
                Qt.callLater(() => grab.active = popup.visible)
            } else {
                grab.active = false
            }
        }

        InlineMenu {
            id: menu
            visible: true
            onCloseRequested: taskbar.closeMenu()
        }
    }
}
