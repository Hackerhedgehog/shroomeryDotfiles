import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.SettingsApp

// Night light in the settings panel: on/off now, schedule (off, fixed times,
// sunset to sunrise), temperature and brightness. State: NightLightState.
ColumnLayout {
    id: root

    readonly property var modes: ["off", "fixed", "sun"]

    spacing: 12

    SettingRow {
        label: "Night Light"
        ToggleSwitch {
            checked: NightLightState.running
            onToggled: {
                NightLightState.toggle()
                checked = Qt.binding(() => NightLightState.running)
            }
        }
        Item { implicitWidth: 28 }
    }

    TabPills {
        model: ["Off", "Fixed", "Sun"]
        currentIndex: Math.max(0, root.modes.indexOf(NightLightState.mode))
        onActivated: index => NightLightState.setMode(root.modes[index])
    }

    // Fixed schedule. A typed time commits on Enter/focus loss; an invalid
    // one is ignored and the field shows the stored time again.
    RowLayout {
        Layout.fillWidth: true
        visible: NightLightState.mode === "fixed"
        spacing: 10

        Text {
            text: "On at"
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        FieldInput {
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignHCenter
            text: NightLightState.onTime
            onEditingFinished: {
                NightLightState.setOnTime(text)
                text = Qt.binding(() => NightLightState.onTime)
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "Off at"
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        FieldInput {
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignHCenter
            text: NightLightState.offTime
            onEditingFinished: {
                NightLightState.setOffTime(text)
                text = Qt.binding(() => NightLightState.offTime)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: NightLightState.mode === "sun"
        wrapMode: Text.WordWrap
        text: NightLightState.sunset !== ""
            ? "On at sunset " + NightLightState.sunset + " · off at sunrise " + NightLightState.sunrise
            : "Sun times unavailable — using " + NightLightState.onTime + "–" + NightLightState.offTime
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }

    ParamRow {
        Layout.fillWidth: true
        label: "Temperature"
        from: 2500
        to: 6500
        stepSize: 100
        decimals: 0
        unit: "K"
        value: NightLightState.temperature
        onMoved: v => NightLightState.setTemperature(v)
    }

    ParamRow {
        Layout.fillWidth: true
        label: "Brightness"
        from: 50
        to: 100
        stepSize: 5
        decimals: 0
        unit: "%"
        value: NightLightState.gamma
        onMoved: v => NightLightState.setGamma(v)
    }
}
