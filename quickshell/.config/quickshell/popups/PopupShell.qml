// popups/PopupShell.qml — styled container for popup content (gruvbox).
import QtQuick
import qs

Rectangle {
    id: root

    default property alias content: contentCol.data

    color: Theme.bg
    radius: Theme.radius
    border.color: Theme.dark2
    border.width: 1

    Column {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing
    }
}
