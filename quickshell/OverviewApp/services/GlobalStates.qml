pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool overviewOpen: false
    // True while open and while it slides away after closing, so the windows
    // stay mapped and the previews keep their picture until it is off screen.
    property bool overviewShown: false
    readonly property int slideDuration: 350
    property bool superReleaseMightTrigger: true

    onOverviewOpenChanged: {
        if (overviewOpen) {
            hideTimer.stop();
            overviewShown = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: root.slideDuration
        onTriggered: root.overviewShown = false
    }
}
