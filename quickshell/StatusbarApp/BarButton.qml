import QtQuick
import QtQuick.Effects
import Quickshell
import qs.shared.ui
import qs.shared
// Reusable round icon button used across the status bar modules.
Rectangle {
    id: btn
    property string iconSrc: ""
    property bool colorize: true
    // Set by the keyboard navigation in StatusbarWindow to highlight the
    // currently selected module.
    property bool focused: false
    signal clicked()
    // Right click; does nothing unless the module handles it.
    signal rightClicked()

    // Name of the PopoutState panel this button grows the bar into on click
    // (and on keyboard Return), or "" for a plain button. Clicking again
    // closes it; while another panel is pinned open, hovering moves it here.
    property string popout: ""
    readonly property string screenName: QsWindow.window && QsWindow.window.screen
        ? QsWindow.window.screen.name : ""

    // Run the button's action (mouse click or keyboard Return).
    function activate(): void {
        if (btn.popout !== "")
            PopoutState.openFrom(btn.popout, btn, btn.screenName)
        else
            btn.clicked()
    }

    onHoveredChanged: {
        if (btn.popout === "")
            return
        if (btn.hovered)
            PopoutState.hover(btn.screenName, btn.popout, btn, false)
        else
            PopoutState.unhover(btn)
    }
    // Lets IPC opens and the notification popups find this button.
    onScreenNameChanged: if (btn.popout !== "" && btn.screenName !== "")
        PopoutState.registerAnchor(btn.screenName, btn.popout, btn)
    Component.onDestruction: if (btn.popout !== "")
        PopoutState.unregisterAnchor(btn.screenName, btn.popout, btn)

    readonly property bool hovered: mouseArea.containsMouse
    // Highlighted when hovered with the mouse or selected via the keyboard.
    readonly property bool active: btn.hovered || btn.focused

    implicitWidth: 30
    implicitHeight: 30
    radius: 15

    // Every button gets the same accent-filled circle on hover/selection.
    // (colorize only controls whether the icon itself is recolored, so the
    // a multi-colored icon can keep its colors while still matching the others.)
    color: btn.active ? Theme.primary : "transparent"

    // Fade the accent circle in on hover/selection and out again on leave.
    Behavior on color {
        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
    }

    Image {
        anchors.centerIn: parent
        source: btn.iconSrc
        width: 18
        height: 18
        sourceSize.width: 18
        sourceSize.height: 18
        fillMode: Image.PreserveAspectFit
        layer.enabled: btn.colorize
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: btn.active ? Theme.background : Theme.primary

            // Recolor the icon in step with the circle fade.
            Behavior on colorizationColor {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                btn.rightClicked()
            else if (btn.popout !== "")
                PopoutState.click(btn.screenName, btn.popout, btn)
            else
                btn.clicked()
        }
    }
}
