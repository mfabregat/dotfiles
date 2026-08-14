// popups/NightLightPopup.qml — night light controls (gammastep daemon).
// Anchored to the bar's night light widget. Sliders update the persisted
// state live but only restart the gammastep daemon on RELEASE (a daemon
// restart is a ~50ms neutral flash — restarting per tick would flicker;
// see services/NightLight.qml).
import QtQuick
import qs
import qs.popups
import qs.services

AnchoredPopup {
    id: root

    implicitWidth: 280
    implicitHeight: popupShell.implicitHeight

    PopupShell {
        id: popupShell
        anchors.fill: parent

        SectionLabel { text: "Night Light" }

        // Toggle row: icon · label · switch
        Item {
            width: parent.width
            height: 20

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: NightLight.enabled ? Theme.warn : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "Enabled"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            ToggleSwitch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: NightLight.enabled
                onToggled: on => NightLight.setEnabled(on)
            }
        }

        // Temperature (1000–6500K)
        SliderRow {
            label: "Temperature"
            valueText: NightLight.temperature + "K"
            from: NightLight.minTemp
            to: NightLight.maxTemp
            value: NightLight.temperature
            onUserSet: v => NightLight.setTemperature(v)
            onCommitted: NightLight.apply()
        }

        // Day / night brightness (gammastep -b DAY:NIGHT)
        SliderRow {
            label: "Day brightness"
            valueText: Math.round(NightLight.dayBrightness * 100) + "%"
            from: 0.1
            to: 1.0
            value: NightLight.dayBrightness
            onUserSet: v => NightLight.setDayBrightness(v)
            onCommitted: NightLight.apply()
        }

        SliderRow {
            label: "Night brightness"
            valueText: Math.round(NightLight.nightBrightness * 100) + "%"
            from: 0.1
            to: 1.0
            value: NightLight.nightBrightness
            onUserSet: v => NightLight.setNightBrightness(v)
            onCommitted: NightLight.apply()
        }
    }

    // ── Section header (same micro-label as PowerSection/AudioMenu) ────
    component SectionLabel: Text {
        text: ""
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing
    }

    // ── Label + value + slider; commits (daemon restart) on release ────
    component SliderRow: Column {
        property string label: ""
        property string valueText: ""
        property real from: 0
        property real to: 100
        property real value: 0
        signal userSet(real v)
        signal committed

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
            onPressedChanged: { if (!pressed) parent.committed(); }
        }
    }
}
