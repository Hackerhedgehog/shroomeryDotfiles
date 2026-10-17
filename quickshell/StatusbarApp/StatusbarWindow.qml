import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.StatusbarApp
import qs.NotificationPanel
import qs.VisualizerApp

PanelWindow {
    id: root

    // Set by the Variants in StatusbarBars: the screen this bar belongs to.
    required property var modelData
    screen: modelData
    readonly property string screenName: modelData ? modelData.name : ""

    // { name: Component } of the popout panels (StatusbarBars.panels).
    required property var panels

    // --- WAYLAND CONFIGURATION ---
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard focus is owned by the HyprlandFocusGrab below (the same primitive
    // the popup menus use), not by the layer-shell focus mode. A
    // WlrKeyboardFocus.Exclusive grab held the keyboard until Escape and left
    // running apps dead; OnDemand never grabbed from the keybinding at all. The
    // focus grab gives the bar the keyboard while expanded *and* fires onCleared
    // when the pointer/keyboard goes to another window, which is what hands focus
    // back to the app (and collapses the bar). Leave the layer-shell mode at its
    // default (None) so the two mechanisms don't fight.

    // Grabs the keyboard for the bar while it is expanded so SUPER + SPACE can
    // drive Left/Right/Return navigation, and releases it the moment the user
    // interacts with another window (clicking/entering an app) — which returns
    // the keyboard to that app and collapses the bar.
    // Stands down while the taskbar's right-click menu holds its own grab:
    // hyprland-focus-grab-v1 clears an active grab whenever another grab is
    // started, so without this the menu would clear the bar's grab and
    // collapse the bar out from under itself.
    // It also holds the keyboard for a pinned popout panel, so its text fields
    // work and an outside click closes it.
    // See the matching comment in QuickSettingsPanel/QuickSettingsPanel.qml.
    // A popout panel on this bar that was pinned (press inside, IPC, Return).
    readonly property bool panelPinned: host.open && PopoutState.pinned

    Component.onDestruction: PopoutState.unregisterBar(root)

    HyprlandFocusGrab {
        // All bars, not just this one: with a panel pinned the pointer must
        // still reach the other monitor's bar to hover its buttons.
        windows: PopoutState.barWindows.length > 0 ? PopoutState.barWindows : [root]
        active: (root.barExpanded || root.panelPinned)
            && !root.taskbarMenuOpen && !host.holdOpen
        onCleared: {
            if (root.taskbarMenuOpen || host.holdOpen)
                return
            root.barExpanded = false
            if (root.panelPinned)
                PopoutState.close()
        }
    }

    // Escape closes the open panel unless the panel used it for a dialog of
    // its own (PopoutPanel.escapeHandler).
    Shortcut {
        sequence: "Escape"
        enabled: host.open
        onActivated: {
            const item = host.currentItem
            if (item && item.escapeHandler && item.escapeHandler())
                return
            PopoutState.close()
        }
    }

    property int barHeight: StatusbarState.settings.bar.height
    // Constant vertical space reserved for the bar (windows tile below this).
    property int reservedHeight: StatusbarState.settings.bar.reservedHeight

    // Whether the bar is shown. The "enabled" flag in statusbar.json is the
    // single source of truth; it is toggled from the SettingsApp switch and via
    // "qs ipc call statusbar toggle", persisted back to the file, and survives
    // restarts. Kept as a binding so a settings reload updates it for free.
    // Visualizer mode hides the bar without touching statusbar.json.
    property bool barEnabled: StatusbarState.settings.bar.enabled && !VisualizerState.active

    // Hide completely and reserve no space when disabled — except while a
    // popout panel is open on it (opened by a keybind), which needs the bar.
    visible: barEnabled || host.open
    // Reserve 20px less than the band so the gap below the pill is smaller
    // than above (windows tile 20px higher).
    exclusiveZone: barEnabled ? reservedHeight - 20 : 0

    // Keep the pill expanded regardless of hover. Set via IPC
    // ("qs ipc call statusbar focus") which is bound to SUPER + SPACE in
    // Hyprland, and cleared on Escape, after running a module, or when the
    // focus grab is released because the user interacted with another window.
    property bool barExpanded: false

    // When set in statusbar.json the pill never collapses: it stays in its
    // expanded (full-width) state independent of hover or the IPC toggle. This
    // is purely visual — unlike barExpanded it does not grab the keyboard — so
    // the left/right module areas remain permanently visible.
    property bool alwaysExpanded: StatusbarState.settings.bar.alwaysExpanded

    // --- MODULE PLACEMENT ---
    // Each module name in the settings file maps to the component placed into
    // the left/center/right groups. Unknown names load nothing.
    Component { id: cTerminal;   TerminalModule {} }
    Component {
        id: cWorkspaces
        WorkspacesModule {
            screenName: root.screenName
            // Rebuild keyboard navigation when workspaces appear/disappear.
            onNavButtonsChanged: Qt.callLater(root.rebuildNavItems)
        }
    }
    Component { id: cLauncher;   LauncherModule {} }
    Component {
        id: cClock
        ClockModule {
            expanded: pill.expanded
            timeFormat: StatusbarState.settings.clock.format
            dateFormat: StatusbarState.settings.clock.dateFormat
        }
    }
    Component { id: cSwaync;     SwayncModule {} }
    Component { id: cNotifications; NotificationsModule {} }
    // True while a system-tray context menu is open. Kept at window scope so
    // the pill can pin itself expanded while a menu is up (the tray lives in
    // the right area, which only exists while expanded).
    property bool trayMenuOpen: false
    Component {
        id: cSystemTray
        SystemTrayModule {
            // Rebuild keyboard navigation when the tray empties or repopulates
            // (it collapses out of the layout when it has no items).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            // Surface the open-menu state up to the window so the pill stays
            // expanded for as long as a tray menu is showing.
            Binding {
                target: root
                property: "trayMenuOpen"
                value: menuOpen
            }
        }
    }
    Component { id: cLogo;       LogoModule {} }
    Component { id: cSettings;   SettingsModule {} }
    Component { id: cNetwork;    NetworkModule {} }
    Component { id: cBluetooth;  BluetoothModule {} }
    Component { id: cPower;      PowerModule {} }
    Component { id: cVolume;     VolumeModule {} }
    Component {
        id: cUpdates
        UpdatesModule {
            // Rebuild the keyboard navigation list when the module hides or
            // reappears (its collapsed state tracks the available update count).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
        }
    }
    Component {
        id: cBattery
        BatteryModule {
            // Rebuild the keyboard navigation list when the module hides or
            // reappears (it only shows on machines with a battery).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
        }
    }

    // True while the taskbar's right-click menu is open. Its focus grab would
    // otherwise clear the bar's.
    property bool taskbarMenuOpen: false
    Component {
        id: cTaskbar
        TaskbarModule {
            // Rebuild keyboard navigation when apps open/close.
            onNavButtonsChanged: Qt.callLater(root.rebuildNavItems)
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            Binding {
                target: root
                property: "taskbarMenuOpen"
                value: menuOpen
            }
        }
    }

    readonly property var moduleComponents: ({
        "taskbar":    cTaskbar,
        "terminal":   cTerminal,
        "workspaces": cWorkspaces,
        "launcher":   cLauncher,
        "clock":      cClock,
        "swaync":     cSwaync,
        "notifications": cNotifications,
        "systemtray": cSystemTray,
        "logo":       cLogo,
        "settings":   cSettings,
        "network":    cNetwork,
        "bluetooth":  cBluetooth,
        "power":      cPower,
        "updates":      cUpdates,
        "volume":       cVolume,
        "battery":      cBattery
    })

    // The component for a module name, or null for an unknown name or a module
    // switched off in the settings (the taskbar, from the SettingsApp).
    function moduleComponent(name: string): var {
        if (name === "taskbar" && !StatusbarState.settings.taskbar.enabled)
            return null
        return root.moduleComponents[name] || null
    }

    // --- KEYBOARD NAVIGATION ---
    // Ordered left-to-right list of the navigable items, rebuilt from the
    // placed modules whenever the layout or the (dynamic) workspace/taskbar
    // buttons change. Modules with several buttons (workspaces, taskbar) splice
    // them in at their position; collection modules without a single action
    // (the system tray) are skipped.
    property var navItems: []
    // Index of the keyboard-selected item, or -1 when none is selected.
    property int focusIndex: -1

    function rebuildNavItems(): void {
        let items = []
        let groups = [leftRepeater, centerLeftRepeater, centerRepeater,
                      centerRightRepeater, rightRepeater]
        for (let g = 0; g < groups.length; g++) {
            let rep = groups[g]
            for (let i = 0; i < rep.count; i++) {
                let loader = rep.itemAt(i)
                let m = loader ? loader.item : null
                if (!m)
                    continue
                if (m.collapsed === true)                // hidden (e.g. updates)
                    continue
                if (m.navButtons !== undefined) {        // workspaces, taskbar
                    items = items.concat(m.navButtons)
                } else if (typeof m.activate === "function") {
                    items.push(m)
                }
            }
        }
        root.navItems = items
    }

    Component.onCompleted: {
        Qt.callLater(rebuildNavItems)
        PopoutState.registerBar(root)
    }
    Connections {
        target: StatusbarState
        function onSettingsChanged(): void { Qt.callLater(root.rebuildNavItems) }
    }

    // Highlight exactly the item at focusIndex and clear all others. Called
    // both when the selection moves and when navItems changes underneath it.
    function applyFocus(): void {
        let items = root.navItems
        for (let i = 0; i < items.length; i++)
            items[i].focused = (i === root.focusIndex)
    }

    onFocusIndexChanged: applyFocus()
    onNavItemsChanged: {
        // Keep the selection in range when the workspace count changes.
        if (root.focusIndex >= root.navItems.length)
            root.focusIndex = root.navItems.length - 1
        applyFocus()
    }

    onBarExpandedChanged: {
        if (barExpanded) {
            focusIndex = 0
            keyHandler.forceActiveFocus()
        } else {
            focusIndex = -1
        }
    }

    function moveFocus(dir: int): void {
        if (!barExpanded)
            return
        let n = root.navItems.length
        root.focusIndex = (root.focusIndex + dir + n) % n
    }

    // Forward an Up/Down press to the keyboard-selected module if it exposes a
    // step() function (e.g. the volume module), so the arrows adjust it in place
    // without leaving keyboard-navigation mode.
    function stepFocused(dir: int): void {
        if (root.focusIndex < 0 || root.focusIndex >= root.navItems.length)
            return
        let m = root.navItems[root.focusIndex]
        if (typeof m.step === "function")
            m.step(dir)
    }

    function activateFocused(): void {
        if (root.focusIndex >= 0 && root.focusIndex < root.navItems.length)
            root.navItems[root.focusIndex].activate()
        // Collapse so the keyboard is handed back to the (possibly newly
        // launched) application instead of staying captured by the bar.
        root.barExpanded = false
    }

    // Expand this bar and take keyboard focus for arrow-key navigation.
    // Called by StatusbarBars' IPC handler for the focused monitor only.
    function grabKeyboard(): void {
        root.barExpanded = true
        keyHandler.forceActiveFocus()
    }

    color: "transparent"

    // Full-width strip anchored to the top of the screen
    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 0
    }

    // Full screen height: the popout panels grow down from the pill inside
    // this window. Only the pill and the open panel take input (mask).
    implicitHeight: modelData ? modelData.height : 1080
    mask: Region {
        item: pill
        Region { item: host.inputItem }
    }

    // Pointer over the pill or the open panel; leaving both starts the
    // popout's close delay.
    readonly property bool pointerInside: hoverHandler.hovered || host.hovered
    onPointerInsideChanged: PopoutState.pointer(root.screenName, root.pointerInside)

    // Pill + popout panel as one shape (border, fill, shadow).
    BarShape {
        pill: pill
        host: host
        // With a panel open the whole shape is as opaque as the old panel
        // cards (0.96) so the panel stays readable.
        fillOpacity: host.open
            ? Math.max(0.96, StatusbarState.settings.opacity.expanded)
            : pill.expanded
                ? StatusbarState.settings.opacity.expanded
                : StatusbarState.settings.opacity.collapsed
        Behavior on fillOpacity {
            NumberAnimation {
                duration: StatusbarState.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }
    }

    // ==========================================
    // CENTERED PILL
    // ==========================================
    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        // Centered in the reserved band at the top of the screen.
        y: Math.round((root.reservedHeight - height) / 2)

        // Collapsed = sized to content, Expanded = fixed width.
        // Stays expanded while the notification panel is open: the bell lives
        // in the right area, and the panel closes back into it.
        property bool expanded: hoverHandler.hovered || root.barExpanded
            || root.alwaysExpanded || root.trayMenuOpen
            || NotificationState.panelOpen || host.open
        // The center group plus its two flanks, kept symmetric around the center
        // group so that stays in the middle of the bar: each half is half the
        // center plus the wider flank (and the gap to it).
        property real flankWidth: Math.max(centerLeftArea.implicitWidth,
                                           centerRightArea.implicitWidth)
        property real middleWidth: centerArea.implicitWidth
            + (flankWidth > 0 ? 2 * (flankWidth + 14) : 0)

        // 0 in the settings file means "hug the center content".
        property real collapsedWidth: StatusbarState.settings.pill.collapsedWidth > 0
            ? StatusbarState.settings.pill.collapsedWidth
            : middleWidth + 32

        // Minimum width the content needs so the centered center area never
        // overlaps the left/right areas. The center stays centered, so each
        // side must clear half of it: the bar has to be at least as wide as the
        // center plus twice the wider of the two side areas (whichever side
        // would collide first), plus the 16px edge margins and some breathing
        // room. Computed live so adding workspaces (or any module growing)
        // pushes the bar wider instead of clipping.
        property real contentWidth: middleWidth
            + 2 * Math.max(leftArea.implicitWidth, rightArea.implicitWidth)
            + 64
        // expandedWidth from the settings file is treated as a minimum: the
        // pill grows past it when the content needs more room.
        property real expandedWidth: Math.max(
            StatusbarState.settings.pill.expandedWidth, contentWidth)

        // A popout panel wider than the pill widens the pill while open.
        width: expanded ? Math.max(expandedWidth, host.open ? host.targetW : 0) : collapsedWidth
        height: expanded ? root.barHeight + 10 : root.barHeight

        Behavior on width {
            NumberAnimation {
                duration: StatusbarState.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: StatusbarState.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        HoverHandler {
            id: hoverHandler
        }

        // Captures arrow keys (navigate), Return (execute) and Escape
        // (collapse) while the bar is in expanded mode.
        FocusScope {
            id: keyHandler
            anchors.fill: parent
            focus: root.barExpanded
            Keys.onLeftPressed: root.moveFocus(-1)
            Keys.onRightPressed: root.moveFocus(1)
            Keys.onUpPressed: root.stepFocused(1)
            Keys.onDownPressed: root.stepFocused(-1)
            Keys.onReturnPressed: root.activateFocused()
            Keys.onEnterPressed: root.activateFocused()
            Keys.onEscapePressed: root.barExpanded = false
        }

        // ==========================================
        // LEFT AREA (only visible when expanded)
        // ==========================================
        RowLayout {
            id: leftArea
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            opacity: pill.expanded ? 1 : 0
            visible: opacity > 0
            enabled: pill.expanded

            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Repeater {
                id: leftRepeater
                model: StatusbarState.settings.modules.left
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponent(modelData)
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // CENTER AREA (always visible)
        // ==========================================
        RowLayout {
            id: centerArea
            anchors.centerIn: parent
            spacing: 14

            Repeater {
                id: centerRepeater
                model: StatusbarState.settings.modules.center
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponent(modelData)
                    // Collapse the slot of an empty module (e.g. a taskbar with
                    // no apps), see the right area.
                    visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // CENTER FLANKS (always visible)
        // ==========================================
        // Modules beside the center group, which stays centered on the bar:
        // centerLeft ends just left of it, centerRight starts just right of it.
        RowLayout {
            id: centerLeftArea
            anchors.right: centerArea.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                id: centerLeftRepeater
                model: StatusbarState.settings.modules.centerLeft || []
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponent(modelData)
                    visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        RowLayout {
            id: centerRightArea
            anchors.left: centerArea.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Repeater {
                id: centerRightRepeater
                model: StatusbarState.settings.modules.centerRight || []
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponent(modelData)
                    visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // RIGHT AREA (only visible when expanded)
        // ==========================================
        RowLayout {
            id: rightArea
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            // Same tight spacing as the workspace buttons on the left.
            spacing: 6

            opacity: pill.expanded ? 1 : 0
            visible: opacity > 0
            enabled: pill.expanded

            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Repeater {
                id: rightRepeater
                model: StatusbarState.settings.modules.right
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponent(modelData)
                    // Collapse the layout slot when the module marks itself
                    // collapsed (e.g. the updates module with no pending
                    // updates). Reading the plain `collapsed` flag — rather than
                    // the module's effective `visible` — avoids a binding latch
                    // that would pin this Loader hidden once the right area
                    // collapses in the pill's collapsed state.
                    visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }
    }

    // The popout panel growing out of the pill's bottom edge.
    PopoutHost {
        id: host
        y: pill.y + pill.height
        width: parent.width
        height: Math.max(0, parent.height - y)
        screenName: root.screenName
        panels: root.panels
        pill: pill
        borderWidth: StatusbarState.settings.border.width
        snap: StatusbarState.settings.pill.radius + 12
        maxHeight: parent.height - y - 28
    }
}
