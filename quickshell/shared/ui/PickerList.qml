import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import qs.shared
import "PickerLogic.js" as Logic

// A searchable list to pick one item from many (keyboard layouts, timezones,
// locales): a SearchField over a list of rows, the current one filled.
// `model` is a list of { key, label, detail }; a click (or Return on the
// first result) emits picked(key). The owner sets `currentKey` back — the list
// never changes it itself.
//
//   PickerList {
//       model: [{ key: "ee", label: "Estonian", detail: "ee" }]
//       currentKey: state.layout
//       onPicked: key => state.setLayout(key)
//   }
ColumnLayout {
    id: root

    property var model: []
    property string currentKey: ""
    property string placeholderText: "Search"
    // Shown when nothing matches the search (or the model is empty).
    property string emptyText: "Nothing found"

    readonly property var filtered: Logic.filterItems(root.model, search.text)

    signal picked(string key)

    function clearSearch() {
        search.text = "";
    }

    // Scroll the current item into view (after the model arrives, on open).
    function showCurrent() {
        const i = Logic.indexOfKey(root.filtered, root.currentKey);
        if (i >= 0)
            list.positionViewAtIndex(i, ListView.Center);
    }

    onModelChanged: Qt.callLater(showCurrent)
    onVisibleChanged: if (visible) Qt.callLater(showCurrent)

    spacing: 8
    opacity: enabled ? 1 : 0.45

    SearchField {
        id: search
        Layout.fillWidth: true
        placeholderText: root.placeholderText
        onKeyPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.filtered.length > 0) {
                root.picked(root.filtered[0].key);
                event.accepted = true;
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Theme.surface_container_low
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 4
            model: root.filtered
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            QQC.ScrollBar.vertical: QQC.ScrollBar {}

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool current: modelData.key === root.currentKey

                width: ListView.view.width
                implicitHeight: 34
                radius: 10
                color: current ? Theme.primary_container
                    : (rowHover.hovered && root.enabled ? Theme.surface_container_high : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: row.current ? Theme.on_primary_container : Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: row.current
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: text !== ""
                        text: row.modelData.detail || ""
                        color: row.current ? Theme.on_primary_container : Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                HoverHandler {
                    id: rowHover
                    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                TapHandler {
                    enabled: root.enabled
                    onTapped: root.picked(row.modelData.key)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.filtered.length === 0
            text: root.emptyText
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }
}
