import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.SettingsApp
import "UpdateLogic.js" as Logic

// Safe system update in the SettingsApp: the recovery point (known-good) and
// the state of the last update, the update check, Update / System update, then
// Verify / Promote / Discard for an update that is not promoted yet, the log of
// the running command, Restore and the package cache. State and commands:
// UpdateState (shroomery/scripts/pkg-update.sh). Mutating commands ask for
// the polkit password; there is no force option here (CLI only).
ColumnLayout {
    id: root

    // The action waiting for a click on Confirm: "", "promote", "discard",
    // "keep1" or "clear".
    property string confirming: ""

    readonly property var status: UpdateState.status
    readonly property var knownGood: status && status.known_good ? status.known_good : null
    readonly property var pending: status && status.pending ? status.pending : null
    // The record `discard` keeps (pending.discarded/) until the next promote.
    readonly property var discarded: status && status.discarded ? status.discarded : null
    readonly property string pendingState: pending ? String(pending.state) : ""
    readonly property bool haveCheck: UpdateState.checkCount > 0 || UpdateState.checkError !== ""
    readonly property var result: resultChip()

    spacing: 12

    // The confirm row of a destructive action: what it does, Cancel, Confirm.
    component ConfirmRow: ColumnLayout {
        id: confirmRow
        property string message: ""
        property string confirmText: "Confirm"
        signal confirmed()
        signal cancelled()

        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: confirmRow.message
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            PanelButton {
                compact: true
                text: "Cancel"
                onClicked: confirmRow.cancelled()
            }
            PanelButton {
                compact: true
                filled: true
                text: confirmRow.confirmText
                enabled: !UpdateState.running
                onClicked: confirmRow.confirmed()
            }
        }
    }

    // One "name  old → new" list, scrolling inside when long.
    component PackageList: ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 176)
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        delegate: RowLayout {
            required property var modelData
            width: ListView.view.width - 12
            height: 22
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: modelData.name
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                text: modelData.old + "  →  " + modelData.new
                color: Theme.on_surface_variant
                font.family: "monospace"
                font.pixelSize: 11
            }
        }
    }

    function kindLabel(kind) {
        switch (kind) {
        case "apply": return "Update";
        case "promote": return "Promote";
        case "discard": return "Discard";
        case "fetch-missing": return "Fetch";
        case "cache-keep": return "Cache cleanup";
        case "cache-clear": return "Clear cache";
        }
        return "Command";
    }

    // The chip above the log: running, finished, cancelled, blocked or failed.
    // A cancelled password prompt (126/127) is not an error.
    function resultChip() {
        const kind = kindLabel(UpdateState.runKind);
        if (UpdateState.running)
            return { text: kind + " running", tone: "busy" };
        if (UpdateState.runKind === "")
            return null;
        const code = UpdateState.exitCode;
        if (code === 0)
            return { text: kind + " finished", tone: "good" };
        if (code === 126 || code === 127)
            return { text: "Cancelled, nothing changed", tone: "normal" };
        if (code === 3)
            return { text: "Another update operation runs", tone: "busy" };
        if (code === 4)
            return { text: "Blocked: an unverified update is pending", tone: "error" };
        return { text: kind + " failed", tone: "error" };
    }

    // What the recovery point means right now, in one sentence.
    function stateHint() {
        if (!status)
            return "pkg-update.sh status gave no answer.";
        if (pendingState === "running")
            return "An update is running, or one was interrupted before it finished.";
        if (pendingState === "failed" && Logic.partlyChanged(pending))
            return "The last update failed after it had partly changed packages (" + pending.changed + "). Do not reboot: restore now (Restore below), or finish the update (Discard, then Update; the known-good is kept).";
        if (pendingState === "failed")
            return "The last update failed before it changed a package. Discard the record to update again; the known-good is untouched.";
        if (pendingState === "awaiting-verification")
            return "Reboot if the kernel changed, then Verify and Promote. Discard ends the record without promoting: the update stays installed and the known-good stays the recovery point.";
        if (pending)
            return "The update record cannot be read. Discard it to update again; the known-good is untouched.";
        if (!knownGood)
            return "No recovery point yet. The first Update takes one before it changes anything.";
        if (discarded && status.matches !== true)
            return "The last update was discarded without being verified: it stays installed, and the known-good stays the recovery point (the next Update does not replace it). Restore brings the known-good back.";
        if (status.matches === true && knownGood.verified === false && knownGood.forced !== true)
            return "The installed kernel, drivers and boot packages match the recovery point, but it is a checkpoint that was never verified (promote marks a verified state).";
        if (status.matches === true)
            return "The installed kernel, drivers and boot packages match the recovery point.";
        return "The installed protected packages differ from the recovery point (changed outside this tool). The next Update replaces it with the installed state and keeps the old one as known-good.prev.";
    }

    function knownGoodText() {
        if (!knownGood)
            return "";
        const day = Logic.dayOf(knownGood.created);
        return "Known-good " + day + (knownGood.kernel ? " · kernel " + knownGood.kernel : "")
            + (knownGood.verified === false ? " · not verified" : "");
    }

    function pendingText() {
        if (!pending)
            return "";
        const day = Logic.dayOf(pending.started);
        return day !== "" ? "Update started " + day : "";
    }

    function confirmMessage() {
        const lost = "Rollback of packages that are not in the protected set is lost; the protected (known-good) archives are kept. ";
        if (confirming === "promote")
            return "Promote makes the installed, verified state the new known-good and replaces the old one.";
        if (confirming === "discard")
            return "Discard ends this update without promoting it: the update stays installed; the known-good stays the recovery point and the next Update does not replace it. Restore brings it back.";
        if (confirming === "keep1")
            return lost + "Only the newest version of every package stays in the cache.";
        if (confirming === "clear")
            return lost + "Every other package file is removed from the cache.";
        return "";
    }

    function runConfirmed() {
        const what = confirming;
        confirming = "";
        if (what === "promote")
            UpdateState.promote();
        else if (what === "discard")
            UpdateState.discard();
        else if (what === "keep1")
            UpdateState.run(["cache", "keep", "1"], "cache-keep");
        else if (what === "clear")
            UpdateState.cacheClear();
    }

    // A command started or the record changed: a pending confirmation is stale.
    Connections {
        target: UpdateState
        function onRunningChanged() { root.confirming = ""; }
    }
    onPendingStateChanged: if (confirming === "promote" || confirming === "discard") confirming = ""

    // --- RECOVERY POINT ---
    Card {
        Layout.fillWidth: true
        implicitHeight: stateColumn.implicitHeight + 28

        ColumnLayout {
            id: stateColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            SectionHeader { label: "Recovery point" }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                StatusChip {
                    text: UpdateState.chip.text
                    tone: UpdateState.chip.tone
                }
                StatusChip {
                    visible: root.pendingText() !== ""
                    text: root.pendingText()
                }
                StatusChip {
                    visible: root.knownGood !== null
                    text: root.knownGoodText()
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.stateHint()
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- UPDATES ---
    Card {
        Layout.fillWidth: true
        implicitHeight: updatesColumn.implicitHeight + 28

        ColumnLayout {
            id: updatesColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            SectionHeader { label: "Updates" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                PanelButton {
                    compact: true
                    glyph: String.fromCodePoint(0xF0450)
                    text: UpdateState.checking ? "Checking…" : "Check for updates"
                    enabled: !UpdateState.checking && !UpdateState.running
                    onClicked: UpdateState.check(false)
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.haveCheck && UpdateState.checkError === ""
                    text: UpdateState.count + (UpdateState.count === 1 ? " update" : " updates")
                        + (UpdateState.heldCount > 0 ? ", " + UpdateState.heldCount + " held back" : "")
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: !root.haveCheck || UpdateState.checkError !== "" }
            }

            Text {
                Layout.fillWidth: true
                visible: UpdateState.checkError !== ""
                text: UpdateState.checkError
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: !root.haveCheck && !UpdateState.checking
                text: "Nothing checked yet. The check changes nothing; from the second one on it re-downloads the package databases."
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: root.haveCheck && UpdateState.checkError === "" && UpdateState.count === 0 && UpdateState.heldCount === 0
                text: "The system is up to date."
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            PackageList {
                visible: UpdateState.count > 0
                model: UpdateState.updates
            }

            SectionHeader {
                visible: UpdateState.heldCount > 0
                label: "Held back by IgnorePkg"
            }
            PackageList {
                visible: UpdateState.heldCount > 0
                model: UpdateState.held
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PanelButton {
                    filled: true
                    glyph: String.fromCodePoint(0xF01DA)
                    text: "Update"
                    enabled: !UpdateState.running
                    onClicked: UpdateState.update(false)
                }
                PanelButton {
                    tonal: true
                    text: "System update"
                    enabled: !UpdateState.running
                    onClicked: UpdateState.update(true)
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                text: "Update keeps the packages in IgnorePkg and IgnoreGroup as they are; System update includes them. A recovery point is taken first and the update has to be verified and promoted afterwards."
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- AFTER AN UPDATE: VERIFY / PROMOTE / DISCARD ---
    Card {
        Layout.fillWidth: true
        visible: root.pending !== null
        implicitHeight: pendingColumn.implicitHeight + 28

        ColumnLayout {
            id: pendingColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            SectionHeader { label: root.pendingState === "failed" ? "The last update failed" : "Last update" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // A failed update can only be discarded.
                PanelButton {
                    visible: root.pendingState === "failed"
                    filled: true
                    glyph: String.fromCodePoint(0xF01B4)
                    text: "Discard"
                    enabled: !UpdateState.running
                    onClicked: root.confirming = "discard"
                }
                PanelButton {
                    visible: root.pendingState !== "failed"
                    compact: false
                    glyph: String.fromCodePoint(0xF012C)
                    text: UpdateState.verifying ? "Verifying…" : "Verify"
                    enabled: !UpdateState.verifying && !UpdateState.running
                    onClicked: UpdateState.verifyNow()
                }
                PanelButton {
                    visible: root.pendingState !== "failed"
                    filled: true
                    text: "Promote"
                    enabled: root.pendingState === "awaiting-verification" && !UpdateState.running
                    onClicked: root.confirming = "promote"
                }
                PanelButton {
                    visible: root.pendingState !== "failed"
                    text: "Discard"
                    enabled: !UpdateState.running
                    onClicked: root.confirming = "discard"
                }
                Item { Layout.fillWidth: true }
            }

            // The verify checks, one per line.
            ColumnLayout {
                Layout.fillWidth: true
                visible: UpdateState.verifyLines.length > 0
                spacing: 2

                Repeater {
                    model: UpdateState.verifyLines

                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        color: modelData.indexOf("FAIL") === 0 ? Theme.error
                            : modelData.indexOf("WARN") === 0 ? Theme.tertiary
                            : Theme.on_surface_variant
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ConfirmRow {
                visible: root.confirming === "promote" || root.confirming === "discard"
                message: root.confirmMessage()
                confirmText: root.confirming === "promote" ? "Promote" : "Discard"
                onCancelled: root.confirming = ""
                onConfirmed: root.runConfirmed()
            }
        }
    }

    // --- LOG OF THE LAST COMMAND ---
    Card {
        Layout.fillWidth: true
        visible: UpdateState.log !== ""
        implicitHeight: logColumn.implicitHeight + 28

        ColumnLayout {
            id: logColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            SectionHeader { label: "Output" }

            StatusChip {
                visible: root.result !== null
                text: root.result ? root.result.text : ""
                tone: root.result ? root.result.tone : "normal"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                radius: 10
                color: Theme.surface_container_lowest

                Flickable {
                    id: logFlick
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    contentWidth: width
                    contentHeight: logText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    function toEnd() {
                        contentY = Math.max(0, contentHeight - height);
                    }

                    TextEdit {
                        id: logText
                        width: logFlick.width - 10
                        text: UpdateState.log
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Theme.on_surface
                        selectionColor: Theme.primary_container
                        selectedTextColor: Theme.on_primary_container
                        font.family: "monospace"
                        font.pixelSize: 11
                    }

                    // Follow the end while the command runs.
                    Connections {
                        target: UpdateState
                        function onLogChanged() { Qt.callLater(logFlick.toEnd) }
                    }
                }
            }
        }
    }

    // --- ARCHIVES AND RESTORE ---
    Card {
        Layout.fillWidth: true
        implicitHeight: toolsColumn.implicitHeight + 28

        ColumnLayout {
            id: toolsColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            SettingRow {
                label: "Fetch missing archives"
                hint: "Download the recovery point's package archives the cache lacks, from the Arch Linux Archive"
                PanelButton {
                    compact: true
                    text: "Fetch"
                    enabled: !UpdateState.running
                    onClicked: UpdateState.fetchMissing()
                }
            }

            SettingRow {
                visible: root.knownGood !== null
                label: "Restore known-good"
                hint: "When the desktop does not start, run sudo " + Paths.recoveryScript + " from a TTY (Ctrl+Alt+F3); this opens it in a terminal"
                PanelButton {
                    compact: true
                    glyph: String.fromCodePoint(0xF006F)
                    text: "Restore"
                    onClicked: UpdateState.restore()
                }
            }
        }
    }

    // --- PACKAGE CACHE ---
    Card {
        Layout.fillWidth: true
        implicitHeight: cacheColumn.implicitHeight + 28

        ColumnLayout {
            id: cacheColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            SectionHeader { label: "Package cache" }

            SettingRow {
                label: "Size: " + Logic.formatBytes(UpdateState.cacheBytes)
                hint: "Protected (known-good) archives are hardlinks and stay whatever the cache is cleaned to"
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Versions kept per package after an update"
                from: Logic.KEEP.min
                to: Logic.KEEP.max
                stepSize: 1
                decimals: 0
                value: UpdateState.keep
                onMoved: v => UpdateState.setKeep(v)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PanelButton {
                    compact: true
                    text: "Keep latest 1"
                    enabled: !UpdateState.running
                    onClicked: root.confirming = "keep1"
                }
                PanelButton {
                    compact: true
                    text: "Clear all"
                    enabled: !UpdateState.running
                    onClicked: root.confirming = "clear"
                }
                Item { Layout.fillWidth: true }
            }

            ConfirmRow {
                visible: root.confirming === "keep1" || root.confirming === "clear"
                message: root.confirmMessage()
                confirmText: root.confirming === "keep1" ? "Keep latest 1" : "Clear all"
                onCancelled: root.confirming = ""
                onConfirmed: root.runConfirmed()
            }
        }
    }
}
