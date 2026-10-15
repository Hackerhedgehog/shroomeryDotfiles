import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import "CalendarModel.js" as Cal

// Month calendar, Monday first. The month name sits centered between the
// prev/next arrows; clicking it goes back to the current month. Scrolling
// anywhere on it moves a month per wheel notch. Fills the size it is given.
Item {
    id: cal

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December"]
    readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }
    readonly property var today: ({ y: clock.date.getFullYear(), m: clock.date.getMonth(), d: clock.date.getDate() })
    property int year: today.y
    property int month: today.m
    readonly property bool showingToday: year === today.y && month === today.m
    readonly property var grid: Cal.monthGrid(year, month, today)

    // Back to the current month (on open, and on a click on the month name).
    function reset(): void {
        cal.year = cal.today.y;
        cal.month = cal.today.m;
    }

    function shift(delta: int): void {
        const r = Cal.shiftMonth(cal.year, cal.month, delta);
        cal.year = r.year;
        cal.month = r.month;
    }

    // Wheel: one month per notch (120); touchpads add up their small deltas.
    property real wheelRest: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            cal.wheelRest += event.angleDelta.y;
            while (Math.abs(cal.wheelRest) >= 120) {
                // Down = later months.
                cal.shift(cal.wheelRest < 0 ? 1 : -1);
                cal.wheelRest += cal.wheelRest < 0 ? 120 : -120;
            }
        }
    }

    implicitWidth: 276
    implicitHeight: 246

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            ActionIcon {
                iconSrc: Paths.icon("chevron-left")
                onClicked: cal.shift(-1)
            }

            // As wide as the longest month name, so the arrows never move.
            TextMetrics {
                id: longestMonth
                text: "November 8888"
                font: monthLabel.font
            }

            Rectangle {
                implicitWidth: Math.ceil(longestMonth.advanceWidth) + 20
                implicitHeight: 28
                radius: 14
                color: monthMouse.containsMouse && !cal.showingToday
                    ? Theme.surface_container_high : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: monthLabel
                    anchors.centerIn: parent
                    text: cal.monthNames[cal.month] + " " + cal.year
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }

                MouseArea {
                    id: monthMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: cal.showingToday ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: cal.reset()
                }
            }

            ActionIcon {
                iconSrc: Paths.icon("chevron-right")
                onClicked: cal.shift(1)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 2
            columnSpacing: 2

            Repeater {
                model: cal.dayNames
                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            Repeater {
                model: cal.grid.days
                delegate: Item {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height, 30)
                        height: width
                        radius: width / 2
                        visible: parent.modelData.isToday
                        color: Theme.primary
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.day
                        color: parent.modelData.isToday ? Theme.background : Theme.on_background
                        opacity: parent.modelData.inMonth ? 1 : 0.3
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: parent.modelData.isToday
                    }
                }
            }
        }
    }
}
