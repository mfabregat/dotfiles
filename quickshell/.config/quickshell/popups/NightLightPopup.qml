// popups/NightLightPopup.qml — night light controls (gammastep), the
// native replacement for the gammastep-indicator tray menu. Toggle,
// suspend presets, live status (period / temperature) and config info
// (day/night temps, brightness, gamma). The shell owns the daemon
// (services/NightLight.qml) — this popup only reads state and sends
// SIGUSR1, so nothing here can desync the screen.
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

        Divider {}

        // Live status (parsed from the daemon's -v output)
        InfoRow { label: "Period"; value: root.periodLabel() }
        InfoRow { label: "Temperature"; value: NightLight.enabled ? NightLight.temperature + "K" : "—" }
        InfoRow { label: "Day / Night"; value: NightLight.configDay + "K / " + NightLight.configNight + "K" }
        InfoRow {
            label: "Brightness"
            value: Math.round(NightLight.configDayBrightness * 100) + "% / "
                + Math.round(NightLight.configNightBrightness * 100) + "%"
        }
        InfoRow {
            label: "Gamma"
            value: (NightLight.configDayGamma || "—") + " / "
                + (NightLight.configNightGamma || "—")
        }

        Divider {}

        // Suspend presets (SIGUSR1 off, timed SIGUSR1 back on)
        Item {
            width: parent.width
            height: 20
            visible: !NightLight.suspended

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Suspend for"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { minutes: 30, label: "30m" },
                        { minutes: 60, label: "1h" },
                        { minutes: 120, label: "2h" },
                        { minutes: 240, label: "4h" },
                        { minutes: 480, label: "8h" }
                    ]

                    delegate: Chip {
                        required property var modelData
                        label: modelData.label
                        onClicked: NightLight.suspend(modelData.minutes)
                    }
                }
            }
        }

        // Suspended: countdown + resume now
        Item {
            width: parent.width
            height: 20
            visible: NightLight.suspended

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Resuming in " + root.fmtRemaining(NightLight.suspendRemaining)
                color: Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Chip {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Now"
                onClicked: NightLight.resumeNow()
            }
        }
    }

    // Period display, with the transition moment: while transitioning the
    // daemon reports the day-fraction ("Day: 45.57%") — how far the
    // screen is from night toward day colors (100% at dusk start, 0% at
    // full night, rising again at dawn), same as the old
    // gammastep-indicator Info dialog.
    function periodLabel(): string {
        const p = NightLight.period;
        if (p === "Transition") {
            return "Transition (Day: " + Math.round(NightLight.transitionDay) + "%)";
        }
        if (p === "Daytime" || p === "Night") return p;
        return "Off"; // "None" while disabled, "Unknown" before first line
    }

    function fmtRemaining(s: int): string {
        s = Math.max(0, s);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m";
        return m + ":" + String(sec).padStart(2, "0");
    }

    // ── Shared bits ────────────────────────────────────────────────────
    component Divider: Rectangle {
        width: parent.width
        height: 1
        color: Theme.dark2
    }

    // Label · value info row
    component InfoRow: Item {
        id: infoRow
        property string label: ""
        property string value: ""

        width: parent.width
        height: 18

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.value
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // Small clickable pill (suspend presets / resume now)
    component Chip: Rectangle {
        id: chip
        property string label: ""
        signal clicked

        width: chipText.implicitWidth + 12
        height: 18
        radius: 9
        color: chipArea.containsMouse ? Theme.bgHover : Theme.dark1
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: chip.clicked()
        }
    }
}
