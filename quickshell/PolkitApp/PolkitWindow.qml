import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
import qs.shared.ui

// The session's polkit agent: the password prompt for pkexec, timedatectl,
// systemctl and friends (the Update tab, the launcher's Uninstall, TimeApp…).
// It replaces polkit-gnome, whose prompt is a normal window and so always
// opened *under* the shell's overlay panels. This one is an overlay layer
// mapped after them (so on top) with exclusive keyboard focus, and it joins
// the open panel's focus grab (PolkitState) so using it doesn't close that panel.
// Only one agent can be registered per session: nothing else may start one.
CenterPanel {
    id: root
    ipcTarget: "polkit"
    ipcEnabled: false
    focusGrabEnabled: false
    cardWidth: 460
    cardHeight: 300

    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "shroomery-polkit"

    readonly property var flow: agent ? agent.flow : null
    // Set while the typed password is being checked, cleared by the next prompt.
    property bool checking: false

    function submit() {
        if (!flow || !flow.isResponseRequired || checking)
            return;
        checking = true;
        flow.submit(passwordField.text);
        passwordField.text = "";
    }

    function cancel() {
        if (flow && !flow.isCompleted)
            flow.cancelAuthenticationRequest();
    }

    // Registration can fail across a hot reload (the old instance still holds the session's agent
    // slot when the new one registers), and `path` can't be changed once set. So the agent lives
    // in a LazyLoader that is recreated, under a fresh path, every few seconds while unregistered.
    readonly property var agent: agentLoader.item
    property int registerAttempt: 0
    Timer {
        interval: 3000
        repeat: true
        running: !root.agent || !root.agent.isRegistered
        onTriggered: {
            root.registerAttempt++;
            agentLoader.active = false;
            agentLoader.active = true;
        }
    }

    LazyLoader {
        id: agentLoader
        active: true
        component: PolkitAgent {
            path: "/org/quickshell/PolkitAgent" + (root.registerAttempt > 0 ? root.registerAttempt : "")
            onAuthenticationRequestStarted: {
                root.checking = false;
                passwordField.text = "";
                root.open();
            }
            onIsActiveChanged: {
                if (!isActive)
                    root.close();
            }
        }
    }

    // `qs ipc call polkit status`: whether the agent is registered and a request is pending.
    IpcHandler {
        target: "polkit"
        function status(): string {
            const a = root.agent;
            return JSON.stringify({ registered: !!a && a.isRegistered, active: !!a && a.isActive,
                                    hasFlow: !!root.flow, open: root.isOpen, attempt: root.registerAttempt });
        }
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired) {
                root.checking = false;
                passwordField.forceActiveFocus();
            }
        }
        function onAuthenticationFailed() { root.checking = false; }
    }

    // Escape or the panel closing any other way cancels the request.
    onIsOpenChanged: {
        PolkitState.window = isOpen ? root : null;
        if (isOpen)
            passwordField.forceActiveFocus();
        else
            cancel();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        AppHeader {
            glyph: String.fromCodePoint(0xF033E) // lock
            title: "Authentication required"
            subtitle: root.flow ? root.flow.actionId : ""
        }

        Text {
            Layout.fillWidth: true
            text: root.flow ? root.flow.message : ""
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        FieldInput {
            id: passwordField
            Layout.fillWidth: true
            enabled: root.flow ? root.flow.isResponseRequired && !root.checking : false
            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
            placeholderText: root.flow && root.flow.inputPrompt !== ""
                ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
        }

        StatusChip {
            visible: text !== ""
            tone: root.checking ? "busy" : (root.flow && root.flow.supplementaryIsError ? "error" : "normal")
            text: root.checking ? "Checking…" : (root.flow ? root.flow.supplementaryMessage : "")
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Item { Layout.fillWidth: true }
            PanelButton {
                tonal: true
                text: "Cancel"
                onClicked: root.close()
            }
            PanelButton {
                filled: true
                text: "Authenticate"
                enabled: passwordField.enabled && passwordField.text !== ""
                onClicked: root.submit()
            }
        }
    }
}
