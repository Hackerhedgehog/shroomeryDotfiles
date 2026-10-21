import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.BatteryPanel

// Battery charge and power profile in one module: profile icon (leaf / gauge /
// rocket) plus a charge-level battery icon, then the percentage. Hovering it
// grows the bar into the battery panel (BatteryPanel/BatteryPanel), where the profile is
// picked.
//
// Shown only on machines that actually have a laptop battery, so on a desktop
// it never appears — power-profile switching lives in the QuickSettingsPanel there.
// Battery data comes from the UPower display device; the profile comes from
// power-profiles-daemon through Quickshell's PowerProfiles.
Rectangle {
    id: battery

    // The aggregate battery UPower exposes for the whole machine.
    readonly property var device: UPower.displayDevice
    // True when this machine has a real, present laptop battery. This is the
    // sole condition for showing the module (a desktop reports none).
    readonly property bool hasBattery: device !== null
        && device.isLaptopBattery && device.isPresent
    // True while a power adapter is connected.
    readonly property bool pluggedIn: !UPower.onBattery
    // Rounded charge percentage (0–100). UPower's percentage is a 0.0–1.0
    // fraction, so scale it up before rounding.
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0

    // Charge-level icon: charging takes priority over the fill bars.
    readonly property string batteryIcon: {
        if (battery.pluggedIn)
            return Paths.icon("battery-charging")
        if (battery.percent <= 25)
            return Paths.icon("battery-low")
        if (battery.percent <= 75)
            return Paths.icon("battery-medium")
        return Paths.icon("battery-full")
    }

    readonly property bool collapsed: !hasBattery
    visible: !collapsed

    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    // Keyboard Return: open the battery panel (pinned).
    function activate(): void {
        PopoutState.openFrom("battery", battery, battery.screenName)
    }

    readonly property string screenName: QsWindow.window && QsWindow.window.screen
        ? QsWindow.window.screen.name : ""
    onScreenNameChanged: if (screenName !== "") PopoutState.registerAnchor(screenName, "battery", battery)
    Component.onDestruction: PopoutState.unregisterAnchor(screenName, "battery", battery)

    // Icon for the active power profile.
    readonly property string profileIcon: {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return Paths.icon("profile-power-saver")
        case PowerProfile.Performance: return Paths.icon("profile-performance")
        default: return Paths.icon("profile-balanced")
        }
    }

    readonly property bool active: mouseArea.containsMouse || battery.focused

    implicitWidth: collapsed ? 0 : row.implicitWidth + 12
    implicitHeight: 30
    radius: 15

    // Same accent-filled circle as the other clickable modules.
    color: active ? Theme.primary : "transparent"
    Behavior on color {
        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Image {
            Layout.alignment: Qt.AlignVCenter
            source: battery.profileIcon
            sourceSize.width: 18
            sourceSize.height: 18
            width: 18
            height: 18
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: battery.active ? Theme.background : Theme.primary
                Behavior on colorizationColor {
                    ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
                }
            }
        }

        Image {
            Layout.alignment: Qt.AlignVCenter
            source: battery.batteryIcon
            sourceSize.width: 18
            sourceSize.height: 18
            width: 18
            height: 18
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: battery.active ? Theme.background : Theme.primary
                Behavior on colorizationColor {
                    ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: battery.percent + "%"
            color: battery.active ? Theme.background : Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
            Behavior on color {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }
        }
    }

    // Clicking grows the bar into the battery panel; hovering moves a pinned
    // panel here. Right click toggles the Lenovo conservation mode.
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton
            ? ConservationState.toggle()
            : PopoutState.click(battery.screenName, "battery", battery)
        onContainsMouseChanged: containsMouse
            ? PopoutState.hover(battery.screenName, "battery", battery, false)
            : PopoutState.unhover(battery)
    }
}
