import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.StatusbarApp

// One status bar per connected monitor. Variants re-evaluates when a monitor
// is plugged or unplugged, so bars appear and disappear with their screens.
//
// The settings files live in the StatusbarState singleton and the IPC target
// lives here rather than inside the bar, because both must exist exactly once
// no matter how many monitors are connected.
Scope {
    id: scope

    // The panels the bars grow into, by PopoutState name: { name: Component }.
    // Set in shell.qml, which can import every app.
    property var panels: ({})

    Variants {
        id: bars
        model: Quickshell.screens

        StatusbarWindow {
            panels: scope.panels
        }
    }

    // Variants exposes its created delegates as `instances`. At runtime this
    // is an array-like object (numeric keys "0".."n-1" plus a `.length`, but
    // Array.isArray is false and it is not a real JS array) rather than a
    // plain list or an object model with a `.values` array — confirmed with a
    // temporary Component.onCompleted probe that printed typeof "object",
    // Array.isArray false, keys ["0","1"] and length 2 for two monitors.
    // Array.from() handles both this array-like shape and a true array.
    readonly property var barList: {
        const inst = bars.instances
        return inst ? Array.from(inst) : []
    }

    // The bar on the monitor Hyprland currently has focused, falling back to
    // the first bar so a keybinding never becomes a no-op.
    function focusedBar(): var {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const list = scope.barList
        for (let i = 0; i < list.length; i++)
            if (list[i].screenName === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    // Clear the expanded/keyboard-grab state on every bar. Used by collapse()
    // so a bar can never be left holding the keyboard on another monitor.
    function collapseAll(): void {
        const list = scope.barList
        for (let i = 0; i < list.length; i++)
            list[i].barExpanded = false
    }

    IpcHandler {
        target: "statusbar"

        // --- global: affect every bar through the shared settings ---
        function toggle(): void { StatusbarState.setEnabled(!StatusbarState.settings.bar.enabled) }
        // Named enable/disable rather than show/hide: "show" is a reserved
        // subcommand of "qs ipc" and would never reach the function.
        function enable(): void { StatusbarState.setEnabled(true) }
        function disable(): void { StatusbarState.setEnabled(false) }
        function alwaysExpand(): void { StatusbarState.setAlwaysExpanded(true) }
        function autoCollapse(): void { StatusbarState.setAlwaysExpanded(false) }
        function refresh(): void { StatusbarState.reloadSettings() }
        function reload(): void { StatusbarState.reloadSettings() }

        // --- per-bar: only the monitor the user is looking at ---
        // Expand the focused monitor's bar and grab the keyboard for
        // navigation. Bound to SUPER + SPACE. Idempotent: when that bar is
        // already expanded it only re-grabs focus.
        function focus(): void {
            const bar = scope.focusedBar()
            if (bar)
                bar.grabKeyboard()
        }
        function expand(): void {
            const bar = scope.focusedBar()
            if (bar)
                bar.barExpanded = !bar.barExpanded
        }
        function collapse(): void { scope.collapseAll() }
    }
}
