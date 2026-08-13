// popups/PopupBackdrop.qml — fullscreen transparent click-catcher shown
// while a popup is open; pressing anywhere dismisses all popups.
//
// Must be instantiated as a per-screen Variants delegate (direct children
// of other windows don't map in 0.3.0). Created eagerly as a 0x0 window
// (lazy PanelWindow creation races), grown to fullscreen on show().
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services

PanelWindow {
    id: root

    required property var popupScreen

    screen: popupScreen
    color: "transparent"
    visible: true
    implicitWidth: 0
    implicitHeight: 0
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onPressed: PopupController.dismiss(root.popupScreen)
    }

    Component.onCompleted: PopupController.registerBackdrop(root.popupScreen, root)

    function show(): void {
        if (!root.popupScreen) return;
        root.implicitWidth = root.popupScreen.width;
        root.implicitHeight = root.popupScreen.height;
    }

    function hide(): void {
        root.implicitWidth = 0;
        root.implicitHeight = 0;
    }
}
