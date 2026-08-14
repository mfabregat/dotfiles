// popups/PowerMenu.qml — lock / logout / suspend / reboot / shutdown.
// The actions live in the shared popups/PowerSection.qml (the control
// center embeds the same block); this file is just the anchored popup.
import QtQuick
import qs.popups

AnchoredPopup {
    id: root

    implicitWidth: 230
    implicitHeight: popupShell.implicitHeight

    PopupShell {
        id: popupShell
        anchors.fill: parent

        PowerSection {
            width: parent.width
            onActionTriggered: root.hide()
        }
    }
}
