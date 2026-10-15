import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The window frame shared by every slide-in panel: an overlay layer that
// slides in from the left, right or top edge of the focused monitor, closes on
// outside click and Escape, and exposes toggle/open/close/isOpen over IPC
// (`qs ipc call <ipcTarget> toggle`, which is what each app's toggle.sh runs).
//
//   SlidePanel {
//       ipcTarget: "audio"
//       onIsOpenChanged: ...
//       PanelSurface { ... }
//   }
PanelWindow {
    id: panel

    // IPC target name; also what the app's toggle.sh passes to shared/toggle.sh.
    required property string ipcTarget
    // "left", "right" or "top".
    property string edge: "left"
    // left/right panels: stretch from topMargin to bottomMargin. When false the
    // panel takes its implicitHeight and is centered vertically. Top panels are
    // always sized by implicitHeight and centered horizontally.
    property bool fullHeight: true
    property int panelWidth: 520
    // For a top panel this is its distance from the screen edge when open.
    property int topMargin: 52
    property int bottomMargin: 12

    property bool isOpen: false

    // Called on Escape before the panel closes. Return true when it handled the
    // key (e.g. closed an inner dialog) so the panel stays open.
    property var escapeHandler: function () { return false; }

    // Set false while something else owns the Hyprland focus grab (a popup
    // with its own grab), so the two grabs don't clear each other.
    property bool focusGrabEnabled: true

    // Whether to follow the focused monitor when opening. Off keeps the panel
    // on whichever screen it was first given.
    property bool followFocusedMonitor: true

    readonly property bool sliding: slideAnim.running

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: panelWidth

    // Locked to the focused output when the panel opens, so it doesn't jump
    // monitors if focus moves mid-animation.
    property var lockedScreen: null
    screen: lockedScreen || screenForActiveMonitor()

    function screenMatching(name) {
        const screens = Quickshell.screens;
        if (!screens || screens.length === 0)
            return null;
        if (name) {
            for (let s = 0; s < screens.length; s++) {
                if (screens[s].name === name)
                    return screens[s];
            }
        }
        return screens[0];
    }

    function screenForActiveMonitor() {
        const focused = Hyprland.focusedMonitor;
        return screenMatching(focused ? focused.name : "");
    }

    function pinToActiveMonitor() {
        if (followFocusedMonitor)
            lockedScreen = screenForActiveMonitor();
    }

    function toggle() {
        if (!isOpen)
            pinToActiveMonitor();
        isOpen = !isOpen;
    }

    function open() {
        pinToActiveMonitor();
        isOpen = true;
    }

    function close() {
        isOpen = false;
    }

    readonly property bool vertical: edge === "top"
    readonly property bool stretched: !vertical && fullHeight

    anchors {
        left: panel.edge === "left"
        right: panel.edge === "right"
        top: panel.vertical || panel.stretched
        bottom: panel.stretched
    }

    visible: isOpen || slideAnim.running

    property real currentMargin: vertical
        ? (isOpen ? topMargin : -(implicitHeight + 48))
        : (isOpen ? 0 : -(implicitWidth + 48))

    margins {
        left: panel.edge === "left" ? panel.currentMargin : 0
        right: panel.edge === "right" ? panel.currentMargin : 0
        top: panel.vertical ? panel.currentMargin : (panel.stretched ? panel.topMargin : 0)
        bottom: panel.stretched ? panel.bottomMargin : 0
    }

    Behavior on currentMargin {
        NumberAnimation {
            id: slideAnim
            duration: 350
            easing.type: Easing.OutQuint
        }
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.isOpen && panel.focusGrabEnabled
        onCleared: {
            if (panel.isOpen && panel.focusGrabEnabled)
                panel.isOpen = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (panel.escapeHandler())
                return;
            if (panel.isOpen)
                panel.isOpen = false;
        }
    }

    IpcHandler {
        target: panel.ipcTarget
        function toggle(): void { panel.toggle(); }
        function open(): void { panel.open(); }
        function close(): void { panel.close(); }
        function isOpen(): bool { return panel.isOpen; }
    }
}
