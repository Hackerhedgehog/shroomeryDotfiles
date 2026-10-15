import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.BluetoothApp

PopoutPanel {
    id: root

    implicitWidth: standardWidth
    // Sized to the content (or the password dialog), up to the screen.
    implicitHeight: Math.min(maxHeight, Math.max(column.implicitHeight + 36,
        root.sudoOpen ? sudoBox.implicitHeight + 96 : 0))
    escapeHandler: function () {
        if (root.sudoOpen) {
            root.sudoOpen = false;
            return true;
        }
        return false;
    }

    property bool sudoOpen: false
    property string sudoError: ""
    property bool sudoRunning: false

    onActiveChanged: {
        if (active) {
            sudoOpen = false;
            sudoError = "";
            BluetoothState.openRequests += 1;
            BluetoothState.refresh();
            aliasField.text = BluetoothState.adapterDisplayName(BluetoothState.selectedAdapter);
        } else {
            BluetoothState.openRequests = Math.max(0, BluetoothState.openRequests - 1);
            BluetoothState.stopScan();
            sudoOpen = false;
        }
    }
    Component.onDestruction: if (active) BluetoothState.openRequests = Math.max(0, BluetoothState.openRequests - 1)

    component DeviceCard: Rectangle {
        id: card
        property var device: null
        property bool memoryOnly: false
        property string memoryName: ""
        property string memoryAddress: ""

        readonly property bool live: device !== null
        readonly property string title: live ? BluetoothState.displayName(device) : (memoryName !== "" ? memoryName : memoryAddress)
        readonly property string subtitle: live ? BluetoothState.describeDevice(device) : (memoryAddress + " · Not currently known to BlueZ")
        readonly property bool busy: live && (BluetoothState.isBusy(device.address) || device.pairing || device.state === BluetoothDeviceState.Connecting)
        readonly property var battery: live ? BluetoothState.batteryPercent(device) : null
        readonly property var rssi: live && !device.connected ? BluetoothState.rssiFor(device) : null

        Layout.fillWidth: true
        implicitHeight: 62
        radius: 8
        color: live && device.connected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Theme.surface_container_low
        border.color: live && device.connected ? Theme.primary : Theme.outline_variant
        border.width: 1
        opacity: memoryOnly ? 0.75 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: live && device.connected ? Theme.primary_container : Theme.surface_container_highest
                Image {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    sourceSize.width: 18
                    sourceSize.height: 18
                    fillMode: Image.PreserveAspectFit
                    visible: live
                    source: live ? BluetoothState.iconPathFor(device) : ""
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: live && device.connected ? Theme.on_primary_container : Theme.on_surface_variant
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !live
                    text: "○"
                    color: Theme.outline
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: card.title
                    color: memoryOnly ? Theme.outline : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: card.subtitle
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: card.battery !== null
                implicitHeight: 22
                implicitWidth: batRow.implicitWidth + 14
                radius: 11
                color: Theme.secondary_container
                RowLayout {
                    id: batRow
                    anchors.centerIn: parent
                    spacing: 3
                    Image {
                        source: Paths.icon("battery-medium")
                        width: 12
                        height: 12
                        sourceSize.width: 12
                        sourceSize.height: 12
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.on_secondary_container
                        }
                    }
                    Text {
                        text: card.battery + "%"
                        color: Theme.on_secondary_container
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            Text {
                visible: card.rssi !== null
                text: BluetoothState.signalLabel(card.rssi)
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Item {
                visible: card.busy
                implicitWidth: 18
                implicitHeight: 18
                Text {
                    anchors.centerIn: parent
                    text: "…"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }
            }

            PanelButton {
                visible: !card.busy && !card.memoryOnly && live && device.connected
                text: "Disconnect"
                onClicked: BluetoothState.disconnectDevice(device)
            }

            PanelButton {
                visible: !card.busy && !card.memoryOnly && live && !device.connected
                text: "Connect"
                tonal: true
                onClicked: BluetoothState.connectDevice(device)
            }

            PanelButton {
                visible: card.memoryOnly
                text: "Forget"
                onClicked: BluetoothState.forgetAddress(card.memoryAddress)
            }

            ActionIcon {
                visible: live && !card.memoryOnly && !card.busy
                iconTxt: "⋮"
                onClicked: deviceMenu.open()
                PanelMenu {
                    id: deviceMenu
                    implicitWidth: 260
                    MenuEntry {
                        text: live && device.trusted ? "Revoke trust (no auto-reconnect)" : "Trust (auto-reconnect)"
                        onTriggered: BluetoothState.setTrusted(card.device, !card.device.trusted)
                    }
                    MenuEntry {
                        text: "Forget this device"
                        onTriggered: BluetoothState.forgetDevice(card.device)
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Bluetooth"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }
                Text {
                    text: "Adapters, devices and this PC"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: chipRow.implicitWidth + 16
                radius: 13
                color: {
                    const label = BluetoothState.statusLabel;
                    if (label === "Unavailable" || label === "No adapter" || label === "Blocked")
                        return Theme.error_container;
                    if (label === "Scanning…")
                        return Theme.tertiary_container;
                    if (label === "On")
                        return Theme.primary_container;
                    return Theme.surface_container_highest;
                }
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: BluetoothState.statusLabel === "On" || BluetoothState.statusLabel === "Scanning…" ? "◉" : "○"
                        color: {
                            const label = BluetoothState.statusLabel;
                            if (label === "Unavailable" || label === "No adapter" || label === "Blocked")
                                return Theme.on_error_container;
                            if (label === "Scanning…")
                                return Theme.on_tertiary_container;
                            if (label === "On")
                                return Theme.on_primary_container;
                            return Theme.on_surface_variant;
                        }
                        font.pixelSize: 10
                    }
                    Text {
                        text: BluetoothState.statusLabel
                        color: {
                            const label = BluetoothState.statusLabel;
                            if (label === "Unavailable" || label === "No adapter" || label === "Blocked")
                                return Theme.on_error_container;
                            if (label === "Scanning…")
                                return Theme.on_tertiary_container;
                            if (label === "On")
                                return Theme.on_primary_container;
                            return Theme.on_surface_variant;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            ActionIcon {
                iconTxt: "↻"
                onClicked: BluetoothState.refresh()
            }

            ToggleSwitch {
                id: powerSwitch
                checked: BluetoothState.powered
                enabled: BluetoothState.selectedAdapter !== null && !BluetoothState.powerBusy && !BluetoothState.blocked
                onClicked: BluetoothState.setPowered(checked)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: BluetoothState.issues.length > 0
            implicitHeight: issuesColumn.implicitHeight + 20
            radius: 8
            color: Theme.error_container
            ColumnLayout {
                id: issuesColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Repeater {
                    model: BluetoothState.issues
                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.message
                        color: Theme.on_error_container
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PanelButton {
                        visible: BluetoothState.hasFixableIssues
                        text: BluetoothState.fixing ? "Working…" : "Fix"
                        filled: true
                        enabled: !BluetoothState.fixing
                        onClicked: {
                            sudoField.text = "";
                            sudoError = "";
                            sudoOpen = true;
                            sudoField.forceActiveFocus();
                        }
                    }
                    PanelButton {
                        text: "Re-check"
                        onClicked: BluetoothState.refreshStatus()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: BluetoothState.adapterModel.length > 1
            FieldLabel {
                text: "Adapter"
            }
            FieldCombo {
                Layout.fillWidth: true
                model: BluetoothState.adapterModel
                currentIndex: BluetoothState.adapterIndex
                onActivated: index => BluetoothState.selectAdapterByIndex(index)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.primary
            opacity: 0.3
        }

        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: Theme.primary
                    opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                }
            }

            ColumnLayout {
                width: scrollView.availableWidth
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 24
                    spacing: 8
                    visible: !BluetoothState.available
                    Text {
                        Layout.fillWidth: true
                        text: "Bluetooth stack unavailable"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Cannot reach the BlueZ daemon over D-Bus. Fix the issues shown above, then the device list will load automatically."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 24
                    spacing: 8
                    visible: BluetoothState.available && BluetoothState.selectedAdapter === null
                    Text {
                        Layout.fillWidth: true
                        text: "No Bluetooth adapter found"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Plug in a Bluetooth adapter or enable it in firmware."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 24
                    spacing: 8
                    visible: BluetoothState.available && BluetoothState.selectedAdapter !== null && !BluetoothState.powered
                    Text {
                        Layout.fillWidth: true
                        text: "Bluetooth is off"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Turn Bluetooth on to see and connect devices."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    PanelButton {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Turn on"
                        filled: true
                        onClicked: BluetoothState.setPowered(true)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: BluetoothState.available && BluetoothState.powered

                    SectionHeader {
                        label: "Connected"
                        visible: BluetoothState.connectedCount > 0
                    }
                    Repeater {
                        model: BluetoothState.selectedAdapter ? BluetoothState.selectedAdapter.devices : 0
                        delegate: DeviceCard {
                            required property var modelData
                            visible: modelData.connected
                            Layout.preferredHeight: visible ? implicitHeight : 0
                            device: modelData
                        }
                    }

                    SectionHeader {
                        label: "Saved"
                        visible: BluetoothState.savedCount > 0
                    }
                    Repeater {
                        model: BluetoothState.selectedAdapter ? BluetoothState.selectedAdapter.devices : 0
                        delegate: DeviceCard {
                            required property var modelData
                            visible: BluetoothState.isSaved(modelData)
                            Layout.preferredHeight: visible ? implicitHeight : 0
                            device: modelData
                        }
                    }
                    Repeater {
                        model: BluetoothState.memoryOnly
                        delegate: DeviceCard {
                            required property var modelData
                            memoryOnly: true
                            memoryName: modelData.name
                            memoryAddress: modelData.address
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Text {
                            text: "Nearby"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        PanelButton {
                            text: BluetoothState.scanning ? "Stop" : "Scan"
                            tonal: !BluetoothState.scanning
                            filled: BluetoothState.scanning
                            enabled: BluetoothState.powered
                            onClicked: BluetoothState.scanning ? BluetoothState.stopScan() : BluetoothState.startScan()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 1.5
                        visible: BluetoothState.scanning
                        color: Theme.surface_container_highest
                        Rectangle {
                            id: scanPulse
                            height: parent.height
                            width: parent.width * 0.4
                            radius: 1.5
                            color: Theme.primary
                            SequentialAnimation on x {
                                running: BluetoothState.scanning
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0
                                    to: scanPulse.parent ? scanPulse.parent.width - scanPulse.width : 0
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    from: scanPulse.parent ? scanPulse.parent.width - scanPulse.width : 0
                                    to: 0
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: BluetoothState.nearbyCount === 0
                        text: BluetoothState.scanning ? "Searching for devices…" : "No nearby devices. Press Scan to search, and make sure the device is in pairing mode."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }
                    Repeater {
                        model: BluetoothState.selectedAdapter ? BluetoothState.selectedAdapter.devices : 0
                        delegate: DeviceCard {
                            required property var modelData
                            visible: BluetoothState.isNearby(modelData)
                            Layout.preferredHeight: visible ? implicitHeight : 0
                            device: modelData
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.primary
                        opacity: 0.3
                        Layout.topMargin: 8
                    }

                    Text {
                        text: "This PC"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: pcColumn.implicitHeight + 24
                        radius: 8
                        color: Theme.surface_container_low
                        border.color: Theme.outline_variant
                        border.width: 1

                        ColumnLayout {
                            id: pcColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            FieldLabel {
                                text: "Adapter name"
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                TextField {
                                    id: aliasField
                                    Layout.fillWidth: true
                                    color: Theme.primary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    enabled: BluetoothState.powered
                                    background: Rectangle {
                                        implicitHeight: 36
                                        radius: 8
                                        color: Theme.surface_container
                                        border.color: Theme.primary
                                        border.width: 1
                                        opacity: aliasField.enabled ? 1 : 0.45
                                    }
                                    Keys.onReturnPressed: BluetoothState.setAdapterAlias(aliasField.text)
                                    Keys.onEnterPressed: BluetoothState.setAdapterAlias(aliasField.text)
                                }
                                PanelButton {
                                    text: "Save"
                                    filled: true
                                    enabled: BluetoothState.powered
                                    onClicked: BluetoothState.setAdapterAlias(aliasField.text)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Shown to other devices"
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Address: " + (BluetoothState.adapterAddress(BluetoothState.selectedAdapter) || "—")
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.primary
                                opacity: 0.3
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Discoverable"
                                    color: Theme.primary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    Layout.fillWidth: true
                                }
                                ToggleSwitch {
                                    checked: BluetoothState.selectedAdapter ? BluetoothState.selectedAdapter.discoverable : false
                                    enabled: BluetoothState.powered
                                    onClicked: BluetoothState.setDiscoverable(checked, BluetoothState.timeoutValues[BluetoothState.timeoutIndex])
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: BluetoothState.selectedAdapter && BluetoothState.selectedAdapter.discoverable ? "Visible to nearby devices as \"" + BluetoothState.adapterDisplayName(BluetoothState.selectedAdapter) + "\"" : "Other devices cannot find this PC"
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            FieldLabel {
                                text: "Stop being discoverable after"
                            }
                            FieldCombo {
                                Layout.fillWidth: true
                                model: BluetoothState.timeoutLabels
                                currentIndex: BluetoothState.timeoutIndex
                                enabled: BluetoothState.powered
                                onActivated: index => BluetoothState.setTimeoutByIndex(index)
                            }
                            Text {
                                visible: !BluetoothState.powered
                                Layout.fillWidth: true
                                text: "Turn Bluetooth on to change these settings."
                                color: Theme.on_surface_variant
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.primary
            opacity: 0.3
        }

        Text {
            Layout.fillWidth: true
            text: BluetoothState.statusText
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.sudoOpen
        color: Qt.rgba(0, 0, 0, 0.5)
        radius: 10
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!root.sudoRunning)
                    root.sudoOpen = false;
            }
        }
    }

    Rectangle {
        id: sudoBox
        visible: root.sudoOpen
        anchors.centerIn: parent
        width: parent.width - 48
        implicitHeight: sudoColumn.implicitHeight + 32
        radius: 10
        color: Theme.background
        border.color: Theme.primary
        border.width: 1

        ColumnLayout {
            id: sudoColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Text {
                text: "Administrator rights required"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }
            FieldLabel {
                text: "Your password is needed to run:"
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdText.implicitHeight + 16
                radius: 8
                color: Theme.surface_container
                Text {
                    id: cmdText
                    anchors.fill: parent
                    anchors.margins: 8
                    text: BluetoothState.fixCommands.join("\n")
                    color: Theme.primary
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
            TextField {
                id: sudoField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 14
                enabled: !root.sudoRunning
                placeholderText: "Sudo password"
                placeholderTextColor: Theme.on_surface_variant
                background: Rectangle {
                    implicitHeight: 36
                    radius: 8
                    color: Theme.surface_container
                    border.color: Theme.primary
                    border.width: 1
                }
                Keys.onReturnPressed: root.submitSudo()
                Keys.onEnterPressed: root.submitSudo()
                Keys.onEscapePressed: {
                    if (!root.sudoRunning)
                        root.sudoOpen = false;
                }
            }
            Text {
                visible: root.sudoError !== ""
                Layout.fillWidth: true
                text: root.sudoError
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                PanelButton {
                    text: "Cancel"
                    enabled: !root.sudoRunning
                    onClicked: root.sudoOpen = false
                }
                PanelButton {
                    text: root.sudoRunning ? "Working…" : "Authenticate"
                    filled: true
                    enabled: !root.sudoRunning && sudoField.text !== ""
                    onClicked: root.submitSudo()
                }
            }
        }
    }

    function submitSudo() {
        if (root.sudoRunning)
            return;
        const password = sudoField.text;
        sudoField.text = "";
        root.sudoError = "";
        root.sudoRunning = true;
        if (!BluetoothState.applyFixes(password))
            root.sudoRunning = false;
    }

    Connections {
        target: BluetoothState
        function onLiveRevisionChanged() {
            if (!aliasField.activeFocus) {
                const name = BluetoothState.adapterDisplayName(BluetoothState.selectedAdapter);
                if (aliasField.text !== name)
                    aliasField.text = name;
            }
        }
        function onFixingChanged() {
            if (!BluetoothState.fixing)
                root.sudoRunning = false;
            if (!BluetoothState.fixing && BluetoothState.errorMessage === "Incorrect password — try again.") {
                root.sudoError = BluetoothState.errorMessage;
                root.sudoOpen = true;
            } else if (!BluetoothState.fixing && BluetoothState.errorMessage !== "" && root.sudoOpen) {
                root.sudoError = BluetoothState.errorMessage;
            } else if (!BluetoothState.fixing && BluetoothState.errorMessage === "") {
                root.sudoOpen = false;
                root.sudoError = "";
            }
        }
    }
}
