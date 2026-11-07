import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.StatusbarApp
import "TimeLogic.js" as Logic

// Date, time, timezone, clock format and system locale (SUPER+T), in the
// middle of the screen. System changes go through shroomery/scripts/time.sh
// (timedatectl / localectl / pkexec: the polkit agent asks for the password).
// The clock format is the status bar's ("clock" in statusbar.json, through
// StatusbarState), which the dashboard and notifications follow too.
// Automatic timezone: settings/time.json, run by listeners/auto-timezone.sh.
CenterPanel {
    id: root
    ipcTarget: "time"
    cardWidth: 780
    cardHeight: 640

    readonly property var tabs: ["Date & time", "Clock format", "Language & region"]
    property int tab: 0

    // time.sh status.
    property var status: null
    property var timezones: []
    property var locales: []
    readonly property var installedLocales: locales.filter(l => l.installed)
    readonly property var otherLocales: locales.filter(l => !l.installed)
        .map(l => ({ key: l.name, label: l.label, detail: "" }))

    // The system locale being edited; Apply sends it to localectl.
    property var localeDraft: ({})
    readonly property var systemLocale: status ? status.locale : ({})
    readonly property bool localeDirty: !Logic.sameDraft(localeDraft, systemLocale)

    property string message: ""
    property string messageTone: "normal"
    property bool busy: false

    readonly property var clockSettings: StatusbarState.settings.clock
    readonly property var timeParts: Logic.parseTimeFormat(clockSettings.format)

    function setMessage(text, tone) {
        message = text;
        messageTone = tone;
    }

    function refreshStatus() {
        statusProc.running = false;
        statusProc.running = true;
    }

    // One system change at a time: ARGS for time.sh, BUSYTEXT while it runs,
    // OKTEXT after, THEN (optional) on success.
    function run(args, busyText, okText, then) {
        if (busy)
            return;
        busy = true;
        setMessage(busyText, "busy");
        actionProc.okText = okText;
        actionProc.then = then || null;
        actionProc.command = [Paths.timeScript].concat(args);
        actionProc.running = true;
    }

    function setNtp(on) {
        run(["set-ntp", on ? "on" : "off"], "Waiting for permission…",
            on ? "Automatic time on" : "Automatic time off", null);
    }

    function setTime() {
        const value = Logic.composeDateTime(dateField.text, timeField.text);
        if (value === "") {
            setMessage("Enter the date as YYYY-MM-DD and the time as HH:MM:SS", "error");
            return;
        }
        run(["set-time", value], "Waiting for permission…", "Time set", null);
    }

    function setTimezone(zone) {
        if (!status || zone === status.timezone)
            return;
        run(["set-timezone", zone], "Waiting for permission…", "Timezone: " + zone, () => Date.timeZoneUpdated());
    }

    function writeAutoTimezone(on) {
        timeSettings.setText(JSON.stringify({ "autoTimezone": on }, null, 4) + "\n");
    }

    // Turning it on asks once (polkit rule) so the listener can change the
    // timezone later without a prompt, then looks the timezone up now.
    function setAutoTimezone(on) {
        if (!on) {
            writeAutoTimezone(false);
            setMessage("Automatic timezone off", "normal");
            refreshStatus();
            return;
        }
        const lookUp = () => {
            writeAutoTimezone(true);
            busy = false;
            run(["auto-timezone"], "Looking up your timezone…", "Automatic timezone on", () => Date.timeZoneUpdated());
        };
        if (status && status.timezoneAllowed)
            lookUp();
        else
            run(["allow-timezone"], "Waiting for permission…", "", lookUp);
    }

    function applyLocale() {
        const args = Logic.localeArgs(localeDraft);
        if (args.length === 0)
            return;
        run(["set-locale"].concat(args), "Waiting for permission…", "Saved: log out and back in to see it everywhere", null);
    }

    function addLocale(name) {
        run(["add-locale", name], "Installing " + name + "…", "Installed " + name, () => {
            localesProc.running = false;
            localesProc.running = true;
        });
    }

    function setClock(key, value) {
        if (value && value !== clockSettings[key])
            StatusbarState.persistValue("clock", key, value);
    }

    function fillNow() {
        dateField.text = Logic.dateInput(clock.date);
        timeField.text = Logic.timeInput(clock.date);
    }

    // Example text for a date pattern, the way the shell shows it.
    function example(fmt) {
        return Qt.formatDateTime(clock.date, fmt);
    }

    // A locale's formats as text: date, number and money.
    function localeExample(name) {
        if (!name)
            return "";
        const loc = Qt.locale(Logic.qtLocaleName(name));
        return clock.date.toLocaleDateString(loc, Locale.ShortFormat) + "  ·  "
            + Number(1234567.89).toLocaleString(loc, "f", 2) + "  ·  "
            + Number(1234.5).toLocaleCurrencyString(loc);
    }

    function localeIndex(name) {
        return installedLocales.findIndex(l => l.name === name);
    }

    onIsOpenChanged: {
        if (!isOpen)
            return;
        tab = 0;
        setMessage("", "normal");
        refreshStatus();
        if (timezones.length === 0)
            timezonesProc.running = true;
        if (locales.length === 0)
            localesProc.running = true;
        fillNow();
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process {
        id: statusProc
        command: [Paths.timeScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const first = root.status === null;
                try {
                    root.status = JSON.parse(this.text);
                } catch (e) {
                    root.status = null;
                    return;
                }
                if (first || !root.localeDirty)
                    root.localeDraft = Logic.tidy(root.status.locale);
            }
        }
    }

    Process {
        id: timezonesProc
        command: [Paths.timeScript, "timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.timezones = Logic.timezoneItems(this.text)
        }
    }

    Process {
        id: localesProc
        command: [Paths.timeScript, "locales"]
        stdout: StdioCollector {
            onStreamFinished: root.locales = Logic.parseLocales(this.text)
        }
    }

    Process {
        id: actionProc
        property string okText: ""
        property var then: null
        stderr: StdioCollector { id: actionErr }
        onExited: code => {
            root.busy = false;
            if (code === 0) {
                if (okText !== "")
                    root.setMessage(okText, "good");
                const next = then;
                then = null;
                if (next)
                    next();
            } else {
                const msg = actionErr.text.replace(/\x1b\[[0-9;]*m/g, "").replace(/\[ERROR\]\s*/g, "").trim().split("\n").pop();
                root.setMessage(code === 2 ? "Not allowed (password prompt dismissed?)"
                    : (msg !== "" ? msg : "Failed (exit " + code + ")"), "error");
            }
            root.refreshStatus();
        }
    }

    FileView {
        id: timeSettings
        path: Paths.timeSettings
        blockWrites: true
        printErrors: false
    }

    component Caption: Text {
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    // A date pattern: presets (shown as examples) plus the pattern itself.
    component DatePattern: SettingRow {
        id: pattern
        property string key: ""
        property var presets: []
        readonly property string value: root.clockSettings[key] || ""

        FieldCombo {
            Layout.preferredWidth: 220
            model: pattern.presets.map(p => root.example(p))
            boundIndex: pattern.presets.indexOf(pattern.value)
            displayText: currentIndex < 0 ? "Custom" : currentText
            onActivated: index => root.setClock(pattern.key, pattern.presets[index])
        }
        FieldInput {
            Layout.preferredWidth: 170
            text: pattern.value
            onEditingFinished: {
                root.setClock(pattern.key, text.trim());
                text = Qt.binding(() => pattern.value);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        AppHeader {
            glyph: String.fromCodePoint(0xF0954)   // clock-outline
            title: "Date & time"
            subtitle: "Clock, timezone, formats and language"

            StatusChip {
                visible: root.message !== ""
                text: root.message
                tone: root.messageTone
            }
        }

        TabPills {
            model: root.tabs
            currentIndex: root.tab
            onActivated: index => root.tab = index
        }

        // --- DATE & TIME ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === 0
            spacing: 12

            Card {
                Layout.fillWidth: true
                implicitHeight: now.implicitHeight + 28

                ColumnLayout {
                    id: now
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 2

                    Text {
                        text: Qt.formatDateTime(clock.date, Logic.timeFormat(root.timeParts.h24, true))
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        font.bold: true
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, root.clockSettings.longDateFormat)
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }
                    Caption {
                        text: root.status ? root.status.timezone.replace(/_/g, " ")
                            + "  ·  " + Logic.formatOffset(Logic.offsetOf(clock.date)) : ""
                        visible: text !== ""
                    }
                }
            }

            SettingRow {
                label: "Set time automatically"
                hint: !root.status ? "" : root.status.ntp
                    ? (root.status.synced ? "Synchronized with network time" : "Not synchronized yet")
                    : "Set the date and time by hand below"
                ToggleSwitch {
                    enabled: root.status !== null && !root.busy
                    checked: root.status ? root.status.ntp : false
                    onToggled: {
                        root.setNtp(checked);
                        checked = Qt.binding(() => root.status ? root.status.ntp : false);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.status !== null && !root.status.ntp
                spacing: 10

                Caption { text: "Date"; Layout.fillWidth: false }
                FieldInput {
                    id: dateField
                    Layout.preferredWidth: 130
                    horizontalAlignment: Text.AlignHCenter
                    placeholderText: "YYYY-MM-DD"
                    onAccepted: root.setTime()
                }
                Caption { text: "Time"; Layout.fillWidth: false }
                FieldInput {
                    id: timeField
                    Layout.preferredWidth: 110
                    horizontalAlignment: Text.AlignHCenter
                    placeholderText: "HH:MM:SS"
                    onAccepted: root.setTime()
                }
                Item { Layout.fillWidth: true }
                PanelButton {
                    text: "Now"
                    compact: true
                    onClicked: root.fillNow()
                }
                PanelButton {
                    text: "Set"
                    compact: true
                    filled: true
                    enabled: !root.busy
                    onClicked: root.setTime()
                }
            }

            SettingRow {
                label: "Set timezone automatically"
                hint: "Looks up where you are from your IP address when the network connects. The first time asks for your password, so later changes don't."
                ToggleSwitch {
                    enabled: root.status !== null && !root.busy
                    checked: root.status ? root.status.autoTimezone : false
                    onToggled: {
                        root.setAutoTimezone(checked);
                        checked = Qt.binding(() => root.status ? root.status.autoTimezone : false);
                    }
                }
            }

            PickerList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                enabled: root.status !== null && !root.status.autoTimezone && !root.busy
                model: root.timezones
                currentKey: root.status ? root.status.timezone : ""
                placeholderText: "Search timezones (city or region)"
                emptyText: root.timezones.length === 0 ? "Loading timezones…" : "No timezone matches"
                onPicked: key => root.setTimezone(key)
            }
        }

        // --- CLOCK FORMAT ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === 1
            spacing: 12

            Card {
                Layout.fillWidth: true
                implicitHeight: preview.implicitHeight + 28

                GridLayout {
                    id: preview
                    anchors.fill: parent
                    anchors.margins: 14
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 6

                    Caption { text: "Status bar"; Layout.fillWidth: false }
                    Text {
                        Layout.fillWidth: true
                        text: root.example(root.clockSettings.format) + "   " + root.example(root.clockSettings.dateFormat)
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Caption { text: "Dashboard"; Layout.fillWidth: false }
                    Text {
                        Layout.fillWidth: true
                        text: root.example(Logic.withoutSeconds(root.clockSettings.format)) + "   " + root.example(root.clockSettings.longDateFormat)
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }
                    Caption { text: "Lock screen"; Layout.fillWidth: false }
                    Text {
                        Layout.fillWidth: true
                        // shroomery/scripts/lock-clock.sh: hours and minutes, AM/PM in English.
                        text: Qt.formatDateTime(clock.date, root.timeParts.h24 ? "HH:mm" : "h:mm")
                            + (root.timeParts.h24 ? "" : (clock.date.getHours() < 12 ? " AM" : " PM"))
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }
                    Caption { text: "Notifications"; Layout.fillWidth: false }
                    Text {
                        Layout.fillWidth: true
                        text: root.example("ddd " + Logic.withoutSeconds(root.clockSettings.format))
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }
                }
            }

            SettingRow {
                label: "24-hour clock"
                hint: "Status bar, dashboard, notifications and the lock screen"
                ToggleSwitch {
                    checked: root.timeParts.h24
                    onToggled: {
                        root.setClock("format", Logic.timeFormat(checked, root.timeParts.seconds));
                        checked = Qt.binding(() => root.timeParts.h24);
                    }
                }
            }

            SettingRow {
                label: "Show seconds"
                hint: "In the status bar"
                ToggleSwitch {
                    checked: root.timeParts.seconds
                    onToggled: {
                        root.setClock("format", Logic.timeFormat(root.timeParts.h24, checked));
                        checked = Qt.binding(() => root.timeParts.seconds);
                    }
                }
            }

            DatePattern {
                label: "Status bar date"
                hint: "Pick an example or type a pattern"
                key: "dateFormat"
                presets: Logic.SHORT_DATE_PRESETS
            }

            DatePattern {
                label: "Dashboard date"
                key: "longDateFormat"
                presets: Logic.LONG_DATE_PRESETS
            }

            Item { Layout.fillHeight: true }

            Caption {
                text: "Pattern letters: d 7 · dd 07 · ddd Sat · dddd Saturday · M 11 · MM 11 · MMM Nov · MMMM November · yy 26 · yyyy 2026. Anything in 'quotes' is shown as typed. Day and month names follow the Dates and times format of Language & region."
            }
        }

        // --- LANGUAGE & REGION ---
        ScrollView {
            id: regionScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === 2
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: regionScroll.availableWidth
                spacing: 12

                Caption {
                    text: "For the whole system: other apps use these after you log out and back in. Saving asks for your password."
                }

                SettingRow {
                    label: "Display language"
                    hint: "Menus and messages in apps"
                    FieldCombo {
                        Layout.preferredWidth: 300
                        model: root.installedLocales.map(l => l.label)
                        boundIndex: root.localeIndex(root.localeDraft.LANG || "")
                        onActivated: index => root.localeDraft = Logic.setLanguage(root.localeDraft, root.installedLocales[index].name)
                    }
                }

                SettingRow {
                    label: "Formats"
                    hint: {
                        const v = Logic.formatsValue(root.localeDraft);
                        return v !== "" ? root.localeExample(v) : "Mixed: see Per category";
                    }
                    FieldCombo {
                        Layout.preferredWidth: 300
                        model: root.installedLocales.map(l => l.label)
                        boundIndex: root.localeIndex(Logic.formatsValue(root.localeDraft))
                        displayText: currentIndex < 0 ? "Mixed" : currentText
                        onActivated: index => root.localeDraft = Logic.setFormats(root.localeDraft, root.installedLocales[index].name)
                    }
                }

                SectionHeader {
                    id: perCategory
                    label: "Per category"
                    collapsible: true
                    expanded: false
                }

                Repeater {
                    model: perCategory.expanded ? Logic.CATEGORIES : []
                    delegate: SettingRow {
                        id: category
                        required property var modelData
                        label: modelData.label
                        hint: modelData.name
                        FieldCombo {
                            Layout.preferredWidth: 300
                            compact: true
                            model: ["Same as display language"].concat(root.installedLocales.map(l => l.label))
                            boundIndex: root.localeDraft[category.modelData.name]
                                ? root.localeIndex(root.localeDraft[category.modelData.name]) + 1 : 0
                            onActivated: index => root.localeDraft = Logic.setCategory(root.localeDraft, category.modelData.name,
                                index === 0 ? "" : root.installedLocales[index - 1].name)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    PanelButton {
                        text: "Revert"
                        enabled: root.localeDirty && !root.busy
                        onClicked: root.localeDraft = Logic.tidy(root.systemLocale)
                    }
                    PanelButton {
                        text: "Save"
                        glyph: String.fromCodePoint(0xF012C)   // check
                        filled: true
                        enabled: root.localeDirty && !root.busy
                        onClicked: root.applyLocale()
                    }
                }

                SectionHeader {
                    id: addHeader
                    label: "Install another language"
                    collapsible: true
                    expanded: false
                }

                Caption {
                    visible: addHeader.expanded
                    text: "Only installed languages can be picked above. Click one to install it (asks for your password, takes a moment)."
                }

                PickerList {
                    visible: addHeader.expanded
                    Layout.fillWidth: true
                    Layout.preferredHeight: 240
                    enabled: !root.busy
                    model: root.otherLocales
                    placeholderText: "Search languages and countries"
                    emptyText: root.locales.length === 0 ? "Loading…" : "Nothing matches"
                    onPicked: key => root.addLocale(key)
                }
            }
        }
    }
}
