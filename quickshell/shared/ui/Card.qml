import QtQuick
import qs.shared

// A card: rounded surface for one block of content (the dashboard tiles,
// the settings column of a centered app).
Rectangle {
    radius: 14
    color: Theme.surface_container
    border.color: Theme.outline_variant
    border.width: 1
}
