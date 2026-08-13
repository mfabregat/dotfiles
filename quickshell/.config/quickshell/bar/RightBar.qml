// bar/RightBar.qml — the shell's right-edge bar, one instance per screen.
// Phase 2: workspaces, taskbar, mpris, cpu/mem/temp, volume, backlight,
// network, layout, tray, battery, clock, power + calendar/audio/power popups.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.bar
import qs.popups

Scope {
    id: root

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
            color: Theme.bg // flush edge-to-edge bar (no gaps, no radius)

            // ── Popups (anchored to their trigger widget) ───────────────
            CalendarPopup {
                id: calendarPopup
                anchorWindow: barWindow
            }

            AudioMenu {
                id: audioMenu
                anchorWindow: barWindow
            }

            PowerMenu {
                id: powerMenu
                anchorWindow: barWindow
            }

            // ── Bar content ─────────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: Theme.spacing

                    // Top: desks + now playing
                    Workspaces {
                        id: wsWidget
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    MprisWidget {
                        Layout.alignment: Qt.AlignHCenter
                        // Space between workspaces and the taskbar (fixed
                        // siblings only — acyclic; the two spacers absorb
                        // whatever the text leaves over)
                        freeSpace: barWindow.height - wsWidget.height
                            - taskbarWidget.height - bottomGroup.height - 5 * Theme.spacing
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Center: all windows (taskbar)
                    Taskbar {
                        id: taskbarWidget
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Bottom: system + clock + power (one block so the
                    // mpris freeSpace can use its total height)
                    Column {
                        id: bottomGroup
                        width: 30
                        spacing: Theme.spacing
                        Layout.alignment: Qt.AlignHCenter

                        CpuMemWidget {}

                        VolumeWidget {
                            audioMenu: audioMenu
                        }

                        BacklightWidget {}

                        NetworkWidget {}

                        LayoutWidget {}

                        TrayWidget {
                            barWindow: barWindow
                        }

                        BatteryWidget {}

                        ClockWidget {
                            calendar: calendarPopup
                        }

                        PowerWidget {
                            powerMenu: powerMenu
                        }
                }
            }
        }
    }
}
