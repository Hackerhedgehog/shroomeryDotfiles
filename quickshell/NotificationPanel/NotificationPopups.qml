import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.NotificationPanel

// New-notification popups, stacked below the bell of the focused monitor's
// status bar (top-right corner when that bar has no bell). Each one hides
// after its timeout (paused while hovered) and stays in the panel's list.
PanelWindow {
    id: root

    readonly property int cardWidth: 380
    readonly property int pad: 16
    readonly property int topMargin: 67

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notification-popups"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Follow the focused monitor while nothing is shown, then stay put.
    property var lockedScreen: null
    screen: lockedScreen || focusedScreen()

    function focusedScreen() {
        const screens = Quickshell.screens;
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        for (let s = 0; s < screens.length; s++)
            if (screens[s].name === name)
                return screens[s];
        return screens.length > 0 ? screens[0] : null;
    }

    readonly property bool hasPopups: NotificationState.popups.length > 0
    onHasPopupsChanged: {
        if (hasPopups) {
            const scr = focusedScreen();
            lockedScreen = scr;
            const rect = PopoutState.anchorRect("notifications", scr ? scr.name : "");
            const sw = scr ? scr.width : 1920;
            const center = rect ? rect.x + rect.width / 2 : sw - implicitWidth / 2 - 8;
            windowX = Math.max(0, Math.min(sw - implicitWidth, Math.round(center - implicitWidth / 2)));
        } else {
            lingerTimer.restart();
        }
    }

    // Keeps the window mapped while the last popup animates out.
    Timer {
        id: lingerTimer
        interval: 400
        onTriggered: if (!root.hasPopups) root.lockedScreen = null
    }

    property real windowX: 0
    anchors {
        top: true
        left: true
    }
    margins.left: windowX
    implicitWidth: cardWidth + 2 * pad
    implicitHeight: Math.max(1, topMargin + list.contentHeight + pad)

    visible: hasPopups || lingerTimer.running

    // Only the cards take input.
    mask: Region { item: list.contentItem }

    ListView {
        id: list
        x: root.pad
        y: root.topMargin
        width: root.cardWidth
        height: contentHeight
        spacing: 8
        interactive: false
        model: ScriptModel { values: NotificationState.popups }

        delegate: Item {
            id: wrapper
            required property var modelData
            width: ListView.view.width
            height: card.implicitHeight

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                blur: 15
                color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
            }

            NotificationCard {
                id: card
                entry: wrapper.modelData
                width: parent.width
                maxBodyLines: 3
                onActivated: NotificationState.hidePopup(wrapper.modelData)
                onHoveredChanged: wrapper.modelData.hovered = hovered

                // Popups get the panel's shadow card look.
                color: Theme.background
                border.color: card.critical ? Theme.error : Theme.primary
            }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { property: "y"; from: -30; duration: 350; easing.type: Easing.OutQuint }
            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 350; easing.type: Easing.OutQuint }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 200 }
            NumberAnimation { property: "x"; to: 60; duration: 250; easing.type: Easing.InQuint }
        }
        // Also finish the fade/scale of an add that the shift interrupted,
        // or the card is left half transparent.
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 300; easing.type: Easing.OutQuint }
            NumberAnimation { properties: "opacity,scale"; to: 1; duration: 200 }
        }
    }
}
