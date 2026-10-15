import QtQuick

// An app window in the middle of the focused monitor, on the same card the
// dashboard is drawn on. It drops in from the top edge like the launcher and
// has everything SlidePanel has (IPC, Escape, outside click). Children go on
// the card: give them anchors.fill: parent and anchors.margins: 20.
//
//   CenterPanel {
//       ipcTarget: "foo"
//       cardWidth: 720
//       cardHeight: 520
//       ColumnLayout { anchors.fill: parent; anchors.margins: 20 }
//   }
SlidePanel {
    id: panel

    property int cardWidth: 720
    property int cardHeight: 520
    // Room around the card for its shadow (PanelSurface's margins).
    readonly property int shadowMargin: 16
    // Never taller than the screen it opens on.
    readonly property int shownCardHeight: Math.min(cardHeight, (screen ? screen.height : 1080) - 96)

    default property alias content: card.data

    edge: "top"
    fullHeight: false
    panelWidth: cardWidth + 2 * shadowMargin
    implicitHeight: shownCardHeight + 2 * shadowMargin
    topMargin: screen ? Math.max(0, Math.round((screen.height - implicitHeight) / 2)) : 200

    PanelSurface {
        id: card
        radius: 24
    }
}
