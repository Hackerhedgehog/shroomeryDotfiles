pragma Singleton

import Quickshell
import QtQuick
import qs.shared

// The dashboard's spectrum ring around the cover art (RoundArt): one shared
// 24-bar cava, running only while something shows the ring (`consumers` > 0).
Singleton {
    id: root

    property int consumers: 0
    readonly property var bars: spectrum.bars

    CavaSpectrum {
        id: spectrum
        barCount: 24
        framerate: 30
        active: root.consumers > 0
    }
}
