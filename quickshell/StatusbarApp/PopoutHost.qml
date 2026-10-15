import QtQuick
import qs.shared
import qs.shared.ui
import "BarGeometry.js" as Geo

// The part of one bar that grows out of the pill's bottom edge into the open
// popout panel (PopoutState) and morphs between panels. It animates the panel
// rect that BarShape draws and shows the panels' contents in it; each panel
// is loaded the first time it opens on this monitor and kept (instant
// reopen). Opening grows the height out of the pill; switching panels
// retargets x, width and height mid-flight and cross-fades the contents;
// closing shrinks the height back into the pill.
//
// Place it at the pill's bottom edge (y), full window width.
Item {
    id: host

    required property string screenName
    // panel name -> Component of a PopoutPanel (from shell.qml)
    required property var panels
    // The pill the panel hangs from.
    required property Item pill
    property int borderWidth: 2
    // Pull to a pill edge when the panel lands this close to it.
    property real snap: 24
    // Tallest the panel rect may get (border included).
    property real maxHeight: 600

    readonly property bool open: PopoutState.currentName !== ""
        && PopoutState.currentScreen === host.screenName
        && host.panels[PopoutState.currentName] !== undefined
    readonly property string currentName: open ? PopoutState.currentName : ""

    // The open panel's content item, once loaded.
    readonly property Item currentItem: {
        for (let i = 0; i < slots.count; i++) {
            const slot = slots.itemAt(i);
            if (slot && slot.current && slot.item)
                return slot.item;
        }
        return null;
    }
    readonly property bool hovered: panelHover.hovered
    readonly property bool holdOpen: currentItem !== null && currentItem.holdOpen === true
    // For the window's input mask.
    readonly property Item inputItem: panelRect

    // Where the open panel wants to be (outer rect, border included).
    readonly property real targetW: currentItem ? currentItem.implicitWidth + 2 * borderWidth : 0
    readonly property real targetH: currentItem ? Math.min(maxHeight, currentItem.implicitHeight + borderWidth) : 0
    // Under the button it opened from; without one (IPC), under the pill's
    // right third, where the panel buttons live.
    readonly property real anchorCenterX: {
        const px = pill.x;
        const pw = pill.width;
        const a = PopoutState.anchorItem;
        if (host.open && a) {
            try {
                return a.mapToItem(host, a.width / 2, 0).x;
            } catch (e) {}
        }
        return px + pw * 5 / 6;
    }
    readonly property real targetX: Geo.panelX(anchorCenterX, targetW, pill.x, pill.width, snap)

    // The animated panel rect, in this item's coordinates (top = pill bottom).
    // x and width hold while it closes.
    property real panelX: 0
    property real panelW: 0
    property real panelH: 0

    readonly property var spatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    readonly property var accelerate: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]

    function retarget(): void {
        if (!host.open || host.targetW <= 0) {
            host.panelH = 0;
            return;
        }
        // From closed, x and width jump (their Behaviors are off at height 0)
        // and only the height grows out of the pill.
        host.panelX = host.targetX;
        host.panelW = host.targetW;
        host.panelH = host.targetH;
    }

    onOpenChanged: retarget()
    // Monitor unplugged: don't leave PopoutState pointing at a gone screen.
    Component.onDestruction: PopoutState.forgetScreen(host.screenName)
    onTargetXChanged: retarget()
    onTargetWChanged: retarget()
    onTargetHChanged: retarget()

    Behavior on panelX {
        enabled: host.panelH > 0.5
        NumberAnimation {
            duration: 450
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.spatial
        }
    }

    Behavior on panelW {
        enabled: host.panelH > 0.5
        NumberAnimation {
            duration: 450
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.spatial
        }
    }

    Behavior on panelH {
        NumberAnimation {
            duration: host.open ? 450 : 280
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.open ? host.spatial : host.accelerate
        }
    }

    Item {
        id: panelRect
        x: host.panelX
        width: host.panelW
        height: host.panelH

        HoverHandler {
            id: panelHover
        }

        // The panel inside its border; clips the contents.
        Item {
            id: clipRect
            anchors.fill: parent
            anchors.leftMargin: host.borderWidth
            anchors.rightMargin: host.borderWidth
            anchors.bottomMargin: host.borderWidth
            clip: true

            Repeater {
                id: slots
                model: Object.keys(host.panels)

                delegate: Loader {
                    id: slot
                    required property string modelData
                    readonly property bool current: host.currentName === modelData

                    // Loaded on first open, then kept.
                    active: false
                    onCurrentChanged: if (current) active = true
                    Component.onCompleted: if (current) active = true
                    sourceComponent: host.panels[modelData]

                    // At the panel's own size, centered and top-aligned: the
                    // growing / morphing rect reveals it.
                    width: item ? item.implicitWidth : 0
                    height: item ? Math.min(host.maxHeight - host.borderWidth, item.implicitHeight) : 0
                    x: Math.round((clipRect.width - width) / 2)

                    opacity: current ? 1 : 0
                    visible: opacity > 0
                    enabled: current
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: slot.current ? 80 : 0 }
                            NumberAnimation {
                                duration: slot.current ? 200 : 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // Keeps the last button while it fades out after a switch. Declared
                    // before `active` so a panel sees its button when it activates.
                    Binding {
                        when: slot.item !== null && slot.current
                        target: slot.item
                        property: "anchorItem"
                        value: PopoutState.anchorItem
                        restoreMode: Binding.RestoreNone
                    }
                    Binding {
                        when: slot.item !== null
                        target: slot.item
                        property: "active"
                        value: slot.current
                    }
                    Binding {
                        when: slot.item !== null
                        target: slot.item
                        property: "maxHeight"
                        value: host.maxHeight - host.borderWidth
                    }

                    Connections {
                        target: slot.item
                        ignoreUnknownSignals: true
                        // Deferred: a panel may ask while PopoutState is still
                        // notifying the change that activated it.
                        function onCloseRequested() {
                            Qt.callLater(() => {
                                if (slot.current)
                                    PopoutState.close();
                            });
                        }
                    }
                }
            }
        }

        // A press inside an unpinned panel pins it; the press itself still
        // reaches the content below.
        MouseArea {
            anchors.fill: parent
            enabled: host.open && !PopoutState.pinned
            onPressed: mouse => {
                PopoutState.press();
                mouse.accepted = false;
            }
        }
    }
}
