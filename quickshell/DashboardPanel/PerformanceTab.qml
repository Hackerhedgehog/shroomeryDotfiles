import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.shared
import qs.shared.ui
import qs.DashboardPanel
import "Stats.js" as Stats

// CPU (load sparkline + temperature), memory and swap, GPU (NVIDIA, only
// read while this tab shows and the card is awake), network rates, and every
// mounted disk.
TabPage {
    id: tab

    implicitWidth: 640
    implicitHeight: grid.implicitHeight

    // Ask SystemStats for the GPU only while this tab is showing.
    onActiveChanged: SystemStats.gpuConsumers = Math.max(0, SystemStats.gpuConsumers + (active ? 1 : -1))
    Component.onDestruction: if (active) SystemStats.gpuConsumers = Math.max(0, SystemStats.gpuConsumers - 1)

    function kb(v: real): string {
        return Stats.formatBytes(v * 1024);
    }

    component Title: RowLayout {
        property string glyph: ""
        property string text: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: parent.glyph
            color: Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 18
        }
        Text {
            Layout.fillWidth: true
            text: parent.text
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
        }
        Text {
            text: parent.value
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
        }
    }

    GridLayout {
        id: grid
        width: tab.implicitWidth
        columns: 2
        rowSpacing: 12
        columnSpacing: 12

        // --- CPU ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8
                Title {
                    glyph: String.fromCodePoint(0xF0EE0)
                    text: "CPU"
                    value: Math.round(SystemStats.cpuPercent) + "%"
                        + (isNaN(SystemStats.cpuTempC) ? "" : "  ·  " + Math.round(SystemStats.cpuTempC) + "°C")
                }
                // Load over the last two minutes.
                Shape {
                    id: spark
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    preferredRendererType: Shape.CurveRenderer
                    readonly property var history: SystemStats.cpuHistory
                    ShapePath {
                        strokeColor: Theme.primary
                        strokeWidth: 2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: {
                                const h = spark.history;
                                const pts = [];
                                for (let i = 0; i < h.length; i++)
                                    pts.push(Qt.point(spark.width * (60 - h.length + i) / 59,
                                                      spark.height * (1 - h[i] / 100)));
                                return pts;
                            }
                        }
                    }
                }
            }
        }

        // --- Memory ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Title {
                    glyph: String.fromCodePoint(0xF035B)
                    text: "Memory"
                }
                UsageBar {
                    Layout.fillWidth: true
                    label: "RAM"
                    valueText: tab.kb(SystemStats.memUsedKb) + " / " + tab.kb(SystemStats.memTotalKb)
                    fraction: SystemStats.memTotalKb > 0 ? SystemStats.memUsedKb / SystemStats.memTotalKb : 0
                }
                UsageBar {
                    Layout.fillWidth: true
                    visible: SystemStats.swapTotalKb > 0
                    label: "Swap"
                    valueText: tab.kb(SystemStats.swapUsedKb) + " / " + tab.kb(SystemStats.swapTotalKb)
                    fraction: SystemStats.swapTotalKb > 0 ? SystemStats.swapUsedKb / SystemStats.swapTotalKb : 0
                }
                Item { Layout.fillHeight: true }
            }
        }

        // --- GPU (hidden without an NVIDIA card) ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            visible: SystemStats.gpuState !== "none"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Title {
                    glyph: String.fromCodePoint(0xF08AE)
                    text: "GPU"
                    value: SystemStats.gpuState === "active" && SystemStats.gpu
                        ? SystemStats.gpu.util + "%  ·  " + SystemStats.gpu.tempC + "°C" : ""
                }
                UsageBar {
                    Layout.fillWidth: true
                    visible: SystemStats.gpuState === "active" && SystemStats.gpu !== null
                    label: "VRAM"
                    valueText: SystemStats.gpu ? SystemStats.gpu.memUsedMb + " / " + SystemStats.gpu.memTotalMb + " MB" : ""
                    fraction: SystemStats.gpu && SystemStats.gpu.memTotalMb > 0
                        ? SystemStats.gpu.memUsedMb / SystemStats.gpu.memTotalMb : 0
                }
                Text {
                    Layout.fillWidth: true
                    visible: SystemStats.gpuState === "asleep"
                    text: "GPU asleep — not polled, so it can stay powered down"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
            }
        }

        // --- Network ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8
                Title {
                    glyph: String.fromCodePoint(0xF04E1)
                    text: "Network"
                }
                Text {
                    text: String.fromCodePoint(0xF0045) + "  " + Stats.formatRate(SystemStats.netRxRate)
                    color: Theme.on_surface
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                }
                Text {
                    text: String.fromCodePoint(0xF005D) + "  " + Stats.formatRate(SystemStats.netTxRate)
                    color: Theme.on_surface
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                }
                Item { Layout.fillHeight: true }
            }
        }

        // --- Disks ---
        Card {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: disksColumn.implicitHeight + 28
            ColumnLayout {
                id: disksColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Title {
                    glyph: String.fromCodePoint(0xF02CA)
                    text: "Disks"
                }
                Repeater {
                    model: SystemStats.disks
                    delegate: UsageBar {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.mount
                        valueText: tab.kb(modelData.usedKb) + " / " + tab.kb(modelData.sizeKb)
                            + "  (" + Math.round(modelData.percent) + "%)"
                        fraction: modelData.percent / 100
                    }
                }
            }
        }
    }
}
