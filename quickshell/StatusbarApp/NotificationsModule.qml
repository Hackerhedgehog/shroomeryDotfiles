import Quickshell
import QtQuick
import qs.shared
import qs.NotificationApp

// Bell: hovering it grows the bar into the notification panel. Also where
// the popups appear. Filled while there are notifications in the list,
// crossed out while do not disturb is on. Right click toggles do not disturb.
BarButton {
    id: bell
    popout: "notifications"

    iconSrc: Paths.icon((NotificationState.count > 0 ? "bell-filled" : "bell")
        + (NotificationState.dnd ? "-crossed" : ""))

    onRightClicked: NotificationState.setDnd(!NotificationState.dnd)
}
