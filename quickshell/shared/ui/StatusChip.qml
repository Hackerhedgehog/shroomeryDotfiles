import QtQuick
import qs.shared

// A small status pill: a dot and a short text. `tone` picks the colors:
// "normal", "good" (primary), "busy" (tertiary) or "error".
Rectangle {
    id: chip

    property string text: ""
    property string tone: "normal"

    readonly property color foreground: tone === "error" ? Theme.on_error_container
        : tone === "busy" ? Theme.on_tertiary_container
        : tone === "good" ? Theme.on_primary_container
        : Theme.on_surface_variant

    implicitHeight: 28
    implicitWidth: label.implicitWidth + 34
    radius: 14
    color: tone === "error" ? Theme.error_container
        : tone === "busy" ? Theme.tertiary_container
        : tone === "good" ? Theme.primary_container
        : Theme.surface_container_high
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: chip.foreground
    }

    Text {
        id: label
        x: 24
        anchors.verticalCenter: parent.verticalCenter
        text: chip.text
        color: chip.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
    }
}
