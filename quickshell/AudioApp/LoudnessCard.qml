// AudioApp/LoudnessCard.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.shared
import qs.shared.ui
import qs.AudioApp
import "Loudness.js" as Loudness

// Collapsible dynamic-loudness card for the Output tab. Presentation only:
// every mutation goes through LoudnessState.
Rectangle {
    id: card

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 20
    radius: 10
    color: Theme.surface_container_low
    border.color: Theme.outline_variant
    border.width: 1

    // Declared on the card itself: the header, every section and the tap
    // handler all read it, and a property on the inner layout would not be
    // reachable as `card.expanded`.
    property bool expanded: false

    Process {
        id: toneProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    function playTone(index) {
        // Restarting the process mid-tone cuts the previous one off and makes
        // the A/B comparison meaningless; let the current tone finish.
        if (toneProc.running)
            return;
        toneProc.command = [Qt.resolvedUrl("tones.sh").toString().replace("file://", ""), "play", String(index)];
        toneProc.running = true;
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // ------------------------------------------------------- header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                // Tapping the title area expands; the switch keeps its own
                // hit area because it is a sibling, not underneath this.
                TapHandler {
                    onTapped: {
                        card.expanded = !card.expanded;
                    }
                }

                Text {
                    text: "Dynamic Loudness"
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        if (!LoudnessState.available)
                            return "Install lsp-plugins-lv2 to enable dynamic loudness.";
                        const preset = Loudness.PRESET_LABELS[LoudnessState.preset];
                        if (!LoudnessState.enabled)
                            return preset + " · off";
                        return preset + " · " + (LoudnessState.targetSinkLabel || "no device");
                    }
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            Text {
                text: card.expanded ? "▾" : "▸"
                color: Theme.on_surface_variant
                font.pixelSize: 12
            }

            ToggleSwitch {
                checked: LoudnessState.enabled
                enabled: LoudnessState.available
                onToggled: LoudnessState.setEnabled(checked)
            }
        }

        // ------------------------------------------------------- presets
        Flow {
            Layout.fillWidth: true
            visible: card.expanded && LoudnessState.available
            spacing: 6

            Repeater {
                model: Loudness.PRESET_ORDER
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool current: LoudnessState.preset === modelData

                    implicitWidth: chipText.implicitWidth + 20
                    implicitHeight: 26
                    radius: 8
                    color: current ? Theme.primary_container : "transparent"
                    border.color: current ? "transparent" : Theme.outline_variant
                    border.width: 1

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: Loudness.PRESET_LABELS[parent.modelData]
                        color: parent.current ? Theme.on_primary_container : Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LoudnessState.applyPreset(parent.modelData)
                    }
                }
            }
        }

        // ---------------------------------------------------- parameters
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.expanded && LoudnessState.available
            spacing: 6

            ParamRow {
                Layout.fillWidth: true
                label: "Threshold"
                unit: "dB"
                from: Loudness.PARAMS.threshold.min
                to: Loudness.PARAMS.threshold.max
                stepSize: Loudness.PARAMS.threshold.step
                value: LoudnessState.values.threshold
                onMoved: v => LoudnessState.setParam("threshold", v)
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Ratio"
                unit: ":1"
                from: Loudness.PARAMS.ratio.min
                to: Loudness.PARAMS.ratio.max
                stepSize: Loudness.PARAMS.ratio.step
                value: LoudnessState.values.ratio
                onMoved: v => LoudnessState.setParam("ratio", v)
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Attack"
                unit: "ms"
                from: Loudness.PARAMS.attack.min
                to: Loudness.PARAMS.attack.max
                stepSize: Loudness.PARAMS.attack.step
                value: LoudnessState.values.attack
                onMoved: v => LoudnessState.setParam("attack", v)
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Release"
                unit: "ms"
                decimals: 0
                from: Loudness.PARAMS.release.min
                to: Loudness.PARAMS.release.max
                stepSize: Loudness.PARAMS.release.step
                value: LoudnessState.values.release
                onMoved: v => LoudnessState.setParam("release", v)
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Makeup gain"
                unit: "dB"
                from: Loudness.PARAMS.makeup.min
                to: Loudness.PARAMS.makeup.max
                stepSize: Loudness.PARAMS.makeup.step
                value: LoudnessState.values.makeup
                onMoved: v => LoudnessState.setParam("makeup", v)
            }

            ParamRow {
                Layout.fillWidth: true
                label: "Limiter ceiling"
                unit: "dB"
                from: Loudness.PARAMS.ceiling.min
                to: Loudness.PARAMS.ceiling.max
                stepSize: Loudness.PARAMS.ceiling.step
                value: LoudnessState.values.ceiling
                onMoved: v => LoudnessState.setParam("ceiling", v)
            }
        }

        // --------------------------------------------------------- curve
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            visible: card.expanded && LoudnessState.available
            radius: 8
            color: Theme.surface_container
            border.color: Theme.outline_variant
            border.width: 1

            Canvas {
                id: curve
                anchors.fill: parent
                anchors.margins: 8

                // Redraw whenever the maths behind the curve changes.
                readonly property real threshold: LoudnessState.values.threshold
                readonly property real ratio: LoudnessState.values.ratio
                readonly property real makeup: LoudnessState.values.makeup
                readonly property real ceiling: LoudnessState.values.ceiling
                // A Canvas repaints only when told to, so a theme switch would
                // otherwise leave it drawn in the old palette.
                readonly property color gridColor: Theme.outline_variant
                readonly property color curveColor: Theme.primary
                onThresholdChanged: requestPaint()
                onRatioChanged: requestPaint()
                onMakeupChanged: requestPaint()
                onCeilingChanged: requestPaint()
                onGridColorChanged: requestPaint()
                onCurveColorChanged: requestPaint()

                function px(db) {
                    return ((db + 60) / 60) * width;
                }
                function py(db) {
                    return height - ((db + 60) / 60) * height;
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);

                    // 1:1 reference, so the amount of compression reads at a
                    // glance as the gap between the two lines.
                    ctx.strokeStyle = curve.gridColor;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(px(-60), py(-60));
                    ctx.lineTo(px(0), py(0));
                    ctx.stroke();

                    ctx.strokeStyle = curve.curveColor;
                    ctx.lineWidth = 2;
                    ctx.beginPath();
                    for (let db = -60; db <= 0; db += 0.5) {
                        let out = Loudness.gainComputer(db, threshold, ratio) + makeup;
                        if (out > ceiling)
                            out = ceiling;
                        const x = px(db);
                        const y = py(Math.max(out, -60));
                        if (db === -60)
                            ctx.moveTo(x, y);
                        else
                            ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }
            }
        }

        // ------------------------------------------- reduction + makeup
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.expanded && LoudnessState.available
            spacing: 4

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    const parts = [];
                    for (let i = 0; i < Loudness.TABLE_LEVELS.length; i++) {
                        const lvl = Loudness.TABLE_LEVELS[i];
                        // Sign comes from the value: a hardcoded minus makes
                        // zero reduction render as "−0.0".
                        const gr = LoudnessState.reductionAt(lvl);
                        parts.push(lvl + " → " + (gr > 0.05 ? "−" : "") + gr.toFixed(1));
                    }
                    return "Reduction (dB): " + parts.join("   ");
                }
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: LoudnessState.limiterOnset === null ? "Limiter: never engages at these settings." : "Limiter engages above " + LoudnessState.limiterOnset.toFixed(1) + " dBFS input."
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Suggested makeup: +" + LoudnessState.suggestedMakeup.toFixed(1) + " dB"
                    color: Theme.tertiary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Rectangle {
                    implicitWidth: applyText.implicitWidth + 18
                    implicitHeight: 24
                    radius: 8
                    color: Theme.primary_container

                    Text {
                        id: applyText
                        anchors.centerIn: parent
                        text: "Apply"
                        color: Theme.on_primary_container
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LoudnessState.applySuggestedMakeup()
                    }
                }
            }
        }

        // ---------------------------------------------------- test tones
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.expanded && LoudnessState.available && LoudnessState.tonesAvailable
            spacing: 4

            Text {
                text: "Test sounds"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["Very quiet", "Quiet", "Medium", "Loud", "Very loud"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index

                        implicitWidth: toneText.implicitWidth + 18
                        implicitHeight: 26
                        radius: 8
                        color: "transparent"
                        border.color: Theme.outline_variant
                        border.width: 1

                        Text {
                            id: toneText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.playTone(parent.index)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: LoudnessState.errorMessage !== ""
            text: LoudnessState.errorMessage
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
