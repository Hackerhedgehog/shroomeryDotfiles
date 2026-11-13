pragma Singleton

import Quickshell
import QtQuick

// The polkit password prompt (PolkitApp/PolkitWindow) registers its window
// here while it is open. Every SlidePanel adds it to its Hyprland focus grab,
// so clicking the prompt doesn't count as a click outside the app below it
// (which would close that app, e.g. the launcher or Settings mid-update).
Singleton {
    property var window: null
}
