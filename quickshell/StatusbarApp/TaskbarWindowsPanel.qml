import QtQuick
import qs.shared.ui

// The taskbar's window list: the panel the bar grows into after hovering a
// running app's button. Shows that app's windows (WindowList); moving the
// pointer onto another running app morphs it over to that one.
PopoutPanel {
    id: root

    readonly property var windows: root.anchorItem && root.anchorItem.windows
        ? root.anchorItem.windows : []

    implicitWidth: 336
    implicitHeight: Math.min(maxHeight, windowList.implicitHeight)

    // Nothing to list: opened without a button, or the app's last window
    // closed. Checked a tick later, once the host has handed over the button.
    function closeIfEmpty(): void {
        if (root.active && root.windows.length === 0)
            root.closeRequested();
    }
    onWindowsChanged: Qt.callLater(root.closeIfEmpty)
    onActiveChanged: Qt.callLater(root.closeIfEmpty)

    WindowList {
        id: windowList
        framed: false
        listWidth: 336
        windows: root.windows
        onCloseRequested: root.closeRequested()
    }
}
