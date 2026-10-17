import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.shared
import qs.shared.ui

// Battery details, the power-profile switch and what idling / closing the lid
// does: the panel the status bar grows into from the battery module. Charge
// data comes from the UPower display device, the profile from
// power-profiles-daemon (D-Bus, through Quickshell's PowerProfiles), idle and
// lid actions from IdleState (hypridle.conf, logind.conf).
PopoutPanel {
    id: root

    implicitWidth: standardWidth
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 36)
    // The password prompt for logind.conf is another window: keep the panel
    // open while it is up.
    holdOpen: IdleState.lidPending !== null

    // Lid choices for `key`; the plugged-in one can follow the battery one.
    // The current action stays listed even when this machine can't do it
    // (hibernate without swap) or the menu doesn't know it (set by hand).
    function lidOptions(key: string): var {
        const list = (key === "HandleLidSwitchExternalPower"
            ? [{ value: "", label: "Same as on battery" }] : []).concat(IdleState.lidActions);
        const current = IdleState.lidAction(key);
        if (!list.some(option => option.value === current)) {
            const known = IdleState.allLidActions.find(option => option.value === current);
            list.push({ value: current, label: known ? known.label + " (unavailable)" : current });
        }
        return list;
    }

    readonly property var device: UPower.displayDevice
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool pluggedIn: !UPower.onBattery

    // "1 h 05 min" / "42 min"; "" for an unknown (0) estimate.
    function formatDuration(seconds: real): string {
        if (!(seconds > 0))
            return "";
        const minutes = Math.round(seconds / 60);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        if (h === 0)
            return m + " min";
        return h + " h " + (m < 10 ? "0" : "") + m + " min";
    }

    // One line under the percentage: what the battery is doing right now.
    readonly property string stateText: {
        if (!device)
            return "";
        switch (device.state) {
        case UPowerDeviceState.Charging: {
            const t = formatDuration(device.timeToFull);
            return t !== "" ? "Charging · " + t + " until full" : "Charging";
        }
        case UPowerDeviceState.Discharging: {
            const t = formatDuration(device.timeToEmpty);
            return t !== "" ? "On battery · " + t + " left" : "On battery";
        }
        case UPowerDeviceState.FullyCharged:
            return "Fully charged";
        case UPowerDeviceState.PendingCharge:
            return "Plugged in · not charging";
        case UPowerDeviceState.Empty:
            return "Empty";
        default:
            return pluggedIn ? "Plugged in" : "On battery";
        }
    }

    readonly property string batteryIcon: {
        if (pluggedIn)
            return Paths.icon("battery-charging");
        if (percent <= 25)
            return Paths.icon("battery-low");
        if (percent <= 75)
            return Paths.icon("battery-medium");
        return Paths.icon("battery-full");
    }

    // Selectable profiles, lowest power first. Performance only when the
    // daemon offers it.
    readonly property var profiles: {
        const list = [
            { value: PowerProfile.PowerSaver, label: "Power Saver", icon: "profile-power-saver",
              detail: "Longer battery life, reduced performance" },
            { value: PowerProfile.Balanced, label: "Balanced", icon: "profile-balanced",
              detail: "Standard performance and power use" }
        ];
        if (PowerProfiles.hasPerformanceProfile)
            list.push({ value: PowerProfile.Performance, label: "Performance", icon: "profile-performance",
                        detail: "Highest performance, more power and heat" });
        return list;
    }

    readonly property string degradedText: {
        switch (PowerProfiles.degradationReason) {
        case PerformanceDegradationReason.LapDetected:
            return "Performance is limited: the laptop is on your lap.";
        case PerformanceDegradationReason.HighTemperature:
            return "Performance is limited: the system is running hot.";
        default:
            return "";
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 18
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
            policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Theme.primary
                opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
            }
        }

        ColumnLayout {
            id: column
            width: flick.width
            spacing: 10

            PanelTitle {
                title: "Battery"
                subtitle: "Charge, power profile, idle and lid"
            }

            // ------------------------------------------------------------ charge

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: chargeColumn.implicitHeight + 24
                radius: 8
                color: Theme.surface_container_low
                border.color: Theme.outline_variant
                border.width: 1

                ColumnLayout {
                    id: chargeColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: 20
                            color: Theme.primary_container
                            ColoredIcon {
                                anchors.centerIn: parent
                                source: root.batteryIcon
                                size: 22
                                color: Theme.on_primary_container
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: root.percent + "%"
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: 22
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.stateText
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Charge bar.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.surface_container_highest
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.percent / 100))
                            height: parent.height
                            radius: 3
                            color: root.percent <= 15 && !root.pluggedIn ? Theme.error : Theme.primary
                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
                            }
                        }
                    }

                    // Power draw and wear, when UPower knows them.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: rateText.text !== "" || healthText.text !== ""
                        Text {
                            id: rateText
                            Layout.fillWidth: true
                            text: root.device && Math.abs(root.device.changeRate) >= 0.1
                                ? Math.abs(root.device.changeRate).toFixed(1) + " W" : ""
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            id: healthText
                            text: root.device && root.device.healthSupported
                                ? "Health " + Math.round(root.device.healthPercentage) + "%" : ""
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // ----------------------------------------------------------- profile

            SectionHeader {
                label: "Power profile"
            }

            Repeater {
                model: root.profiles
                delegate: Rectangle {
                    id: profileCard
                    required property var modelData
                    readonly property bool selected: PowerProfiles.profile === modelData.value

                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 8
                    color: selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : cardMouse.containsMouse ? Theme.surface_container : Theme.surface_container_low
                    border.color: selected ? Theme.primary : Theme.outline_variant
                    border.width: 1
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutQuint }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 16
                            color: profileCard.selected ? Theme.primary_container : Theme.surface_container_highest
                            ColoredIcon {
                                anchors.centerIn: parent
                                source: Paths.icon(profileCard.modelData.icon)
                                size: 18
                                color: profileCard.selected ? Theme.on_primary_container : Theme.on_surface_variant
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: profileCard.modelData.label
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: profileCard.modelData.detail
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            visible: profileCard.selected
                            text: "✓"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = profileCard.modelData.value
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.degradedText !== ""
                text: root.degradedText
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            // -------------------------------------------------------------- idle

            SectionHeader {
                label: "When idle"
            }

            Card {
                Layout.fillWidth: true
                implicitHeight: idleColumn.implicitHeight + 24

                ColumnLayout {
                    id: idleColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 8

                    Repeater {
                        model: IdleState.listeners
                        delegate: SettingRow {
                            id: idleRow
                            required property var modelData
                            required property int index
                            label: modelData.label
                            FieldCombo {
                                compact: true
                                Layout.preferredWidth: 130
                                model: idleRow.modelData.choices.labels
                                boundIndex: idleRow.modelData.choices.index
                                onActivated: i => IdleState.setIdleTimeout(idleRow.index,
                                    idleRow.modelData.choices.values[i])
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: IdleState.listeners.length === 0
                        text: "No listeners in hypridle.conf."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
            }

            // --------------------------------------------------------------- lid

            SectionHeader {
                label: "When the lid closes"
                visible: IdleState.lidPresent
            }

            Card {
                Layout.fillWidth: true
                visible: IdleState.lidPresent
                implicitHeight: lidColumn.implicitHeight + 24

                ColumnLayout {
                    id: lidColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 8

                    Repeater {
                        model: [
                            { key: "HandleLidSwitch", label: "On battery" },
                            { key: "HandleLidSwitchExternalPower", label: "Plugged in" }
                        ]
                        delegate: SettingRow {
                            id: lidRow
                            required property var modelData
                            readonly property var options: root.lidOptions(modelData.key)
                            label: modelData.label
                            FieldCombo {
                                compact: true
                                Layout.preferredWidth: 190
                                enabled: IdleState.lidPending === null
                                model: lidRow.options.map(option => option.label)
                                boundIndex: lidRow.options.findIndex(
                                    option => option.value === IdleState.lidAction(lidRow.modelData.key))
                                onActivated: i => IdleState.setLid(lidRow.modelData.key, lidRow.options[i].value)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: IdleState.lidError !== "" ? IdleState.lidError
                            : IdleState.lidPending !== null ? "Waiting for the password…" : ""
                        color: IdleState.lidError !== "" ? Theme.error : Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
