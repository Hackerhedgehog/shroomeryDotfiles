import QtQuick

// One dashboard tab. Shown while it is the current tab: slides in from the
// side it comes from and fades; the panel sizes itself to its implicit size.
Item {
    id: page

    property int tabIndex: 0
    property int currentTab: 0
    // Dashboard open and this tab showing: run timers / polling from it.
    property bool active: false
    readonly property bool shown: tabIndex === currentTab

    // Ask the dashboard to switch tabs (e.g. the weather card → Weather).
    signal requestTab(int index)

    width: implicitWidth
    height: implicitHeight
    opacity: shown ? 1 : 0
    visible: opacity > 0
    enabled: shown

    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    transform: Translate {
        x: page.shown ? 0 : (page.tabIndex < page.currentTab ? -48 : 48)
        Behavior on x {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
}
