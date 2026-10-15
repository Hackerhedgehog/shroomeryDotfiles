import Quickshell
import QtQuick
import qs.shared
import qs.shared.ui
// Time, with the date hanging below it when expanded. Hovering it opens the dashboard.
Item {
    id: clockRoot

    // Set by the parent: when true the date is revealed and the time shifts up.
    property bool expanded: false
    // Qt date/time format for the time, supplied from statusbar.json.
    property string timeFormat: "HH:mm"
    // Qt date/time format for the date shown below the time when expanded.
    property string dateFormat: "ddd, dd MMM"
    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    // Keyboard Return: open the dashboard (pinned) from the clock.
    function activate(): void {
        PopoutState.openFrom("dashboard", clockRoot, clockRoot.screenName)
    }

    readonly property string screenName: QsWindow.window && QsWindow.window.screen
        ? QsWindow.window.screen.name : ""
    onScreenNameChanged: if (screenName !== "") PopoutState.registerAnchor(screenName, "dashboard", clockRoot)
    Component.onDestruction: PopoutState.unregisterAnchor(screenName, "dashboard", clockRoot)

    implicitWidth: Math.max(timeText.implicitWidth, dateText.implicitWidth)
    implicitHeight: timeText.implicitHeight

    // Nudge the whole module up slightly in expanded mode so the time+date
    // block sits centered alongside the other icons.
    transform: Translate { y: clockRoot.expanded ? -2 : 0 }

    // Highlight ring shown when selected via the keyboard. Wraps tightly around
    // the visible content (the time, plus the date when expanded).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        anchors.top: timeText.top
        anchors.topMargin: -4
        anchors.bottom: clockRoot.expanded ? dateText.bottom : timeText.bottom
        anchors.bottomMargin: -4
        radius: 8
        color: "transparent"
        border.color: Theme.primary
        border.width: 1
        opacity: clockRoot.focused ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    // Live clock, only ticks once per minute.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Clicking the time (or the date hanging below it) grows the bar into
    // the dashboard; hovering moves a pinned panel here.
    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: dateText.bottom
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: PopoutState.click(clockRoot.screenName, "dashboard", clockRoot)
        onContainsMouseChanged: containsMouse
            ? PopoutState.hover(clockRoot.screenName, "dashboard", clockRoot, false)
            : PopoutState.unhover(clockRoot)
    }

    Text {
        id: timeText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // Shift up when expanded so the date below has more room.
        anchors.verticalCenterOffset: clockRoot.expanded ? -6 : 0
        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
        }
        text: Qt.formatDateTime(clock.date, clockRoot.timeFormat)
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 16
        font.bold: true
    }

    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeText.bottom
        anchors.topMargin: 1
        text: Qt.formatDateTime(clock.date, clockRoot.dateFormat)
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 11

        opacity: clockRoot.expanded ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
        }
    }
}
