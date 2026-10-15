pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "NightLightLogic.js" as Logic

// Night light: settings in shroomery/settings/night-light.json
// (Paths.nightLightSettings), applied and scheduled by
// shroomery/scripts/hyprsunset.sh and listeners/night-light.sh. The panel
// only writes the settings and calls the script; it never starts
// hyprsunset itself.
Singleton {
    id: root

    property string mode: Logic.DEFAULTS.mode
    property string onTime: Logic.DEFAULTS.on
    property string offTime: Logic.DEFAULTS.off
    property int temperature: Logic.DEFAULTS.temperature
    property int gamma: Logic.DEFAULTS.gamma

    // Whether hyprsunset runs; polled while the settings panel is open.
    property bool running: false
    // Today's sun times ("HH:MM"), "" while unknown.
    property string sunrise: ""
    property string sunset: ""

    readonly property bool panelOpen: SettingsState.panelOpen

    function apply(raw: string): void {
        let parsed = {};
        try {
            parsed = JSON.parse(raw) || {};
        } catch (e) {
            console.warn("night-light.json: " + e);
        }
        const s = Logic.normalize(parsed);
        mode = s.mode;
        onTime = s.on;
        offTime = s.off;
        temperature = s.temperature;
        gamma = s.gamma;
    }

    function save(): void {
        settingsFile.setText(JSON.stringify({
            "mode": mode, "on": onTime, "off": offTime,
            "temperature": temperature, "gamma": gamma
        }, null, 4) + "\n");
    }

    function setMode(m: string): void {
        if (Logic.MODES.indexOf(m) < 0 || m === mode)
            return;
        mode = m;
        save();
        sync();
        if (m === "sun")
            refreshSunTimes();
    }

    // Invalid text is ignored; the field re-binds and shows the old value.
    function setOnTime(t: string): void {
        const m = Logic.parseTime(t);
        if (m < 0)
            return;
        onTime = Logic.formatTime(m);
        save();
        sync();
    }

    function setOffTime(t: string): void {
        const m = Logic.parseTime(t);
        if (m < 0)
            return;
        offTime = Logic.formatTime(m);
        save();
        sync();
    }

    function setTemperature(v: real): void {
        temperature = Logic.clampInt(v, Logic.TEMPERATURE.min, Logic.TEMPERATURE.max, temperature);
        save();
        applyDebounce.restart();
    }

    function setGamma(v: real): void {
        gamma = Logic.clampInt(v, Logic.GAMMA.min, Logic.GAMMA.max, gamma);
        save();
        applyDebounce.restart();
    }

    function toggle(): void {
        Quickshell.execDetached([Paths.hyprsunset, "toggle"]);
        running = !running;
        statusSettle.restart();
    }

    function sync(): void {
        Quickshell.execDetached([Paths.hyprsunset, "sync"]);
        statusSettle.restart();
    }

    function refreshStatus(): void {
        statusReader.running = false;
        statusReader.running = true;
    }

    function refreshSunTimes(): void {
        sunReader.running = false;
        sunReader.running = true;
    }

    onPanelOpenChanged: if (panelOpen && mode === "sun") refreshSunTimes()

    // One hyprsunset.sh apply per pause in a slider drag, not one per step.
    Timer {
        id: applyDebounce
        interval: 150
        onTriggered: Quickshell.execDetached([Paths.hyprsunset, "apply"])
    }

    // Re-read the real state once the script has had time to act.
    Timer {
        id: statusSettle
        interval: 300
        onTriggered: root.refreshStatus()
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.panelOpen
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: statusReader
        command: [Paths.hyprsunset, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.running = this.text.trim() === "on"
        }
    }

    Process {
        id: sunReader
        command: [Paths.hyprsunset, "sun-times"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = Logic.parseSunTimes(this.text);
                root.sunrise = t ? t.sunrise : "";
                root.sunset = t ? t.sunset : "";
            }
        }
    }

    FileView {
        id: settingsFile
        path: Paths.nightLightSettings
        blockLoading: true
        // The script reads the file right after a save (sync).
        blockWrites: true
        printErrors: false
        watchChanges: true
        onLoaded: root.apply(text())
        onFileChanged: reload()
    }
}
