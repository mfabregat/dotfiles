// popups/NotificationRow.qml — one notification card (used by both the
// popup window and the center). Gruvbox card: app icon, app name + time,
// summary, body, optional image and action buttons, close button.
// Urgency styling: critical gets a red border (and never auto-dismisses —
// that's decided in services/Notifications.qml).
//
// `pausable` rows (popups) pause their dismissal timer while hovered;
// `clickable` rows (popups) open the center on click. In the center both
// flags are off and hover only highlights.
//
// The card-level MouseArea is declared first (lowest z) so the close and
// action buttons above it keep receiving clicks.
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import qs
import qs.services

Rectangle {
    id: root

    /// The service wrapper object ({ notification, ... }).
    required property var wrapper
    property bool pausable: false
    property bool clickable: false
    property int bodyLines: 2

    readonly property var notif: root.wrapper && root.wrapper.notification
        ? root.wrapper.notification : null
    readonly property bool critical: root.notif !== null
        && root.notif.urgency === NotificationUrgency.Critical
    readonly property bool hovered: area.containsMouse

    width: 340
    radius: Theme.popupRadius
    color: root.hovered ? Theme.bgAlt : Theme.bg
    border.color: root.critical ? Theme.urgent : Theme.dark2
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    // Rectangles don't derive implicit size from children — expose the
    // content column's so popup windows/columns can size themselves.
    implicitHeight: content.implicitHeight + 20

    // Card-level interactions (bottom z): highlight, hover-pause, open-center.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onHoveredChanged: {
            if (root.pausable && root.wrapper) {
                Notifications.setPaused(root.wrapper, hovered);
            }
        }
        onClicked: {
            if (root.clickable) Notifications.openCenter();
        }
    }

    Column {
        id: content
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        // ── Header: icon · app + summary · close ───────────────────────
        Item {
            width: parent.width
            height: 32

            Rectangle {
                id: iconBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 6
                color: Theme.dark1
                clip: true

                Image {
                    id: iconImg
                    anchors.fill: parent
                    anchors.margins: 3
                    source: root.iconSource(root.notif ? root.notif.appIcon : "")
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeGlyphs
                    visible: iconImg.status !== Image.Ready
                }
            }

            Column {
                anchors.left: iconBox.right
                anchors.leftMargin: 8
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: root.notif ? root.notif.appName : ""
                    color: root.critical ? Theme.urgent : Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: root.notif ? root.notif.summary : ""
                    color: Theme.fg
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            Text {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                text: "✕"
                color: closeArea.containsMouse ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Notifications.discard(root.wrapper);
                }
            }
        }

        // ── Body ───────────────────────────────────────────────────────
        Text {
            width: parent.width
            visible: root.notif !== null && root.notif.body.length > 0
            text: root.notif ? root.notif.body : ""
            color: Theme.fgDim
            wrapMode: Text.Wrap
            maximumLineCount: root.bodyLines
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            lineHeight: 1.2
        }

        Image {
            width: parent.width
            height: Math.min(96, implicitHeight > 0 ? implicitHeight : 96)
            source: root.notif ? root.notif.image : ""
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            clip: true
        }

        // ── Actions ────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 6
            visible: root.notif !== null && root.notif.actions.length > 0

            Repeater {
                model: root.notif ? root.notif.actions : []

                Rectangle {
                    required property var modelData

                    height: 22
                    width: Math.min(actionText.implicitWidth + 14, 140)
                    radius: 5
                    color: actionArea.containsMouse ? Theme.accent : Theme.dark1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: modelData.text
                        color: actionArea.containsMouse ? Theme.dark0 : Theme.fg
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            modelData.invoke(); // closes unless resident
                        }
                    }
                }
            }
        }
    }

    /// Resolve an app icon to an Image source. Uses the native
    /// `Quickshell.iconPath` for theme names; absolute paths become file
    /// URLs (apps sometimes pass `/path/to/icon.png` directly).
    function iconSource(appIcon: string): string {
        const raw = String(appIcon || "");
        if (raw.length === 0) return "";
        if (raw.startsWith("file://") || raw.startsWith("image://")) return raw;
        if (raw.startsWith("/")) return "file://" + raw;
        return Quickshell.iconPath(raw);
    }
}
