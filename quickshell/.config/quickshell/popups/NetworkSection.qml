// popups/NetworkSection.qml — wifi + ethernet block, shared by the bar
// network menu (popups/NetworkMenu.qml) and the control center.
// Native NetworkManager state via services/WifiState.qml — no nmcli
// subprocesses. The wifi parts hide when the machine has no wifi
// hardware (this desktop doesn't); the ethernet row always shows.
//
// Delegate notes (landmines 9/14): plain inline delegates only, no
// `required property var modelData` (it kills `index`); the row binds
// `net` from the sorted array by index instead of reading modelData.
import Quickshell.Networking
import QtQuick
import qs
import qs.services

Column {
    id: root

    spacing: Theme.spacing

    readonly property var wiredDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wired)
    /// Show at most 8 APs (the popup clamps height anyway).
    readonly property var visibleNetworks: WifiState.sortedNetworks.slice(0, 8)

    /// Nerd-font signal bars from the module's 0..1 signalStrength.
    function strengthIcon(strength: real): string {
        if (strength > 0.8) return "󰤨";
        if (strength > 0.6) return "󰤥";
        if (strength > 0.4) return "󰤢";
        if (strength > 0.2) return "󰤟";
        return "󰤯";
    }

    // ── Wi-Fi header: label + enable toggle ────────────────────────────
    Item {
        width: parent.width
        height: 22
        visible: WifiState.wifiDevice !== null

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        ToggleSwitch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: WifiState.wifiEnabled
            onToggled: on => WifiState.enableWifi(on)
        }
    }

    // ── Rescan row ─────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: Theme.popupRowHeight
        radius: Theme.radius
        visible: WifiState.wifiDevice !== null
        color: rescanArea.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeGlyphs
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 36
            anchors.verticalCenter: parent.verticalCenter
            text: "Rescan"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        MouseArea {
            id: rescanArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: WifiState.rescan()
        }
    }

    // ── Connection error (shown under the rows) ────────────────────────
    Text {
        width: parent.width
        visible: WifiState.error !== ""
        text: WifiState.error
        color: Theme.urgent
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    // ── Network rows ───────────────────────────────────────────────────
    Repeater {
        model: root.visibleNetworks

        delegate: Column {
            readonly property var net: WifiState.sortedNetworks[index]
            readonly property bool isPsk: WifiState.pskNetwork === net
            readonly property bool isPending: WifiState.pending === net

            width: root.width
            spacing: Theme.spacing

            // Focus the password field only when this row actually opens (the
            // delegate is created for every network, hidden or not — a plain
            // onCompleted would steal focus at creation).
            onIsPskChanged: {
                if (isPsk) Qt.callLater(() => pskInput.forceActiveFocus());
            }

            // Main row
            Rectangle {
                width: root.width
                height: Theme.popupRowHeight
                radius: Theme.radius
                color: rowArea.containsMouse ? Theme.bgHover : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                // Signal strength icon
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: strengthIcon(net.signalStrength)
                    color: net.connected ? Theme.accent : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeGlyphs
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Lock glyph (secured networks)
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    visible: net.security !== WifiSecurityType.Open
                        && net.security !== WifiSecurityType.Owe
                    text: ""
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                // SSID
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 40
                    anchors.right: statusGlyph.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: net.name
                    color: net.connected ? Theme.fg : Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: net.connected
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Status glyph: check / spinner / chevron
                Text {
                    id: statusGlyph
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: net.connected ? ""
                        : isPending ? "…"
                        : WifiState.pskNetwork === net ? "" : ""
                    color: net.connected ? Theme.accent
                        : isPending ? Theme.warn : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: WifiState.connect(net)
                }
            }

            // Inline PSK row (this network is awaiting a password)
            Item {
                width: root.width
                height: isPsk ? 30 : 0
                visible: isPsk
                clip: true

                TextInput {
                    id: pskInput
                    anchors.left: parent.left
                    anchors.right: pskConnect.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    echoMode: TextInput.Password
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.dark0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    clip: true

                    Keys.onReturnPressed: { root.submitPsk(pskInput.text); event.accepted = true; }
                    Keys.onEnterPressed: { root.submitPsk(pskInput.text); event.accepted = true; }
                    Keys.onEscapePressed: { WifiState.cancelPsk(); event.accepted = true; }
                }

                Text {
                    id: pskConnect
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect"
                    color: pskArea.containsMouse ? Theme.fg : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: pskArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.submitPsk(pskInput.text)
                    }
                }
            }
        }
    }

    // Empty wifi state (scanner just turned on — results land in a moment)
    Text {
        width: parent.width
        visible: WifiState.wifiDevice !== null && WifiState.sortedNetworks.length === 0
        text: "No networks found"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
    }

    // ── Ethernet rows ──────────────────────────────────────────────────
    Item {
        width: parent.width
        height: root.wiredDevices.length > 0 ? 22 : 0
        visible: root.wiredDevices.length > 0

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Ethernet"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    Repeater {
        model: root.wiredDevices

        delegate: Rectangle {
            required property var modelData

            width: root.width
            height: Theme.popupRowHeight
            radius: Theme.radius
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.connected ? "󰈀" : "󰈁"
                color: modelData.connected ? Theme.accent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 36
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.connected ? "Connected" : "Disconnected"
                color: modelData.connected ? Theme.fgDim : Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    function submitPsk(text: string): void {
        WifiState.connectWithPsk(text);
    }
}
