import QtQuick
import QtQuick.Controls
import qs.shared

// Themed ComboBox over a list of strings.
//
// ComboBox resets currentIndex to 0 whenever its model is replaced, and
// selecting an item writes currentIndex directly — both strand a plain
// `currentIndex:` binding. When the selection comes from state, set
// `boundIndex` instead; it is re-asserted after every reset.
ComboBox {
    id: combo

    property bool compact: false
    property var boundIndex: undefined

    function syncIndex() {
        if (boundIndex !== undefined && currentIndex !== boundIndex)
            currentIndex = boundIndex;
    }
    onBoundIndexChanged: syncIndex()
    onModelChanged: Qt.callLater(syncIndex)
    onCountChanged: Qt.callLater(syncIndex)
    Component.onCompleted: syncIndex()

    implicitHeight: compact ? 32 : 36
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    font.family: Theme.fontFamily
    font.pixelSize: compact ? 12 : 13
    background: Rectangle {
        implicitHeight: combo.implicitHeight
        radius: 10
        color: combo.hovered || combo.popup.visible ? Theme.surface_container_highest : Theme.surface_container_high
        border.color: combo.popup.visible || combo.visualFocus ? Theme.primary : "transparent"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: Text {
        leftPadding: 12
        rightPadding: 30
        text: combo.displayText
        font: combo.font
        color: Theme.on_surface
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint(0xF0140)   // chevron-down
        color: Theme.on_surface_variant
        font.family: Theme.iconFontFamily
        font.pixelSize: 16
        rotation: combo.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 150 } }
    }
    delegate: ItemDelegate {
        id: entry
        required property var modelData
        required property int index
        readonly property bool current: combo.currentIndex === index
        width: combo.width - 12
        implicitHeight: combo.compact ? 32 : 34
        highlighted: combo.highlightedIndex === index
        contentItem: Text {
            text: entry.modelData
            font.family: Theme.fontFamily
            font.pixelSize: combo.font.pixelSize
            font.bold: entry.current
            color: entry.highlighted ? Theme.on_primary_container : Theme.on_surface
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            leftPadding: 6
        }
        background: Rectangle {
            color: entry.highlighted ? Theme.primary_container : "transparent"
            radius: 8
        }
    }
    popup: Popup {
        y: combo.height + 6
        width: combo.width
        padding: 6
        background: Rectangle {
            color: Theme.surface_container
            border.color: Theme.outline_variant
            border.width: 1
            radius: 12
        }
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 240)
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }
    }
}
