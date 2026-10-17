pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.shared
import "WeatherData.js" as W

// Weather for the dashboard from wttr.in (JSON, no API key, metric). The
// location comes from shroomery/settings/weather-location (empty or missing
// = wttr.in's guess from the IP address). The last answer is cached in
// ~/.cache/shroomery/weather.json and fetched again only when the dashboard
// opens and it is over 30 minutes old (or the location changed).
Singleton {
    id: root

    readonly property int maxAgeMs: 30 * 60 * 1000
    property string location: ""
    // WeatherData.normalize() result, or null.
    property var current: null
    property double fetchedAt: 0
    property bool loading: false
    // "" or a short message; with `current` still set the data is stale.
    property string error: ""
    readonly property bool stale: error !== "" && current !== null

    function minutesNow(): int {
        const d = new Date();
        return d.getHours() * 60 + d.getMinutes();
    }

    function isNightNow(): bool {
        return current ? W.isNight(minutesNow(), current.sunrise, current.sunset) : false;
    }

    function glyph(code: int): string {
        return W.glyph(code, isNightNow());
    }

    // The singleton is created when the dashboard first opens, and both files
    // load asynchronously: decide about fetching only once both are read.
    property bool _locationDone: false
    property bool _cacheDone: false
    property var _cached: null
    property bool _refreshWanted: false

    function _settle(): void {
        if (!root._locationDone || !root._cacheDone)
            return;
        if (root._cached) {
            root.current = root._cached.data;
            root.fetchedAt = root._cached.location === root.location ? root._cached.fetchedAt : 0;
            root._cached = null;
        }
        if (root._refreshWanted) {
            root._refreshWanted = false;
            root.refreshIfStale();
        }
    }

    function refreshIfStale(): void {
        if (!root._locationDone || !root._cacheDone) {
            root._refreshWanted = true;
            return;
        }
        if (!root.loading && W.isStale(root.fetchedAt, Date.now(), root.maxAgeMs))
            root.fetch();
    }

    function fetch(): void {
        root.loading = true;
        root.error = "";
        fetcher.command = ["curl", "-sf", "--max-time", "10", W.url(root.location)];
        fetcher.running = true;
    }

    function ingest(text: string): void {
        root.loading = false;
        let j1 = null;
        try {
            j1 = JSON.parse(text);
        } catch (e) {}
        const data = W.normalize(j1);
        if (!data) {
            root.error = "Weather unavailable";
            return;
        }
        root.current = data;
        root.fetchedAt = Date.now();
        cacheFile.setText(JSON.stringify({ fetchedAt: root.fetchedAt, location: root.location, data: data }));
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Paths.cacheDir])

    Process {
        id: fetcher
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.error = "Weather unavailable";
            }
        }
    }

    FileView {
        id: locationFile
        path: Paths.weatherLocation
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const loc = text().trim();
            if (loc !== root.location) {
                root.location = loc;
                root.fetchedAt = 0;
            }
            root._locationDone = true;
            root._settle();
        }
        onLoadFailed: {
            root.location = "";
            root._locationDone = true;
            root._settle();
        }
    }

    FileView {
        id: cacheFile
        path: Paths.weatherCache
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c && c.data)
                    root._cached = c;
            } catch (e) {}
            root._cacheDone = true;
            root._settle();
        }
        onLoadFailed: {
            root._cacheDone = true;
            root._settle();
        }
    }
}
