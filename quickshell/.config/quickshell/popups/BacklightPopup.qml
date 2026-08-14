// popups/BacklightPopup.qml — screen brightness slider.
// Anchored to the bar's backlight widget (click to open, wheel still
// works directly on the widget). Writes go through brightnessctl (udev
// perms — reads stay sysfs-native via the Brightness service).
import Quickshell
import QtQuick
import qs
import qs.popups
import qs.services

AnchoredPopup {
    id: root

    implicitWidth: 280
    implicitHeight: popupShell.implicitHeight

    // Slider drags fire many times; coalesce to one brightnessctl spawn
    // per ~120ms (playbook: coalesce rapid step deltas).
    property int target: -1
    Timer {
        id: writeDebounce
        interval: 120
        repeat: false
        onTriggered: {
            if (root.target >= 0) {
                Quickshell.execDetached(["brightnessctl", "set", root.target + "%"]);
            }
        }
    }

    PopupShell {
        id: popupShell
        anchors.fill: parent

        SectionLabel { text: "Brightness" }

        Item {
            width: parent.width
            height: 20

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "Backlight"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Brightness.percent + "%"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        ControlSlider {
            width: parent.width
            from: 0
            to: 100
            value: Brightness.percent
            onUserSet: v => {
                root.target = Math.round(v);
                writeDebounce.restart();
            }
        }
    }
}
