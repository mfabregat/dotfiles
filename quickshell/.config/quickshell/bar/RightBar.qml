// bar/RightBar.qml — the shell's right-edge bar, one instance per screen.
// Phase 2: workspaces, taskbar, mpris, cpu/mem/temp, volume, backlight,
// network, layout, tray, battery, clock, power + calendar/audio/power popups.
//
// Windows must be Variants delegates in quickshell 0.3.0 (direct children
// never map), so the bar AND every popup get their own per-screen Variants.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.bar
import qs.popups

Scope {
    id: root

    // ── Bar per screen ──────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow

            required property var modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                right: true
            }

            implicitWidth: Theme.barWidth
            color: "transparent"

            Rectangle {
                id: barSurface

                anchors.fill: parent
                anchors.margins: Theme.spacing
                radius: Theme.radius
                color: Theme.bg

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: Theme.spacing

                    // Top: desks + windows
                    Workspaces {
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    Taskbar {
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Bottom: media + system + clock + power
                    MprisWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    CpuMemWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    VolumeWidget {
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    BacklightWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    NetworkWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    LayoutWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    TrayWidget {
                        Layout.alignment: Qt.AlignHCenter
                        barWindow: barWindow
                    }

                    BatteryWidget {
                        Layout.alignment: Qt.AlignHCenter
                    }

                    ClockWidget {
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    PowerWidget {
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }
                }
            }
        }
    }

    // ── Popups per screen (backdrop first, so it stacks below) ─────────
    Variants {
        model: Quickshell.screens

        PopupBackdrop {
            required property var modelData
            popupType: "backdrop"
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        CalendarPopup {
            required property var modelData
            popupType: "calendar"
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        AudioMenu {
            required property var modelData
            popupType: "audio"
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        PowerMenu {
            required property var modelData
            popupType: "power"
            screen: modelData
        }
    }
}
