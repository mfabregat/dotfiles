// popups/NetworkMenu.qml — quick wifi/ethernet menu (bar network widget).
// Shares the network block with the control center (NetworkSection.qml).
import QtQuick
import qs
import qs.services

AnchoredPopup {
    id: root

    implicitWidth: 280
    implicitHeight: Math.min(popupShell.implicitHeight, 420)

    PopupShell {
        id: popupShell
        anchors.fill: parent

        NetworkSection {
            width: parent.width
        }
    }

    // Scanner refcount: scan only while this menu is open.
    onVisibleChanged: WifiState.useScanner(root.visible)
}
