// popups/NotificationCenter.qml — notification history panel, one fullscreen
// window per screen; only the focused monitor's instance is visible
// (same pattern as the launcher). Toggled from the bar bell or via
// `quickshell ipc call notifications toggle` ($mod+n). Clicking the
// backdrop or pressing Esc closes it; opening it marks everything read.
import Quickshell
import Quickshell.I3
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

    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: Notifications.centerOpen && root.i3Monitor !== null && root.i3Monitor.focused

    // Card height computed explicitly: padding + header + list + spacing +
    // empty state (plain Items don't contribute implicit sizes, so no
    // implicit propagation here), clamped to the screen.
    readonly property int listH: Math.min(Notifications.notifications.length * 96, 400)
    readonly property int emptyH: Notifications.notifications.length === 0 ? 18 : 0

    // Fresh open: arm keyboard focus (deferred past surface mapping).
    onVisibleChanged: {
        if (root.visible) Qt.callLater(() => focusCatcher.forceActiveFocus());
    }

    // Backdrop: click-away closes.
    MouseArea {
        anchors.fill: parent
        onClicked: Notifications.closeCenter()
    }

    // ── Card (right edge, next to the bar) ─────────────────────────────
    Rectangle {
        id: card
        anchors.right: parent.right
        anchors.rightMargin: Theme.barWidth + 12
        anchors.top: parent.top
        anchors.topMargin: 12
        width: 380
        radius: Theme.popupRadius
        color: Theme.bg
        border.color: Theme.dark2
        border.width: 1
        clip: true

        height: Math.min(Theme.padding * 2 + 22 + 8 + root.listH + (root.emptyH > 0 ? 8 + root.emptyH : 0),
                         (root.screen ? root.screen.height : 1080) - 24)

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.padding
            spacing: 8

            // Header: title · DND toggle · clear all
            Item {
                width: parent.width
                height: 22

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        text: "" // bell-slash
                        color: dndArea.containsMouse ? Theme.fg
                             : Notifications.dnd ? Theme.warn : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeGlyphs
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: dndArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Notifications.dnd = !Notifications.dnd
                        }
                    }

                    Text {
                        text: "" // trash
                        visible: Notifications.notifications.length > 0
                        color: clearArea.containsMouse ? Theme.urgent : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeGlyphs
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Notifications.clearAll()
                        }
                    }
                }
            }

            // History list
            ListView {
                id: list
                width: parent.width
                height: Math.min(Notifications.notifications.length * 96, 400)
                model: Notifications.notifications
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    // Inline wrapper delegate — see NotificationPopup.qml for
                    // why file-component delegates can't read `modelData` here.
                    implicitHeight: row.implicitHeight
                    NotificationRow {
                        id: row
                        width: list.width
                        wrapper: modelData
                        bodyLines: 3
                    }
                }
            }

            // Empty state
            Text {
                width: parent.width
                visible: Notifications.notifications.length === 0
                text: "No notifications"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Invisible focus holder: Esc closes the center (launcher pattern —
    // declarative focus + deferred forceActiveFocus past mapping).
    Item {
        id: focusCatcher
        focus: true

        Keys.onEscapePressed: {
            Notifications.closeCenter();
            event.accepted = true;
        }
    }
}
