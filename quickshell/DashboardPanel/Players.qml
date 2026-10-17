pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The MPRIS players for the dashboard and the one it shows: the one picked in
// the Media tab while it exists, else the first one playing, else the first.
Singleton {
    id: root

    readonly property var list: Mpris.players.values
    // Picked in the Media tab, or null to follow playback.
    property var chosen: null
    readonly property var current: {
        const l = root.list;
        if (root.chosen && l.indexOf(root.chosen) >= 0)
            return root.chosen;
        for (let i = 0; i < l.length; i++)
            if (l[i].isPlaying)
                return l[i];
        return l.length > 0 ? l[0] : null;
    }
}
