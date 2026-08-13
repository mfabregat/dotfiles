// popups/PopupBackdrop.qml — fullscreen transparent click-catcher shown
// while a popup is open; pressing anywhere dismisses all popups.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services

PanelWindow {
    id: root

    required property string popupType

    color: "transparent"
    visible: true
    implicitWidth: 0
    implicitHeight: 0
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Component.onCompleted: PopupRegistry.register(root.screen, root.popupType, root)

    MouseArea {
        anchors.fill: parent
        onPressed: PopupRegistry.closeAll(root.screen)
    }

    function show(): void {
        if (!root.screen) return;
        root.implicitWidth = root.screen.width;
        root.implicitHeight = root.screen.height;
    }

    function hide(): void {
        root.implicitWidth = 0;
        root.implicitHeight = 0;
    }
}
