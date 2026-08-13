// bar/TrayWidget.qml — StatusNotifier tray items (max 4, clipped).
// Left click: activate · right click: native DBusMenu.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import qs
import qs.popups

Item {
    id: root

    required property var barWindow

    readonly property int shown: Math.min(SystemTray.items.values.length, 4)

    width: Theme.widgetWidth
    // Sized by `height`: the parent is a plain Column (not a Layout), so
    // Layout.preferredHeight would be ignored here.
    height: shown * 23
    clip: true // overflow (5+ items) is hidden, never overlaps the clock

    Column {
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: SystemTray.items

            delegate: Rectangle {
                required property var modelData
                readonly property bool canActivate: !modelData.onlyMenu

                width: Theme.pillWidth
                height: Theme.pillWidth
                radius: 6
                color: itemArea.containsMouse ? Theme.bgHover : "transparent"

                Image {
                    id: icon
                    anchors.centerIn: parent
                    width: Theme.fontSizeGlyphs
                    height: Theme.fontSizeGlyphs
                    source: modelData.icon
                    sourceSize { width: Theme.fontSizeGlyphs; height: Theme.fontSizeGlyphs }
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    text: modelData.title ? modelData.title.charAt(0).toUpperCase() : "?"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    function showMenu(): void {
                        // position is relative to the bar window
                        const pos = root.mapToItem(root.barWindow.contentItem, 0, 0);
                        modelData.display(root.barWindow, pos.x + width / 2, pos.y + height / 2);
                    }

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu || !canActivate) showMenu();
                            else modelData.activate();
                        }
                    }
                    onPressed: (mouse) => {
                        PopupManager.hideOpen();
                        if (mouse.button === Qt.RightButton) showMenu();
                    }
                }
            }
        }
    }
}
