import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.MonitorApp

Item {
    id: canvas
    clip: true

    // The Repeater is keyed on monitor names, not on the draft array itself.
    // Rebuilding the model would destroy the delegate that currently holds the
    // mouse grab, which is what used to make a drag die on its first move.
    property var names: []

    property bool dragging: false
    property string dragName: ""
    property real frozenScale: 1
    property real frozenOx: 0
    property real frozenOy: 0
    property real pressCanvasX: 0
    property real pressCanvasY: 0
    property real startMonX: 0
    property real startMonY: 0
    // Live drag position in monitor coordinates. Kept local: MonitorState is
    // only written once, on release.
    property real dragMonX: 0
    property real dragMonY: 0

    // Disabled outputs have no geometry to draw; they live in the panel's
    // "Disabled displays" list instead.
    readonly property var monitors: MonitorState.enabledMonitors
    readonly property real pad: 32

    function syncNames() {
        const list = MonitorState.enabledMonitors;
        const next = [];
        for (let i = 0; i < list.length; i++)
            next.push(list[i].name);
        if (next.join("") !== names.join(""))
            names = next;
    }

    Component.onCompleted: syncNames()

    Connections {
        target: MonitorState
        function onDraftChanged() {
            canvas.syncNames();
        }
    }

    readonly property var bounds: {
        const list = monitors;
        if (!list || list.length === 0)
            return ({
                    minX: 0,
                    minY: 0,
                    maxX: 1,
                    maxY: 1
                });
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < list.length; i++) {
            const m = list[i];
            minX = Math.min(minX, m.x);
            minY = Math.min(minY, m.y);
            maxX = Math.max(maxX, m.x + MonitorState.layoutWidth(m));
            maxY = Math.max(maxY, m.y + MonitorState.layoutHeight(m));
        }
        if (!isFinite(minX))
            return ({
                    minX: 0,
                    minY: 0,
                    maxX: 1,
                    maxY: 1
                });
        return ({
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY
            });
    }

    readonly property real computedScale: {
        const b = bounds;
        const availW = Math.max(1, width - pad * 2);
        const availH = Math.max(1, height - pad * 2);
        const bw = Math.max(1, b.maxX - b.minX);
        const bh = Math.max(1, b.maxY - b.minY);
        return Math.min(availW / bw, availH / bh);
    }

    // Plain properties rather than readonly ones so the Behaviors below can
    // ease the view between layouts instead of snapping it after every apply.
    property real viewScale: dragging ? frozenScale : computedScale

    property real originX: {
        if (dragging)
            return frozenOx;
        const b = bounds;
        const usedW = (b.maxX - b.minX) * computedScale;
        return (width - usedW) / 2 - b.minX * computedScale;
    }

    property real originY: {
        if (dragging)
            return frozenOy;
        const b = bounds;
        const usedH = (b.maxY - b.minY) * computedScale;
        return (height - usedH) / 2 - b.minY * computedScale;
    }

    Behavior on viewScale {
        enabled: !canvas.dragging
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
    Behavior on originX {
        enabled: !canvas.dragging
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
    Behavior on originY {
        enabled: !canvas.dragging
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    function toCanvasX(x) {
        return originX + x * viewScale;
    }
    function toCanvasY(y) {
        return originY + y * viewScale;
    }

    function freezeView() {
        frozenScale = viewScale;
        frozenOx = originX;
        frozenOy = originY;
    }

    function moveDrag(canvasX, canvasY) {
        const s = viewScale > 0 ? viewScale : 1;
        dragMonX = startMonX + (canvasX - pressCanvasX) / s;
        dragMonY = startMonY + (canvasY - pressCanvasY) / s;
    }

    function endDrag() {
        if (!dragging)
            return;
        const name = dragName;
        // Weld first, then leave drag mode: the tile is still drawn at the drop
        // point while the new position lands, so releasing animates from where
        // the cursor let go to the welded spot instead of flicking back to the
        // pre-drag position for a frame.
        if (name !== "")
            MonitorState.dropMonitor(name, dragMonX, dragMonY);
        dragging = false;
        dragName = "";
    }

    Card {
        anchors.fill: parent
    }

    Text {
        anchors.centerIn: parent
        visible: canvas.names.length === 0
        text: MonitorState.initialized ? "No displays detected" : "Asking Hyprland…"
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }

    Repeater {
        model: canvas.names

        delegate: Rectangle {
            id: tile
            required property string modelData

            readonly property var mon: MonitorState.monitorNamed(modelData)
            readonly property bool beingDragged: canvas.dragging && canvas.dragName === modelData
            readonly property int layoutW: mon ? MonitorState.layoutWidth(mon) : 1
            readonly property int layoutH: mon ? MonitorState.layoutHeight(mon) : 1
            readonly property bool selected: !MonitorState.defaultRuleSelected && MonitorState.selectedName === modelData

            visible: mon !== null
            x: canvas.toCanvasX(beingDragged ? canvas.dragMonX : (mon ? mon.x : 0))
            y: canvas.toCanvasY(beingDragged ? canvas.dragMonY : (mon ? mon.y : 0))
            // No minimum size: the drawn rectangle has to be exactly the
            // logical rectangle, otherwise a placement that looks flush is not.
            width: Math.max(1, layoutW * canvas.viewScale)
            height: Math.max(1, layoutH * canvas.viewScale)
            z: beingDragged ? 2 : (selected ? 1 : 0)
            radius: 10
            color: (mon && mon.disabled) ? Qt.rgba(Theme.surface_container_highest.r, Theme.surface_container_highest.g, Theme.surface_container_highest.b, 0.55) : selected ? Theme.primary_container : (tileHover.hovered ? Theme.surface_bright : Theme.surface_container_highest)
            border.color: selected ? Theme.primary : "transparent"
            border.width: 2
            Behavior on color { ColorAnimation { duration: 150 } }
            opacity: (mon && mon.disabled) ? 0.7 : 1
            clip: true

            // Eases the weld on release, and keeps the tiles from teleporting
            // when a new layout comes back from Hyprland.
            Behavior on x {
                enabled: !tile.beingDragged
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                enabled: !tile.beingDragged
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            HoverHandler {
                id: tileHover
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: tile.modelData
                        color: tile.selected ? Theme.on_primary_container : Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    // Marks the primary output. Dimmed while the pick is still
                    // staged, so a star that has not been applied yet does not
                    // read as fact.
                    Text {
                        visible: MonitorState.draftPrimary === tile.modelData
                        opacity: MonitorState.primaryName === tile.modelData ? 1 : 0.5
                        text: String.fromCodePoint(0xF04CE)   // star
                        color: tile.selected ? Theme.on_primary_container : Theme.primary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: !tile.mon ? "" : tile.mon.disabled ? "Disabled" : (tile.layoutW + "×" + tile.layoutH)
                    color: tile.selected ? Theme.on_primary_container : Theme.on_surface_variant
                    opacity: 0.85
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                onPressed: mouse => {
                    if (!tile.mon)
                        return;
                    MonitorState.select(tile.modelData);
                    canvas.freezeView();
                    // Capture the grab offset and seed the drag position BEFORE
                    // switching the tile over to drag mode. Doing it the other
                    // way round rebinds x to a stale dragMonX for one frame, and
                    // the tile is measured after it has already jumped.
                    canvas.pressCanvasX = tile.x + mouse.x;
                    canvas.pressCanvasY = tile.y + mouse.y;
                    canvas.startMonX = tile.mon.x;
                    canvas.startMonY = tile.mon.y;
                    canvas.dragMonX = tile.mon.x;
                    canvas.dragMonY = tile.mon.y;
                    canvas.dragName = tile.modelData;
                    canvas.dragging = true;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !tile.beingDragged)
                        return;
                    canvas.moveDrag(tile.x + mouse.x, tile.y + mouse.y);
                }
                onReleased: canvas.endDrag()
                onCanceled: canvas.endDrag()
            }
        }
    }
}
