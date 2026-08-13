// bar/NetworkWidget.qml — active network (NetworkManager via Quickshell).
// v1: display only; the full network menu arrives with the control center.
import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

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

    function findActive(devices: var, networks: var): var {
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const nets = i === 0 ? networks : d.networks.values;
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
    }
}
