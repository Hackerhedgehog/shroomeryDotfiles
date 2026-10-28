import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs.shared

// System tray (StatusNotifierItem hosts): the icons apps like Steam put in
// the tray. Left click activates the app, middle click is its secondary
// action, right click (or left click on a menu-only item) opens its menu.
RowLayout {
    id: tray
    spacing: 2

    // Collapse the slot when there are no tray items, so the right Repeater
    // hides this Loader and the RowLayout doesn't reserve spacing around an
    // empty, zero-width module (which otherwise leaves a doubled gap next to
    // its neighbours).
    readonly property bool collapsed: SystemTray.items.values.length === 0

    // True while any tray context menu is open. The bar pins itself expanded
    // while this is set: placed in the left/right area, which is only
    // visible/enabled when the pill is expanded, the popup's anchor item would
    // otherwise vanish (pointer leaves the bar -> hover lost -> collapse) and
    // the menu would be dismissed the instant it opened.
    property int openMenuCount: 0
    readonly property bool menuOpen: openMenuCount > 0

    Repeater {
        model: SystemTray.items

        // Same accent circle on hover as BarButton; the icon keeps its colors.
        delegate: Rectangle {
            id: trayItem
            required property var modelData

            implicitWidth: 30
            implicitHeight: 30
            radius: 15
            Layout.alignment: Qt.AlignVCenter
            color: mouseArea.containsMouse ? Theme.primary : "transparent"

            Behavior on color {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }

            Image {
                anchors.centerIn: parent
                source: trayItem.modelData.icon
                width: 18
                height: 18
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                onClicked: (mouse) => {
                    const item = trayItem.modelData
                    if (mouse.button === Qt.MiddleButton)
                        item.secondaryActivate()
                    else if (mouse.button === Qt.LeftButton && !item.onlyMenu)
                        item.activate()
                    else if (item.hasMenu)
                        trayMenu.open()
                }
            }

            QsMenuAnchor {
                id: trayMenu
                menu: trayItem.modelData.menu
                anchor.item: trayItem
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom

                // Keep the bar expanded for as long as the menu is open so the
                // anchor item (and this popup) survive the pointer leaving the
                // bar surface.
                onOpened: tray.openMenuCount++
                onClosed: tray.openMenuCount--
            }
        }
    }
}
