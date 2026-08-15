// bar/NetworkWidget.qml — active network (NetworkManager via Quickshell).
// Icon-only: the connection name lives in the popup (phase 7). Wifi is
// colored by signal strength (red → orange → green); ethernet is green
// when connected; dimmed when nothing is connected. Click opens the
// network menu popup.
import Quickshell
import Quickshell.Networking
import QtQuick
import qs

Rectangle {
    id: root

    required property var networkMenu

    readonly property var wifi: findWifi(Networking.devices.values)
    readonly property var activeNet: findActive(Networking.devices.values, wifi ? wifi.networks.values : [])
    readonly property bool activeIsWifi: root.activeNet !== null
        && root.activeNet.device && root.activeNet.device.type === DeviceType.Wifi

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    /// Wifi signal color: red < 40% < orange < 70% < green (signalStrength
    /// is 0..1). Three steps — more than three hues don't read at 16px.
    function strengthColor(s: real): color {
        if (s >= 0.7) return Theme.brightGreen;
        if (s >= 0.4) return Theme.brightOrange;
        return Theme.urgent;
    }

    function findWifi(devices: var): var {
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (d.type === DeviceType.Wifi) return d;
        }
        return null;
    }

    function findActive(devices: var, wifiNets: var): var {
        // Connected wifi first (the usual case; one scan, no duplicates).
        for (let i = 0; i < wifiNets.length; i++) {
            if (wifiNets[i].connected) return wifiNets[i];
        }
        // Then any device's own connected network (ethernet, ...). The old
        // `i === 0 ? networks : d.networks.values` hack never scanned the
        // ethernet device's networks when a wifi device existed — wired-only
        // connections showed as disconnected.
        for (let i = 0; i < devices.length; i++) {
            const nets = devices[i].networks.values;
            for (let j = 0; j < nets.length; j++) {
                if (nets[j].connected) return nets[j];
            }
        }
        return null;
    }

    Text {
        anchors.centerIn: parent
        text: root.wifi ? "" : "󰈀"
        color: !root.activeNet ? Theme.fgDim
             : root.activeIsWifi ? root.strengthColor(root.activeNet.signalStrength)
             : Theme.brightGreen
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeGlyphs
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.networkMenu.showAt(root)
    }
}
