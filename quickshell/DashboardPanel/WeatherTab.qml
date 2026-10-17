import QtQuick
import QtQuick.Layouts
import qs.shared
import qs.shared.ui
import qs.DashboardPanel
import "WeatherData.js" as W

// Current conditions, today's hours and a three-day forecast (Weather).
TabPage {
    id: tab

    readonly property var w: Weather.current

    implicitWidth: 640
    implicitHeight: Math.max(200, column.implicitHeight)

    component Glyph: Text {
        font.family: Theme.iconFontFamily
        color: Theme.primary
    }

    component Small: Text {
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    ColumnLayout {
        id: column
        width: tab.implicitWidth
        spacing: 12
        visible: tab.w !== null

        // --- now ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18

                Glyph {
                    text: tab.w ? Weather.glyph(tab.w.code) : ""
                    font.pixelSize: 80
                }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: tab.w ? Math.round(tab.w.tempC) + "°C" : ""
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        font.bold: true
                    }
                    Text {
                        text: tab.w ? tab.w.desc : ""
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }
                    Small {
                        text: tab.w ? "Feels like " + Math.round(tab.w.feelsC) + "°  ·  " + tab.w.location : ""
                    }
                }
                Item { Layout.fillWidth: true }
                GridLayout {
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 8
                    Glyph { text: String.fromCodePoint(0xF058E); font.pixelSize: 16 }
                    Small { text: tab.w ? tab.w.humidity + "%" : "" }
                    Glyph { text: String.fromCodePoint(0xF059D); font.pixelSize: 16 }
                    Small { text: tab.w ? tab.w.windKmph + " km/h " + tab.w.windDir : "" }
                    Glyph { text: String.fromCodePoint(0xF059C); font.pixelSize: 16 }
                    Small { text: tab.w ? W.to24h(tab.w.sunrise) : "" }
                    Glyph { text: String.fromCodePoint(0xF059B); font.pixelSize: 16 }
                    Small { text: tab.w ? W.to24h(tab.w.sunset) : "" }
                }
            }
        }

        // --- today, every 3 hours ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 0
                Repeater {
                    model: tab.w ? tab.w.hourly : []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        Small {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.time
                        }
                        Glyph {
                            Layout.alignment: Qt.AlignHCenter
                            // Night glyphs for the hours outside daylight.
                            text: W.glyph(modelData.code, tab.w ? W.isNight(modelData.hour * 60, tab.w.sunrise, tab.w.sunset) : false)
                            font.pixelSize: 22
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(modelData.tempC) + "°"
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Small {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.rain + "%"
                            opacity: modelData.rain > 0 ? 1 : 0.4
                        }
                    }
                }
            }
        }

        // --- three days ---
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: daysColumn.implicitHeight + 24
            ColumnLayout {
                id: daysColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                Repeater {
                    model: tab.w ? tab.w.days : []
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 60
                            text: index === 0 ? "Today" : modelData.weekday
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Glyph {
                            text: isNaN(modelData.code) ? "" : W.glyph(modelData.code, false)
                            font.pixelSize: 20
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(modelData.maxC) + "°"
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Small { text: Math.round(modelData.minC) + "°" }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Small {
                Layout.fillWidth: true
                text: (Weather.stale ? "Showing cached data — " + Weather.error.toLowerCase() + ". " : "")
                    + "Updated " + Qt.formatDateTime(new Date(Weather.fetchedAt), "HH:mm")
                    + (Weather.location === "" ? " · location from IP" : "")
            }
            ActionIcon {
                iconTxt: Weather.loading ? "…" : "↻"
                enabled: !Weather.loading
                onClicked: Weather.fetch()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: tab.w === null
        text: Weather.loading ? "Loading weather…" : (Weather.error !== "" ? Weather.error : "No weather yet")
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 14
    }
}
