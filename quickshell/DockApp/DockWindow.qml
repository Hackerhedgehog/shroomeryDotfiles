import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.DockApp

// Application dock: the running Hyprland applications plus a persistent list of 
// pinned ones, on a single (primary) screen at the bottom edge.
PanelWindow {
    id: root

    // --- WAYLAND CONFIGURATION ---
    WlrLayershell.layer: WlrLayer.Top
    // The dock claims its strip of the screen so windows tile above it instead
    // of running underneath. Only the pill itself is reserved (the window is
    // taller to leave room for the shadow), see exclusiveZone below.
    //
    // Autohiding and reserving space are mutually exclusive — a hidden dock that
    // still holds a gap open would be pointless — so an autohiding dock (or one
    // with dock.reserveSpace turned off) goes back to floating over the windows.
    exclusionMode: root.reservesSpace
        ? ExclusionMode.Normal
        : ExclusionMode.Ignore

    // Shown on the primary screen only: the Hyprland monitor with id 0, matched
    // to a Quickshell screen by name. Falls back to the first known screen.
    screen: {
        const screens = Quickshell.screens
        if (!screens || screens.length === 0)
            return null
        const monitors = Hyprland.monitors.values
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].id !== 0)
                continue
            for (let s = 0; s < screens.length; s++)
                if (screens[s].name === monitors[i].name)
                    return screens[s]
        }
        return screens[0]
    }

    // --- USER SETTINGS ---
    // Read and written by the DockSettings singleton, which owns the settings
    // files. It lives outside this window because dock.enabled decides whether
    // the window is created at all (see DockLoader).
    readonly property var settings: DockSettings.settings

    // --- APPS ---
    // The pinned apps (dock.json) plus the running ones, built by AppList.
    readonly property var pinnedApps: settings.apps.pinned
    readonly property var dockEntries: AppList.entries(root.pinnedApps)

    // Append an app to the pinned list (it keeps its position from then on).
    function pinApp(key: string): void {
        const list = AppList.withPinned(root.pinnedApps, key)
        if (list)
            DockSettings.persistPinned(list)
    }

    function unpinApp(key: string): void {
        if (key)
            DockSettings.persistPinned(AppList.withoutPinned(root.pinnedApps, key))
    }

    // --- VISIBILITY ---
    // This window exists only while the dock is enabled — DockLoader creates and
    // destroys it with the flag — so there is nothing to hide here.
    property bool autohide: settings.dock.autohide

    // Whether the dock holds a gap open at the bottom of the screen.
    readonly property bool reservesSpace: settings.dock.reserveSpace && !autohide
    // The pill plus its bottom margin — not the full window height, which also
    // covers the drop shadow and the slide-out distance.
    exclusiveZone: reservesSpace ? dockHeight + settings.dock.marginBottom : 0

    // --- CONTEXT MENU ---
    // One menu for the whole dock, drawn inside this window above the item it
    // was opened from. Only one can be open, so right-clicking another icon just
    // moves it.
    property var menuItem: null
    readonly property bool menuOpen: contextMenu.visible

    function openMenuFor(item, actions): void {
        root.menuItem = item
        contextMenu.actions = actions
        contextMenu.visible = true
    }

    function closeMenu(): void {
        contextMenu.visible = false
        root.menuItem = null
    }

    // Dismiss the menu when the pointer or keyboard goes to another window. The
    // grab is held on this window (a layer surface), so clicks on the dock and
    // on the menu itself still arrive normally.
    HyprlandFocusGrab {
        windows: [root]
        active: contextMenu.visible
        onCleared: root.closeMenu()
    }

    // Slid into view when autohide is off, while the pointer is on the dock (or
    // in the hot zone at the screen edge), and while a context menu is open.
    readonly property bool revealed: !autohide || dockHover.hovered
        || root.menuOpen

    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    // Height of the visible pill, and of the window around it. The window is
    // taller than the pill to leave room for the drop shadow and for the pill to
    // slide down out of view when autohiding.
    readonly property int dockHeight: settings.dock.iconSize
        + 2 * settings.pill.padding + 10
    // Room above the pill for the context menu, which is drawn inside this
    // window. It is reserved permanently rather than added when a menu opens:
    // resizing the layer surface on open/close makes the whole dock flicker.
    // The area stays transparent and click-through (see mask), and the reserved
    // space (exclusiveZone) is set explicitly, so the extra height costs
    // nothing. Sized for the tallest menu: three 32px rows, 2px apart, in a box
    // with 8px padding, plus the 8px gap above the pill.
    readonly property int menuReserve: 3 * 32 + 2 * 2 + 16 + 8
    implicitHeight: dockHeight + settings.dock.marginBottom + 30 + menuReserve

    // Only the pill takes pointer input; the transparent rest of the window
    // stays click-through so it never swallows clicks meant for the windows
    // behind it. While hidden, a 3px strip at the screen edge remains active as
    // the hot zone that reveals the dock again. While a menu is open the whole
    // window takes input, so the menu entries are clickable and a click on the
    // dock's empty area dismisses the menu.
    mask: Region {
        x: root.menuOpen ? 0 : (root.revealed ? Math.round(pill.x) : 0)
        y: root.menuOpen ? 0 : (root.revealed ? Math.round(pill.y) : root.height - 3)
        width: root.menuOpen ? root.width
            : (root.revealed ? Math.round(pill.width) : root.width)
        height: root.menuOpen ? root.height
            : (root.revealed ? Math.round(pill.height) : 3)
    }

    // A click anywhere in the dock window that is not on the menu or an icon
    // closes the menu (the focus grab only covers clicks in other windows).
    MouseArea {
        anchors.fill: parent
        enabled: root.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeMenu()
    }

    HoverHandler {
        id: dockHover
    }

    // ==========================================
    // DOCK PILL
    // ==========================================
    Item {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        width: dockRow.implicitWidth + 2 * root.settings.pill.padding
        height: root.dockHeight

        // Gap between the pill's bottom edge and the window's, animated for the
        // autohide slide. The pill's y is derived from it rather than animated
        // directly, so the window growing to fit a context menu repositions the
        // pill instantly instead of sliding it.
        property real revealOffset: root.revealed
            ? root.settings.dock.marginBottom
            : -(height - 3)

        Behavior on revealOffset {
            NumberAnimation {
                duration: root.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        y: parent.height - height - revealOffset

        Behavior on width {
            NumberAnimation {
                duration: root.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        RectangularShadow {
            anchors.fill: pillBg
            radius: pillBg.radius
            blur: 15
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
        }

        // Gradient BORDER layer (outer)
        Rectangle {
            id: pillBg
            anchors.fill: parent
            radius: root.settings.pill.radius
            opacity: root.settings.opacity.normal

            // Border colors come from the settings file; empty strings fall back
            // to the dynamic wallpaper theme.
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: root.settings.border.colorTop !== ""
                        ? root.settings.border.colorTop
                        : Theme.primary
                }
                GradientStop {
                    position: 1.0
                    color: root.settings.border.colorBottom !== ""
                        ? root.settings.border.colorBottom
                        : Theme.on_primary
                }
            }

            // Actual background fill (inner), inset by the border thickness
            Rectangle {
                anchors.fill: parent
                anchors.margins: root.settings.border.width
                radius: parent.radius - anchors.margins
                color: Theme.background
            }
        }

        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: root.settings.dock.spacing

            Repeater {
                model: root.dockEntries

                delegate: AppButton {
                    id: dockItem
                    required property var modelData

                    entry: modelData
                    iconSize: root.settings.dock.iconSize
                    menuHost: root
                    Layout.alignment: Qt.AlignVCenter

                    onPinRequested: key => root.pinApp(key)
                    onUnpinRequested: key => root.unpinApp(key)
                }
            }
        }
    }

    // ==========================================
    // CONTEXT MENU
    // ==========================================
    // Declared after the pill so it draws on top of it, and centered over the
    // item it belongs to, clamped to stay on screen.
    InlineMenu {
        id: contextMenu

        x: {
            if (!root.menuItem)
                return 0
            const center = pill.x + dockRow.x + root.menuItem.x
                + root.menuItem.width / 2
            return Math.max(8, Math.min(root.width - width - 8, center - width / 2))
        }
        y: pill.y - height - 8

        onCloseRequested: root.closeMenu()
    }
}
