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

            CpuMemPopup {
                id: cpuMemPopup
                anchorWindow: barWindow
            }

            NetworkMenu {
                id: networkMenu
                anchorWindow: barWindow
            }

            // Dismiss any open popup when pressing empty bar space (the
            // widgets' own MouseAreas dismiss on their presses too).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: PopupManager.hideOpen()
            }

            // ── Bar content ─────────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: Theme.spacing

                    // Top: desks + now playing
                    Workspaces {
                        id: wsWidget
                        Layout.alignment: Qt.AlignHCenter
                        screen: barWindow.screen
                    }

                    MprisWidget {
                        Layout.alignment: Qt.AlignHCenter
                        // Max height: from below the workspaces to the top
                        // edge of the centered taskbar (fixed siblings only
                        // — acyclic; the fill item absorbs any leftover)
                        freeSpace: (barWindow.height - taskbarWidget.height) / 2
                            - 3 - wsWidget.height - Theme.spacing
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Bottom: system + clock + power (one fixed block)
                    Column {
                        id: bottomGroup
                        width: 22
                        spacing: Theme.spacing
                        Layout.alignment: Qt.AlignHCenter

                        CpuMemWidget {
                            detailsPopup: cpuMemPopup
                        }

                        VolumeWidget {
                            audioMenu: audioMenu
                        }

                        BacklightWidget {}

                        NetworkWidget {
                            networkMenu: networkMenu
                        }

                        TrayWidget {
                            barWindow: barWindow
                        }

                        BatteryWidget {}

                        NotificationsWidget {}

                        ClockWidget {
                            calendar: calendarPopup
                        }

                        PowerWidget {
                            powerMenu: powerMenu
                        }
                }
            }

            // Center: all windows (taskbar) — pinned to the true vertical
            // center of the bar so it never drifts as the mpris text changes.
            Taskbar {
                id: taskbarWidget
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
