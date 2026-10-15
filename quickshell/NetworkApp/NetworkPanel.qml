import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.shared
import qs.shared.ui
import qs.NetworkApp

PopoutPanel {
    id: root

    implicitWidth: standardWidth
    // Sized to the content, or to an open dialog when that is taller; up to
    // the screen, then the list scrolls.
    implicitHeight: Math.min(maxHeight, Math.max(column.implicitHeight + 36,
        root.promptKind !== "" ? promptBox.implicitHeight + 96 : 0,
        root.sudoOpen ? sudoBox.implicitHeight + 96 : 0,
        root.propertiesOpen ? maxHeight : 0))
    escapeHandler: function () {
        if (root.promptKind !== "") {
            root.promptKind = "";
            root.promptTarget = null;
            return true;
        }
        if (root.propertiesOpen) {
            root.propertiesOpen = false;
            return true;
        }
        if (root.sudoOpen) {
            if (!NetworkState.sudoRunning)
                root.sudoOpen = false;
            return true;
        }
        return false;
    }

    property bool sudoOpen: false
    property bool propertiesOpen: false

    // "" | "wifiPassword" | "forgetWifi" | "deleteWired"
    property string promptKind: ""
    property string promptTitle: ""
    property string promptLabel: ""
    property string promptBody: ""
    property string promptConfirm: ""
    property var promptTarget: null

    onActiveChanged: {
        if (active) {
            root.closeOverlays();
            NetworkState.openRequests += 1;
            NetworkState.refresh();
        } else {
            NetworkState.openRequests = Math.max(0, NetworkState.openRequests - 1);
            root.closeOverlays();
        }
    }
    Component.onDestruction: if (active) NetworkState.openRequests = Math.max(0, NetworkState.openRequests - 1)

    function closeOverlays() {
        promptKind = "";
        promptTarget = null;
        propertiesOpen = false;
        sudoOpen = false;
        NetworkState.sudoError = "";
    }

    // Four rising bars, filled up to the strength of the access point.
    component SignalBars: Item {
        property int signal: 0
        property color activeColor: Theme.primary
        property color inactiveColor: Theme.outline_variant
        implicitWidth: 18
        implicitHeight: 16
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 4 + index * 4
                    radius: 1
                    anchors.bottom: parent ? parent.bottom : undefined
                    color: index < NetworkState.signalBars(signal) ? activeColor : inactiveColor
                }
            }
        }
    }

    component MiniChip: Rectangle {
        property string label: ""
        property color chipColor: Theme.primary_container
        property color chipTextColor: Theme.on_primary_container
        implicitHeight: 20
        implicitWidth: chipText.implicitWidth + 14
        radius: 10
        color: chipColor
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            color: parent.chipTextColor
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Connect / Disconnect for a row; "Connecting…" / "Disconnecting…" while
    // the link is changing ([transition], from NetworkState.transition).
    component ConnectButton: PanelButton {
        property bool connected: false
        property string transition: ""
        signal connectClicked()
        signal disconnectClicked()
        text: transition === "connecting" ? "Connecting…"
            : transition === "disconnecting" ? "Disconnecting…"
            : connected ? "Disconnect" : "Connect"
        tonal: !connected && transition === ""
        enabled: transition === ""
        onClicked: connected ? disconnectClicked() : connectClicked()
    }

    // One row in any of the lists: an access point, a saved profile or a NIC.
    component ConnectionCard: Rectangle {
        id: card
        property bool active: false
        property string title: ""
        property string subtitle: ""
        property bool busy: false
        property int signal: -1
        property string glyph: ""
        property bool dimmed: false

        default property alias trailing: trailingRow.data

        Layout.fillWidth: true
        implicitHeight: 56
        radius: 8
        color: active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Theme.surface_container_low
        border.color: active ? Theme.primary : Theme.outline_variant
        border.width: 1
        opacity: dimmed ? 0.75 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: card.active ? Theme.primary_container : Theme.surface_container_highest
                SignalBars {
                    anchors.centerIn: parent
                    visible: card.signal >= 0
                    signal: card.signal
                    activeColor: card.active ? Theme.on_primary_container : Theme.primary
                    inactiveColor: card.active ? Qt.rgba(Theme.on_primary_container.r, Theme.on_primary_container.g, Theme.on_primary_container.b, 0.3) : Theme.outline_variant
                }
                Text {
                    anchors.centerIn: parent
                    visible: card.signal < 0
                    text: card.glyph
                    color: card.active ? Theme.on_primary_container : Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: card.title
                    color: card.dimmed ? Theme.outline : Theme.on_surface
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

            Item {
                visible: card.busy
                implicitWidth: 18
                implicitHeight: 18
                BusyIndicator {
                    anchors.fill: parent
                    running: card.busy
                }
            }

            RowLayout {
                id: trailingRow
                spacing: 6
                visible: !card.busy
            }
        }
    }

    // ------------------------------------------------------------------ prompts

    function openWifiPassword(view) {
        promptKind = "wifiPassword";
        promptTarget = view;
        promptTitle = "Connect to " + view.ap.ssid;
        promptLabel = view.ap.secured ? "Password (" + view.ap.security + ")" : "Password";
        promptBody = view.isSaved ? "The stored password was rejected. Enter it again." : "";
        promptConfirm = "Connect";
        passwordField.text = "";
        passwordField.forceActiveFocus();
    }

    function openForgetWifi(view) {
        promptKind = "forgetWifi";
        promptTarget = view;
        promptTitle = "Forget " + (view.ap ? view.ap.ssid : NetworkState.wifiProfileName(view)) + "?";
        promptBody = "The saved password and settings for this network will be removed.";
        promptConfirm = "Forget";
    }

    function openDeleteWired(profile) {
        promptKind = "deleteWired";
        promptTarget = profile;
        promptTitle = "Delete " + profile.name + "?";
        promptBody = "This removes the saved wired connection profile.";
        promptConfirm = "Delete";
    }

    function commitPrompt() {
        const kind = promptKind;
        const target = promptTarget;
        promptKind = "";
        promptTarget = null;
        if (!target)
            return;
        if (kind === "wifiPassword") {
            const password = passwordField.text;
            passwordField.text = "";
            NetworkState.connectNetwork(target, password);
        } else if (kind === "forgetWifi") {
            NetworkState.forgetProfile(target.ap ? target.saved : target);
        } else if (kind === "deleteWired") {
            NetworkState.forgetProfile(target);
        }
    }

    function connectNetwork(view) {
        // Unsaved secured networks always need a password up front; saved ones
        // reprompt only when NetworkManager rejects the stored secret.
        if (!view.isSaved && view.ap.secured && !view.ap.enterprise) {
            root.openWifiPassword(view);
            return;
        }
        NetworkState.connectNetwork(view, "");
    }

    function openSudo() {
        NetworkState.sudoError = "";
        sudoField.text = "";
        sudoOpen = true;
        sudoField.forceActiveFocus();
    }

    function submitSudo() {
        if (NetworkState.sudoRunning)
            return;
        const password = sudoField.text;
        sudoField.text = "";
        NetworkState.runPrivileged(password);
    }

    Connections {
        target: NetworkState
        function onPasswordNeededSsidChanged() {
            const ssid = NetworkState.passwordNeededSsid;
            if (ssid === "")
                return;
            NetworkState.passwordNeededSsid = "";
            const list = NetworkState.visibleNetworks;
            for (let i = 0; i < list.length; i++) {
                if (list[i].ap.ssid === ssid) {
                    root.openWifiPassword(list[i]);
                    return;
                }
            }
        }
        function onSudoRunningChanged() {
            if (!NetworkState.sudoRunning && NetworkState.sudoError === "")
                root.sudoOpen = false;
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
                    text: "Network"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }
                Text {
                    text: "Wi-Fi, wired and interfaces"
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
                    const label = NetworkState.statusLabel;
                    if (label === "Unavailable" || label === "Offline" || label === "Blocked")
                        return Theme.error_container;
                    if (label === "Scanning…")
                        return Theme.tertiary_container;
                    if (label === "Connected")
                        return Theme.primary_container;
                    return Theme.surface_container_highest;
                }
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: NetworkState.statusLabel === "Connected" || NetworkState.statusLabel === "Scanning…" ? "◉" : "○"
                        color: {
                            const label = NetworkState.statusLabel;
                            if (label === "Unavailable" || label === "Offline" || label === "Blocked")
                                return Theme.on_error_container;
                            if (label === "Scanning…")
                                return Theme.on_tertiary_container;
                            if (label === "Connected")
                                return Theme.on_primary_container;
                            return Theme.on_surface_variant;
                        }
                        font.pixelSize: 10
                    }
                    Text {
                        text: NetworkState.statusLabel
                        color: {
                            const label = NetworkState.statusLabel;
                            if (label === "Unavailable" || label === "Offline" || label === "Blocked")
                                return Theme.on_error_container;
                            if (label === "Scanning…")
                                return Theme.on_tertiary_container;
                            if (label === "Connected")
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
                onClicked: NetworkState.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: NetworkState.issues.length > 0
            implicitHeight: issuesColumn.implicitHeight + 20
            radius: 8
            color: Theme.error_container
            ColumnLayout {
                id: issuesColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Repeater {
                    model: NetworkState.issues
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
                        visible: NetworkState.fixableIssues().length > 0
                        text: "Fix"
                        filled: true
                        enabled: !NetworkState.sudoRunning
                        onClicked: {
                            NetworkState.pendingSudoArgv = [];
                            root.openSudo();
                        }
                    }
                    PanelButton {
                        text: "Re-check"
                        onClicked: NetworkState.refresh()
                    }
                }
            }
        }

        // A polkit-denied action that can be retried with sudo.
        Rectangle {
            Layout.fillWidth: true
            visible: NetworkState.pendingSudoArgv.length > 0
            implicitHeight: authColumn.implicitHeight + 20
            radius: 8
            color: Theme.tertiary_container
            ColumnLayout {
                id: authColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: NetworkState.errorMessage
                    color: Theme.on_tertiary_container
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PanelButton {
                        text: "Authenticate"
                        filled: true
                        onClicked: root.openSudo()
                    }
                    PanelButton {
                        text: "Dismiss"
                        onClicked: {
                            NetworkState.pendingSudoArgv = [];
                            NetworkState.errorMessage = "";
                        }
                    }
                }
            }
        }

        // Wi-Fi hard block: rfkill / airplane mode / a hardware switch.
        Rectangle {
            Layout.fillWidth: true
            visible: NetworkState.nmRunning && NetworkState.wifiHardBlocked && NetworkState.issues.length === 0
            implicitHeight: blockedRow.implicitHeight + 20
            radius: 8
            color: Theme.tertiary_container
            RowLayout {
                id: blockedRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi is hard-blocked (airplane mode, a hardware switch or rfkill)."
                    color: Theme.on_tertiary_container
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                PanelButton {
                    text: "Unblock"
                    filled: true
                    enabled: !NetworkState.isBusy("wifi-unblock")
                    onClicked: NetworkState.unblockWifi()
                }
            }
        }

        // Radios
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: radioColumn.implicitHeight + 20
            radius: 8
            color: Theme.surface_container_low
            border.color: Theme.outline_variant
            border.width: 1

            ColumnLayout {
                id: radioColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Wi-Fi"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }
                    Item {
                        visible: NetworkState.isBusy("wifi-toggle")
                        implicitWidth: 20
                        implicitHeight: 20
                        BusyIndicator {
                            anchors.fill: parent
                            running: parent.visible
                        }
                    }
                    ToggleSwitch {
                        visible: !NetworkState.isBusy("wifi-toggle")
                        checked: NetworkState.wifiEnabled
                        enabled: NetworkState.nmRunning && !NetworkState.wifiHardBlocked
                        onClicked: NetworkState.setWifiEnabled(checked)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Ethernet"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }
                    Item {
                        visible: NetworkState.isBusy("eth-toggle")
                        implicitWidth: 20
                        implicitHeight: 20
                        BusyIndicator {
                            anchors.fill: parent
                            running: parent.visible
                        }
                    }
                    ToggleSwitch {
                        visible: !NetworkState.isBusy("eth-toggle")
                        checked: NetworkState.ethernetOn
                        enabled: NetworkState.nmRunning && NetworkState.ethernetDevices.length > 0
                        onClicked: NetworkState.setEthernetEnabled(checked)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: NetworkState.wifiDevices.length > 1
                    FieldLabel {
                        text: "Wi-Fi adapter"
                    }
                    FieldCombo {
                        Layout.fillWidth: true
                        model: NetworkState.wifiIfnameLabels
                        currentIndex: NetworkState.wifiIfnameIndex
                        enabled: NetworkState.nmRunning
                        onActivated: index => NetworkState.setWifiIfnameByIndex(index)
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
                    visible: !NetworkState.nmRunning
                    Text {
                        Layout.fillWidth: true
                        text: NetworkState.nmcliMissing ? "NetworkManager is not installed" : "NetworkManager is not running"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: NetworkState.nmcliMissing ? "Install the networkmanager package, then reopen this panel." : "Start the service with the Fix button above; the lists load automatically once it answers."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: NetworkState.nmRunning

                    // ------------------------------------------- Wi-Fi

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 8
                        Text {
                            text: "Wi-Fi networks"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: NetworkState.scanAgeLabel()
                            visible: text !== "" && !NetworkState.scanning
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        PanelButton {
                            text: NetworkState.scanning ? "Scanning…" : "Scan"
                            tonal: !NetworkState.scanning
                            enabled: NetworkState.wifiEnabled && !NetworkState.scanning
                            onClicked: NetworkState.scanNow()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 1.5
                        visible: NetworkState.scanning
                        color: Theme.surface_container_highest
                        Rectangle {
                            id: scanPulse
                            height: parent.height
                            width: parent.width * 0.4
                            radius: 1.5
                            color: Theme.primary
                            SequentialAnimation on x {
                                running: NetworkState.scanning
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
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                        visible: !NetworkState.wifiEnabled || (NetworkState.visibleNetworks.length === 0 && !NetworkState.scanning)
                        text: !NetworkState.wifiEnabled ? "Wi-Fi is turned off." : "No networks found. Try scanning again."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: NetworkState.wifiEnabled ? NetworkState.visibleNetworks : []
                        delegate: ConnectionCard {
                            id: apCard
                            required property var modelData
                            active: modelData.isConnected
                            signal: modelData.ap.signal
                            title: modelData.ap.ssid
                            subtitle: NetworkState.describeNetwork(modelData)
                            readonly property string transition: NetworkState.transition("ap:" + modelData.ap.ssid,
                                modelData.saved ? modelData.saved.stateRaw : "")
                            busy: NetworkState.isBusy("ap:" + modelData.ap.ssid) && transition === ""

                            MiniChip {
                                visible: !apCard.modelData.isConnected && apCard.modelData.isSaved
                                label: "Saved"
                                chipColor: Theme.secondary_container
                                chipTextColor: Theme.on_secondary_container
                            }
                            MiniChip {
                                visible: !apCard.modelData.ap.secured
                                label: "Open"
                                chipColor: Theme.tertiary_container
                                chipTextColor: Theme.on_tertiary_container
                            }
                            ConnectButton {
                                connected: apCard.modelData.isConnected
                                transition: apCard.transition
                                onConnectClicked: root.connectNetwork(apCard.modelData)
                                onDisconnectClicked: NetworkState.disconnectNetwork(apCard.modelData)
                            }
                            ActionIcon {
                                iconTxt: "⋮"
                                onClicked: apMenu.open()
                                PanelMenu {
                                    id: apMenu
                                    MenuEntry {
                                        text: "Properties"
                                        onTriggered: {
                                            NetworkState.showNetworkProperties(apCard.modelData);
                                            root.propertiesOpen = true;
                                        }
                                    }
                                    MenuEntry {
                                        text: "Reconnect with a new password"
                                        enabled: apCard.modelData.ap.secured && !apCard.modelData.ap.enterprise
                                        onTriggered: root.openWifiPassword(apCard.modelData)
                                    }
                                    MenuEntry {
                                        text: "Forget this network"
                                        enabled: apCard.modelData.isSaved
                                        onTriggered: root.openForgetWifi(apCard.modelData)
                                    }
                                }
                            }
                        }
                    }

                    SectionHeader {
                        id: savedHeader
                        label: "Saved (not in range) · " + NetworkState.savedOutOfRange.length
                        visible: NetworkState.savedOutOfRange.length > 0
                        collapsible: true
                        expanded: false
                    }

                    Repeater {
                        model: savedHeader.expanded ? NetworkState.savedOutOfRange : []
                        delegate: ConnectionCard {
                            id: savedCard
                            required property var modelData
                            active: modelData.isActive
                            glyph: "◇"
                            title: NetworkState.wifiProfileName(modelData)
                            subtitle: NetworkState.describeSavedWifi(modelData)
                            readonly property string transition: NetworkState.transition("conn:" + modelData.uuid, modelData.stateRaw)
                            busy: NetworkState.isBusy("conn:" + modelData.uuid) && transition === ""
                            dimmed: !modelData.isActive

                            ConnectButton {
                                connected: savedCard.modelData.isActive
                                transition: savedCard.transition
                                onConnectClicked: NetworkState.activateProfile(savedCard.modelData)
                                onDisconnectClicked: NetworkState.deactivateProfile(savedCard.modelData)
                            }
                            ActionIcon {
                                iconTxt: "⋮"
                                onClicked: savedMenu.open()
                                PanelMenu {
                                    id: savedMenu
                                    MenuEntry {
                                        text: "Properties"
                                        onTriggered: {
                                            NetworkState.showProfileProperties(NetworkState.wifiProfileName(savedCard.modelData), savedCard.modelData.uuid);
                                            root.propertiesOpen = true;
                                        }
                                    }
                                    MenuEntry {
                                        text: "Forget this network"
                                        onTriggered: root.openForgetWifi(savedCard.modelData)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        implicitHeight: 1
                        color: Theme.primary
                        opacity: 0.3
                    }

                    // ------------------------------------------- Wired

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 8
                        Text {
                            text: "Wired connections"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        PanelButton {
                            visible: NetworkState.preferredWiredUuid !== ""
                            text: "Clear preference"
                            enabled: !NetworkState.isBusy("wired-preference")
                            onClicked: NetworkState.clearWiredPreference()
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: NetworkState.wiredProfiles.length >= 2
                        text: NetworkState.preferredWiredUuid === "" ? "Multiple wired interfaces are available. Pick “Set as preferred” on one of them to stop the network from switching between them." : "The preferred wired connection is pinned with a higher autoconnect priority and a lower route metric."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                        visible: NetworkState.wiredProfiles.length === 0 && NetworkState.orphanEthernetDevices.length === 0
                        text: "No wired connections detected."
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: NetworkState.wiredProfiles
                        delegate: ConnectionCard {
                            id: wiredCard
                            required property var modelData
                            readonly property bool preferred: NetworkState.preferredWiredUuid === modelData.uuid
                            active: modelData.isActive
                            glyph: preferred ? "★" : "▤"
                            title: modelData.name
                            subtitle: NetworkState.describeWired(modelData)
                            readonly property string transition: NetworkState.transition("conn:" + modelData.uuid, modelData.stateRaw)
                            busy: NetworkState.isBusy("conn:" + modelData.uuid) && transition === ""

                            ConnectButton {
                                connected: wiredCard.modelData.isActive
                                transition: wiredCard.transition
                                onConnectClicked: NetworkState.activateProfile(wiredCard.modelData)
                                onDisconnectClicked: NetworkState.deactivateProfile(wiredCard.modelData)
                            }
                            ActionIcon {
                                iconTxt: "⋮"
                                onClicked: wiredMenu.open()
                                PanelMenu {
                                    id: wiredMenu
                                    MenuEntry {
                                        text: "Set as preferred"
                                        enabled: !wiredCard.preferred
                                        onTriggered: NetworkState.setPreferredWired(wiredCard.modelData)
                                    }
                                    MenuEntry {
                                        text: "Clear preference"
                                        enabled: wiredCard.preferred
                                        onTriggered: NetworkState.clearWiredPreference()
                                    }
                                    MenuEntry {
                                        text: "Properties"
                                        onTriggered: {
                                            NetworkState.showProfileProperties(wiredCard.modelData.name, wiredCard.modelData.uuid);
                                            root.propertiesOpen = true;
                                        }
                                    }
                                    MenuEntry {
                                        text: "Delete this profile"
                                        onTriggered: root.openDeleteWired(wiredCard.modelData)
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: NetworkState.orphanEthernetDevices
                        delegate: ConnectionCard {
                            id: nicCard
                            required property var modelData
                            active: modelData.connected
                            glyph: "▤"
                            title: modelData.name
                            subtitle: modelData.stateRaw
                            readonly property string transition: NetworkState.transition("dev:" + modelData.name, modelData.stateRaw)
                            busy: NetworkState.isBusy("dev:" + modelData.name) && transition === ""
                            dimmed: modelData.unavailable

                            ConnectButton {
                                visible: !nicCard.modelData.unavailable || nicCard.transition !== ""
                                connected: nicCard.modelData.connected
                                transition: nicCard.transition
                                onConnectClicked: NetworkState.connectDevice(nicCard.modelData.name)
                                onDisconnectClicked: NetworkState.disconnectDevice(nicCard.modelData.name)
                            }
                            ActionIcon {
                                iconTxt: "⋮"
                                onClicked: nicMenu.open()
                                PanelMenu {
                                    id: nicMenu
                                    MenuEntry {
                                        text: "Properties"
                                        onTriggered: {
                                            NetworkState.showDeviceProperties(nicCard.modelData);
                                            root.propertiesOpen = true;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // -------------------------------- Other interfaces

                    SectionHeader {
                        id: otherHeader
                        label: "Other interfaces · " + NetworkState.otherDevices.length
                        visible: NetworkState.otherDevices.length > 0
                        collapsible: true
                        expanded: false
                    }

                    Repeater {
                        model: otherHeader.expanded ? NetworkState.otherDevices : []
                        delegate: ConnectionCard {
                            id: otherCard
                            required property var modelData
                            glyph: "◈"
                            title: modelData.name
                            subtitle: modelData.typeRaw + " · " + modelData.stateRaw
                            dimmed: true

                            ActionIcon {
                                iconTxt: "⋮"
                                onClicked: otherMenu.open()
                                PanelMenu {
                                    id: otherMenu
                                    MenuEntry {
                                        text: "Properties"
                                        onTriggered: {
                                            NetworkState.showDeviceProperties(otherCard.modelData);
                                            root.propertiesOpen = true;
                                        }
                                    }
                                }
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: NetworkState.statusText
                color: NetworkState.errorMessage !== "" ? Theme.error : Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            PanelButton {
                visible: NetworkState.errorDetail !== ""
                text: "Details"
                onClicked: {
                    NetworkState.propertiesTitle = "Error details";
                    NetworkState.propertiesLoading = false;
                    NetworkState.propertyRows = [["Message", NetworkState.errorMessage], ["Output", NetworkState.errorDetail]];
                    root.propertiesOpen = true;
                }
            }
        }
    }

    // ------------------------------------------------------------- overlays

    Rectangle {
        anchors.fill: parent
        visible: root.promptKind !== "" || root.propertiesOpen || root.sudoOpen
        color: Qt.rgba(0, 0, 0, 0.5)
        radius: 10
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (NetworkState.sudoRunning)
                    return;
                root.promptKind = "";
                root.promptTarget = null;
                root.propertiesOpen = false;
                root.sudoOpen = false;
            }
        }
    }

    Rectangle {
        id: promptBox
        visible: root.promptKind !== ""
        anchors.centerIn: parent
        width: parent.width - 48
        implicitHeight: promptColumn.implicitHeight + 32
        radius: 10
        color: Theme.background
        border.color: Theme.primary
        border.width: 1

        ColumnLayout {
            id: promptColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: root.promptTitle
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.promptBody !== ""
                text: root.promptBody
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            FieldLabel {
                visible: root.promptKind === "wifiPassword"
                text: root.promptLabel
            }
            TextField {
                id: passwordField
                visible: root.promptKind === "wifiPassword"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 14
                placeholderText: "Network password"
                placeholderTextColor: Theme.on_surface_variant
                background: Rectangle {
                    implicitHeight: 36
                    radius: 8
                    color: Theme.surface_container
                    border.color: Theme.primary
                    border.width: 1
                }
                Keys.onReturnPressed: root.commitPrompt()
                Keys.onEnterPressed: root.commitPrompt()
                Keys.onEscapePressed: {
                    root.promptKind = "";
                    root.promptTarget = null;
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                PanelButton {
                    text: "Cancel"
                    onClicked: {
                        root.promptKind = "";
                        root.promptTarget = null;
                    }
                }
                PanelButton {
                    text: root.promptConfirm
                    filled: true
                    onClicked: root.commitPrompt()
                }
            }
        }
    }

    Rectangle {
        id: propertiesBox
        visible: root.propertiesOpen
        anchors.centerIn: parent
        width: parent.width - 40
        height: Math.min(parent.height - 80, propertiesColumn.implicitHeight + 32)
        radius: 10
        color: Theme.background
        border.color: Theme.primary
        border.width: 1
        clip: true

        ColumnLayout {
            id: propertiesColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: NetworkState.propertiesTitle
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                }
                PanelButton {
                    text: "Close"
                    onClicked: root.propertiesOpen = false
                }
            }
            Text {
                visible: NetworkState.propertiesLoading
                text: "Loading…"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 320
                clip: true
                model: NetworkState.propertyRows
                spacing: 6
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    Text {
                        text: modelData[0]
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        Layout.preferredWidth: 150
                        wrapMode: Text.Wrap
                    }
                    Text {
                        text: modelData[1]
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: Theme.primary
                        opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                    }
                }
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
                    text: NetworkState.sudoCommandPreview().join("\n")
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
                enabled: !NetworkState.sudoRunning
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
                    if (!NetworkState.sudoRunning)
                        root.sudoOpen = false;
                }
            }
            Text {
                visible: NetworkState.sudoError !== ""
                Layout.fillWidth: true
                text: NetworkState.sudoError
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
                    enabled: !NetworkState.sudoRunning
                    onClicked: root.sudoOpen = false
                }
                PanelButton {
                    text: NetworkState.sudoRunning ? "Working…" : "Authenticate"
                    filled: true
                    enabled: !NetworkState.sudoRunning && sudoField.text !== ""
                    onClicked: root.submitSudo()
                }
            }
        }
    }
}
