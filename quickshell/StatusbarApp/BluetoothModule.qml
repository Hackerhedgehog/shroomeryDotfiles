import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.shared

// Bluetooth status icon: hovering it grows the bar into the BluetoothPanel
// panel.
// bluetooth while the default adapter is powered, bluetooth-crossed when it
// is off or there is no adapter.
BarButton {
    id: bluetoothButton
    popout: "bluetooth"
    readonly property bool powered: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false

    iconSrc: Paths.icon(powered ? "bluetooth" : "bluetooth-crossed")

}
