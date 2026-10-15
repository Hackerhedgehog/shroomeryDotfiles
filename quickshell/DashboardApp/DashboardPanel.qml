import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.DashboardApp

// The dashboard the status bar grows into when the clock is hovered: a tab
// row over the current tab, which slides in from the side it comes from;
// the panel morphs to each tab's size. Every open starts on the first tab.
// Stats and weather only refresh while it is open.
PopoutPanel {
    id: root

    property int currentTab: 0
    // One name per child of `stage`, same order.
    readonly property var tabNames: ["Dash", "Media", "Performance", "Weather"]
    readonly property Item currentTabItem: stage.children[root.currentTab] || null

    implicitWidth: Math.max(tabRow.implicitWidth, currentTabItem ? currentTabItem.implicitWidth : 0) + 36
    implicitHeight: Math.min(maxHeight,
        tabRow.implicitHeight + 14 + (currentTabItem ? currentTabItem.implicitHeight : 0) + 36)

    onActiveChanged: {
        if (active) {
            root.currentTab = 0;
            SystemStats.consumers += 1;
            Weather.refreshIfStale();
        } else {
            SystemStats.consumers = Math.max(0, SystemStats.consumers - 1);
        }
    }
    Component.onDestruction: if (active) SystemStats.consumers = Math.max(0, SystemStats.consumers - 1)

    RowLayout {
        id: tabRow
        x: Math.round((root.width - implicitWidth) / 2)
        y: 18
        spacing: 4

        Repeater {
            model: root.tabNames
            delegate: Rectangle {
                required property string modelData
                required property int index
                readonly property bool current: root.currentTab === index

                implicitWidth: label.implicitWidth + 28
                implicitHeight: 32
                radius: 16
                color: current ? Theme.primary_container
                    : (tabMouse.containsMouse ? Theme.surface_container_high : "transparent")
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.current ? Theme.on_primary_container : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: parent.current
                }
                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.currentTab = parent.index
                }
            }
        }
    }

    // The tabs, one child per tabNames entry, in order.
    Item {
        id: stage
        x: 18
        y: tabRow.y + tabRow.implicitHeight + 14
        width: root.width - 36
        height: root.height - y - 18

        DashTab {
            id: dash
            tabIndex: 0
            currentTab: root.currentTab
            active: root.active && shown
            onRequestTab: index => { if (index < root.tabNames.length) root.currentTab = index; }
        }

        MediaTab {
            // Every tab is as wide as Dash.
            implicitWidth: dash.implicitWidth
            tabIndex: 1
            currentTab: root.currentTab
            active: root.active && shown
        }

        PerformanceTab {
            // Every tab is as wide as Dash.
            implicitWidth: dash.implicitWidth
            tabIndex: 2
            currentTab: root.currentTab
            active: root.active && shown
        }

        WeatherTab {
            // Every tab is as wide as Dash.
            implicitWidth: dash.implicitWidth
            tabIndex: 3
            currentTab: root.currentTab
            active: root.active && shown
        }
    }
}
