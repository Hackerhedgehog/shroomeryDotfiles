import QtQuick

// Root of a panel the status bar grows into (StatusbarApp/PopoutHost). Lay
// the content out at implicitWidth × implicitHeight: the host clips it to the
// growing / morphing panel and never resizes it mid-animation. No card or
// border here — the bar's shape is the surface.
//
//   PopoutPanel {
//       implicitWidth: standardWidth
//       implicitHeight: Math.min(maxHeight, column.implicitHeight + 36)
//       ColumnLayout { id: column; anchors.fill: parent; anchors.margins: 18 }
//   }
//
// Register it by name in shell.qml (StatusbarBars.panels) and give it an IPC
// target in PopoutState (PanelIpc) if keybinds should open it.
Item {
    // Width shared by the bar-button panels (audio, notifications, settings,
    // network, bluetooth) so they all open at the same size.
    readonly property int standardWidth: 440

    // True while this is the open panel (set by the host): start and stop
    // polling, meters and "panel open" flags from it.
    property bool active: false
    // Tallest the panel may get on this monitor (set by the host).
    property real maxHeight: 600
    // The bar button it opened from, or null when opened through IPC.
    property Item anchorItem: null
    // True while the panel shows a popup with its own focus grab (e.g. the
    // power-profile menu): the bar's grab stands down meanwhile.
    property bool holdOpen: false
    // Called on Escape. Return true when it was used (closed a dialog inside
    // the panel), false to close the panel.
    property var escapeHandler: function () { return false; }

    // Close the panel (a "Close" button, a picked entry, nothing left to show).
    signal closeRequested()
}
