// bar/NotificationsWidget.qml — notification bell: unread badge, dimmed
// while do-not-disturb; click toggles the notification center. The badge
// counts notifications that arrived since the center was last opened.
import QtQuick
import qs
import qs.popups
import qs.services

Rectangle {
    id: root

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    Text {
        anchors.centerIn: parent
        text: ""
        color: Notifications.unread > 0 ? Theme.fg : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeGlyphs
    }

    // Unread badge (hidden while DND — no popups, no badge)
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.right: parent.right
        anchors.rightMargin: 2
        width: 14
        height: 14
        radius: 7
        color: Theme.urgent
        visible: Notifications.unread > 0 && !Notifications.dnd

        Text {
            anchors.centerIn: parent
            text: Math.min(Notifications.unread, 9)
            color: Theme.light0
            font.family: Theme.fontFamily
            font.pixelSize: 8
            font.bold: true
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onPressed: PopupManager.hideOpen() // dismiss bar popups first
        onClicked: Notifications.toggleCenter()
    }
}
