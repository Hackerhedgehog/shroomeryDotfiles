import QtQuick
import QtQuick.Effects
import qs.shared

// The card every panel draws its content on: drop shadow, 2px primary →
// on_primary gradient border, background fill. Children are drawn on top;
// panels put a ColumnLayout in it with anchors.fill: parent and
// anchors.margins: 18.
Item {
    id: surface

    property int radius: 10

    anchors.fill: parent
    anchors.margins: 16

    RectangularShadow {
        anchors.fill: frame
        radius: frame.radius
        blur: 15
        color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: surface.radius
        opacity: 0.96
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.primary }
            GradientStop { position: 1.0; color: Theme.on_primary }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: parent.radius - anchors.margins
            color: Theme.background
        }
    }
}
