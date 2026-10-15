// shared/ui/ParamRow.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
// One parameter: name, slider, and a numeric field that accepts a typed
// value. The row never mutates its own `value` — it reports `moved()` and
// waits to be told the new state, so the owner stays the single source of
// truth.
ColumnLayout {
    id: row

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.1
    property string unit: ""
    property int decimals: 1

    signal moved(real value)

    spacing: 2

    function clamp(v) {
        return Math.max(row.from, Math.min(row.to, v));
    }

    function display(v) {
        return v.toFixed(row.decimals);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: row.label
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        // Typed entry. Commits on Enter or focus loss; reverts to the
        // authoritative value if what was typed is not a number.
        TextField {
            id: field
            implicitWidth: 62
            horizontalAlignment: Text.AlignRight
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 12
            padding: 4
            validator: DoubleValidator {
                bottom: row.from
                top: row.to
                decimals: row.decimals
                notation: DoubleValidator.StandardNotation
            }
            background: Rectangle {
                radius: 6
                color: Theme.surface_container
                border.color: field.activeFocus ? Theme.primary : Theme.outline_variant
                border.width: 1
            }
            Component.onCompleted: text = row.display(row.value)
            onEditingFinished: {
                const parsed = parseFloat(field.text);
                if (isNaN(parsed)) {
                    field.text = row.display(row.value);
                    return;
                }
                row.moved(row.clamp(parsed));
            }
        }

        Text {
            text: row.unit
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }

    Slider {
        id: slider
        Layout.fillWidth: true
        from: row.from
        to: row.to
        stepSize: row.stepSize

        // Seed once and re-push only while the handle is idle. A plain
        // `value: row.value` binding would be destroyed the first time the
        // user drags, because QQC2 Slider assigns to its own `value` during
        // interaction — the same trap documented in VolumeRow.qml.
        Component.onCompleted: value = row.value
        onMoved: row.moved(slider.value)

        Connections {
            target: row
            function onValueChanged() {
                if (!slider.pressed)
                    slider.value = row.value;
                if (!field.activeFocus)
                    field.text = row.display(row.value);
            }
        }

        WheelHandler {
            onWheel: event => {
                const dir = event.angleDelta.y > 0 ? 1 : -1;
                row.moved(row.clamp(row.value + dir * row.stepSize * 5));
            }
        }
    }
}
