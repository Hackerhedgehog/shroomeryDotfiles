import QtQuick
import qs.shared
// Round workspace marker with the workspace number in the middle: the status
// bar's workspace buttons and the workspace column of WindowList. Filled for the
// active workspace, outlined otherwise.
Rectangle {
    id: badge

    property string label: ""
    // The active workspace: a filled circle.
    property bool filled: false
    // Outline width when not filled (the status bar thickens it for a workspace
    // active on another monitor).
    property real outlineWidth: 1
    // Background tint for an unfilled, hovered badge.
    property bool hovered: false
    // Drawn on an accent-colored background (a hovered menu row): swap the
    // accent and background colors so it stays visible.
    property bool inverted: false

    readonly property color accent: badge.inverted ? Theme.background : Theme.primary

    implicitWidth: 26
    implicitHeight: 26
    radius: 13

    color: badge.filled
        ? badge.accent
        : (badge.hovered ? Theme.surface_container_high : "transparent")
    border.color: badge.accent
    border.width: badge.filled ? 0 : badge.outlineWidth

    // Crossfade the fill between active / hover / inactive states so the
    // background of the active circle fades in and the previous one out.
    Behavior on color {
        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
    }
    // Fade the outline in/out as the fill takes over on activation.
    Behavior on border.width {
        NumberAnimation { duration: 500; easing.type: Easing.OutQuint }
    }

    Text {
        anchors.centerIn: parent
        text: badge.label
        color: badge.filled
            ? (badge.inverted ? Theme.primary : Theme.background)
            : (badge.inverted ? Theme.background : Theme.on_background)
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true

        // Match the fill crossfade so the label recolors in step.
        Behavior on color {
            ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
        }
    }
}
