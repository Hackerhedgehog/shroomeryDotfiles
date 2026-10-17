import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.shared
// One labelled slider row: a clickable icon, a themed 0–100 slider, and a
// percentage. Scrolling over the slider itself steps the value by 5; the icon
// and the percentage label are not scroll targets (the WheelHandler is a child
// of the Slider, not of the row).
RowLayout {
    id: row

    property string iconSrc: ""
    // Current value, 0–100. The owner writes this from the real state; the
    // row never mutates it directly, it only emits moved().
    property int value: 0
    // Lowest value the slider can reach (brightness never goes to zero).
    property int minimum: 0
    property bool available: true

    signal moved(int value)
    signal iconClicked()

    spacing: 15
    opacity: row.available ? 1 : 0.4
    enabled: row.available

    function clamp(v) {
        return Math.max(row.minimum, Math.min(100, Math.round(v)))
    }

    // Raise or lower by one 5% step; used by the wheel handler.
    function step(dir: int): void {
        row.moved(row.clamp(row.value + dir * 5))
    }

    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 24
        implicitHeight: 24

        Image {
            anchors.centerIn: parent
            source: row.iconSrc
            width: 20
            height: 20
            sourceSize.width: 20
            sourceSize.height: 20
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: Theme.primary
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.iconClicked()
        }
    }

    Slider {
        id: slider
        Layout.fillWidth: true
        from: row.minimum
        to: 100

        // Track row.value unless the user is actively dragging. A plain
        // `value: row.value` binding would be severed the first time the
        // user drags the handle (QQC2 Slider assigns to its own `value`
        // during interaction, which destroys any declarative binding on
        // it) and the slider would then freeze forever, never reflecting
        // outside changes (wpctl, brightnessctl, media keys) again. Instead
        // we seed it once and re-push it on every external change, but only
        // while the handle isn't pressed, mirroring the same pattern used
        // for the AudioPanel mixer sliders (see AudioPanel/VolumeRow.qml).
        Component.onCompleted: value = row.value
        onMoved: row.moved(row.clamp(value))

        Connections {
            target: row
            function onValueChanged() {
                if (!slider.pressed)
                    slider.value = row.value
            }
        }

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 6
            width: slider.availableWidth
            height: implicitHeight
            radius: 3
            color: Theme.background
            border.color: Theme.primary
            border.width: 1

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                color: Theme.primary
                radius: 3
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 16
            implicitHeight: 16
            radius: 8
            color: slider.pressed ? Theme.background : Theme.primary
            border.color: Theme.primary
            border.width: 1
        }

        WheelHandler {
            onWheel: event => row.step(event.angleDelta.y > 0 ? 1 : -1)
        }
    }

    Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: row.value + "%"
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }
}
