// bar/NetworkWidget.qml — active network (NetworkManager via Quickshell).
// Click opens the network menu popup (phase 7).
import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups

Rectangle {
    id: root

    required property var networkMenu

    readonly property var wifi: findWifi(Networking.devices.values)
    readonly property var activeNet: findActive(Networking.devices.values, wifi ? wifi.networks.values : [])

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.wifi ? "" : "󰈀"
            color: root.activeNet ? Theme.fg : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeGlyphs
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: root.activeNet ? root.activeNet.name : ""
            visible: root.activeNet !== null // no blank line when disconnected
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.networkMenu.showAt(root)
    }
}
