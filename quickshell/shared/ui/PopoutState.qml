pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "PopoutLogic.js" as Logic

// Which status bar popout is open, on which monitor, from which bar button,
// and whether it is pinned. The rules live in PopoutLogic.js; this singleton
// feeds it events, runs its two timers and exposes the result. Each bar's
// StatusbarApp/PopoutHost draws the panel that is open on its monitor.
//
// Bar buttons with a popout name (BarButton.popout) call click() and
// hover()/unhover() and register as that panel's anchor on their monitor, which IPC opens and
// NotificationPopups use. Panels that keybinds open have a PanelIpc below.
Singleton {
    id: root

    property var machine: Logic.initial()
    readonly property string currentName: machine.name
    readonly property string currentScreen: machine.screen
    readonly property var anchorItem: machine.anchor
    readonly property bool pinned: machine.pinned

    // Every bar window: a pinned panel's focus grab lists them all, so the
    // pointer can still hover the other monitor's bar (and move the panel).
    property var barWindows: []

    function registerBar(win: var): void {
        if (root.barWindows.indexOf(win) < 0)
            root.barWindows = root.barWindows.concat([win]);
    }

    function unregisterBar(win: var): void {
        root.barWindows = root.barWindows.filter(w => w !== win);
    }

    // screen name -> { panel name -> bar button Item }
    property var anchorMap: ({})

    function dispatch(ev: var): void {
        const r = Logic.reduce(root.machine, ev);
        // Unchanged state comes back as the same object: don't re-notify.
        if (r.state !== root.machine)
            root.machine = r.state;
        for (const e of r.effects) {
            if (e === "startOpenTimer")
                openTimer.restart();
            else if (e === "stopOpenTimer")
                openTimer.stop();
            else if (e === "startCloseTimer")
                closeTimer.restart();
            else if (e === "stopCloseTimer")
                closeTimer.stop();
        }
    }

    function focusedScreenName(): string {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    // --- from the bars ---
    // `opens`: hovering alone opens the panel (taskbar window lists); other
    // buttons only move a pinned panel over to theirs.
    function hover(screenName: string, name: string, item: Item, opens: bool): void {
        dispatch({ type: "hover", screen: screenName, name: name, anchor: item, opens: opens });
    }

    function unhover(item: Item): void {
        dispatch({ type: "unhover", anchor: item });
    }

    // The pointer entered or left a bar's pill + panel.
    function pointer(screenName: string, inside: bool): void {
        dispatch({ type: "pointer", screen: screenName, inside: inside });
    }

    // A click on a bar button: opens its panel pinned, or closes it when open.
    function click(screenName: string, name: string, item: Item): void {
        dispatch({ type: "click", screen: screenName, name: name, anchor: item });
    }

    // A press inside the open panel pins it.
    function press(): void {
        dispatch({ type: "press" });
    }

    // A bar button is going away: close what it opened, drop its hover.
    function forget(item: Item): void {
        dispatch({ type: "forget", anchor: item });
    }

    // A bar is going away (monitor unplugged): close what it showed.
    function forgetScreen(screenName: string): void {
        dispatch({ type: "forgetScreen", screen: screenName });
    }

    // --- open / close ---
    function close(): void {
        dispatch({ type: "close" });
    }

    function closeIf(name: string): void {
        dispatch({ type: "close", name: name });
    }

    // Pinned, on the focused monitor, from that bar's button for `name`.
    function open(name: string): void {
        const s = focusedScreenName();
        dispatch({ type: "open", name: name, screen: s, anchor: anchorFor(s, name) });
    }

    function toggle(name: string): void {
        const s = focusedScreenName();
        dispatch({ type: "toggle", name: name, screen: s, anchor: anchorFor(s, name) });
    }

    // Pinned, from a given button (keyboard Return on a bar module).
    function openFrom(name: string, item: Item, screenName: string): void {
        dispatch({ type: "open", name: name, screen: screenName, anchor: item });
    }

    function isOpen(name: string): bool {
        return root.machine.name === name;
    }

    // --- anchors ---
    function registerAnchor(screenName: string, name: string, item: Item): void {
        if (!anchorMap[screenName])
            anchorMap[screenName] = {};
        anchorMap[screenName][name] = item;
    }

    function unregisterAnchor(screenName: string, name: string, item: Item): void {
        if (anchorMap[screenName] && anchorMap[screenName][name] === item)
            delete anchorMap[screenName][name];
        forget(item);
    }

    // The registered button for `name` on that monitor, or null when there is
    // none or it is hidden (collapsed module, collapsed pill).
    function anchorFor(screenName: string, name: string): var {
        const item = anchorMap[screenName] ? anchorMap[screenName][name] : null;
        if (!item || !item.visible || item.width <= 0 || item.opacity <= 0)
            return null;
        return item;
    }

    // Screen-local rect of that button, or null.
    function anchorRect(name: string, screenName: string): var {
        const item = anchorFor(screenName, name);
        if (!item)
            return null;
        try {
            return item.mapToItem(null, 0, 0, item.width, item.height);
        } catch (e) {
            return null;
        }
    }

    Timer {
        id: openTimer
        interval: 150
        onTriggered: root.dispatch({ type: "openTimer" })
    }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: root.dispatch({ type: "closeTimer" })
    }

    // toggle/open/close/isOpen over IPC for the panel named by `target`
    // (toggle.sh). No properties of its own: IpcHandler warns about every
    // extra signal, property change signals included.
    component PanelIpc: IpcHandler {
        function toggle(): void { root.toggle(target); }
        function open(): void { root.open(target); }
        function close(): void { root.closeIf(target); }
        function isOpen(): bool { return root.isOpen(target); }
    }

    PanelIpc { target: "notifications" }
    PanelIpc { target: "audio" }
    PanelIpc { target: "network" }
    PanelIpc { target: "bluetooth" }
    PanelIpc { target: "battery" }
    PanelIpc { target: "quick-settings" }
    PanelIpc { target: "dashboard" }
    PanelIpc { target: "power" }
}
