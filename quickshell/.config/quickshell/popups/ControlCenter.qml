// popups/ControlCenter.qml — control panel: volume/brightness sliders,
// night light, network, power. One fullscreen window per screen; only the
// focused monitor's instance is visible (launcher pattern). Toggled from
// sway: `quickshell ipc call controlcenter toggle` ($mod+Shift+c).
//
// Volume writes go through Pipewire natively (node.audio.volume — the
// same verified pattern as the bar VolumeWidget); brightness writes use
// brightnessctl (udev perms — reads stay sysfs-native via the service);
// night light wraps gammastep (services/NightLight.qml); the network and
// power blocks are the shared NetworkSection / PowerSection components.
import Quickshell
import Quickshell.I3
import Quickshell.Services.Pipewire
import Quickshell.Wayland._WlrLayerShell
import QtQuick
import qs
import qs.popups
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Focused monitor's instance only (guard pattern: I3.monitorFor is a
    // native method — its internals aren't tracked by bindings).
    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: ControlCenter.open && root.i3Monitor !== null && root.i3Monitor.focused

    readonly property var volNode: Pipewire.defaultAudioSink
    readonly property int volPct: volNode && volNode.audio ? Math.round(volNode.audio.volume * 100) : 0

    // Brightness write debounce: a slider drag fires many times; coalesce
    // to one brightnessctl spawn per ~120ms (playbook: coalesce rapid
    // wheel/step deltas).
    property int brightTarget: -1
    Timer {
        id: brightDebounce
        interval: 120
        repeat: false
        onTriggered: {
            if (root.brightTarget >= 0 && Brightness.available) {
                Quickshell.execDetached(["brightnessctl", "set", root.brightTarget + "%"]);
            }
        }
    }

    // Fresh open: arm keyboard focus (deferred past surface mapping).
    // The wifi scanner runs while the center is open (refcounted).
    onVisibleChanged: {
        if (root.visible) {
            Qt.callLater(() => focusCatcher.forceActiveFocus());
            WifiState.useScanner(true);
        } else {
            WifiState.useScanner(false);
        }
    }

    // Backdrop: click-away closes.
    MouseArea {
        anchors.fill: parent
        onClicked: ControlCenter.open = false
    }

    // ── Card (right edge, next to the bar) ─────────────────────────────
    Rectangle {
        id: card
        anchors.right: parent.right
        anchors.rightMargin: Theme.barWidth + 12
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: 340
        radius: Theme.popupRadius
        color: Theme.bg
        border.color: Theme.dark2
        border.width: 1
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Theme.padding
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width
                spacing: Theme.spacing

                // ── Header ─────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Control Center"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        color: closeArea.containsMouse ? Theme.fg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: ControlCenter.open = false
                        }
                    }
                }

                // ── Volume ─────────────────────────────────────────────
                SectionLabel { text: "Sound" }

                ControlRow {
                    icon: root.volNode && root.volNode.audio && root.volNode.audio.muted ? "" : ""
                    iconColor: root.volNode && root.volNode.audio && root.volNode.audio.muted ? Theme.urgent : Theme.fg
                    label: "Volume"
                    value: root.volPct + "%"
                    switchChecked: root.volNode && root.volNode.audio ? root.volNode.audio.muted : false
                    showSwitch: true
                    onSwitchToggled: on => {
                        if (root.volNode && root.volNode.audio) {
                            root.volNode.audio.muted = on;
                        }
                    }
                }

                ControlSlider {
                    width: parent.width
                    from: 0
                    to: 100
                    value: root.volPct
                    onUserSet: v => {
                        if (root.volNode && root.volNode.audio) {
                            root.volNode.audio.volume = v / 100;
                        }
                    }
                }

                // ── Brightness (only when a backlight exists) ──────────
                SectionLabel { text: "Display"; visible: Brightness.available }

                ControlRow {
                    visible: Brightness.available
                    icon: ""
                    label: "Brightness"
                    value: (Brightness.available ? Brightness.percent : 0) + "%"
                }

                ControlSlider {
                    width: parent.width
                    visible: Brightness.available
                    from: 0
                    to: 100
                    value: Brightness.percent
                    onUserSet: v => {
                        root.brightTarget = Math.round(v);
                        brightDebounce.restart();
                    }
                }

                // ── Night light (gammastep) ────────────────────────────
                SectionLabel { text: "Night Light"; visible: NightLight.available }

                ControlRow {
                    visible: NightLight.available
                    icon: ""
                    iconColor: NightLight.enabled ? Theme.warn : Theme.fg
                    label: "Night light"
                    value: NightLight.temperature + "K"
                    switchChecked: NightLight.enabled
                    showSwitch: true
                    onSwitchToggled: on => NightLight.setEnabled(on)
                }

                ControlSlider {
                    width: parent.width
                    visible: NightLight.available
                    from: NightLight.minTemp
                    to: NightLight.maxTemp
                    value: NightLight.temperature
                    onUserSet: v => NightLight.setTemperature(v)
                }

                // Day / night brightness (gammastep -b DAY:NIGHT)
                ValueSlider {
                    width: parent.width
                    visible: NightLight.available
                    label: "Day brightness"
                    valueText: Math.round(NightLight.dayBrightness * 100) + "%"
                    from: 0.1
                    to: 1.0
                    value: NightLight.dayBrightness
                    onUserSet: v => NightLight.setDayBrightness(v)
                }

                ValueSlider {
                    width: parent.width
                    visible: NightLight.available
                    label: "Night brightness"
                    valueText: Math.round(NightLight.nightBrightness * 100) + "%"
                    from: 0.1
                    to: 1.0
                    value: NightLight.nightBrightness
                    onUserSet: v => NightLight.setNightBrightness(v)
                }

                // ── Network (wifi parts hide without wifi hardware) ────
                NetworkSection {
                    width: parent.width
                }

                // ── Power ──────────────────────────────────────────────
                PowerSection {
                    width: parent.width
                    onActionTriggered: ControlCenter.open = false
                }
            }
        }
    }

    // Invisible focus holder: Esc closes the center (launcher pattern).
    Item {
        id: focusCatcher
        focus: true

        Keys.onEscapePressed: {
            ControlCenter.open = false;
            event.accepted = true;
        }
    }

    // ── Section header (same micro-label as PowerSection) ──────────────
    component SectionLabel: Text {
        text: ""
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing
    }

    // ── Icon + label + value + optional switch row ─────────────────────
    // Anchors-based (like the notification center header): left texts and
    // a right-aligned value/switch — no Row layout tricks needed.
    component ControlRow: Item {
        property string icon: ""
        property color iconColor: Theme.fg
        property string label: ""
        property string value: ""
        property bool showSwitch: false
        property bool switchChecked: false
        signal switchToggled(bool on)

        width: parent.width
        height: 20

        Text {
            id: iconText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: icon
            color: iconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeGlyphs
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
            anchors.left: iconText.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            anchors.right: showSwitch ? switchItem.left : parent.right
            anchors.rightMargin: showSwitch ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: value !== ""
            text: value
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        ToggleSwitch {
            id: switchItem
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: showSwitch
            checked: switchChecked
            onToggled: on => parent.switchToggled(on)
        }
    }

    // ── Small label + slider (night light day/night brightness) ────────
    component ValueSlider: Column {
        property string label: ""
        property string valueText: ""
        property real from: 0
        property real to: 100
        property real value: 0
        signal userSet(real v)

        spacing: 2

        Item {
            width: parent.width
            height: 18

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: valueText
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        ControlSlider {
            width: parent.width
            from: parent.from
            to: parent.to
            value: parent.value
            onUserSet: v => parent.userSet(v)
        }
    }
}
