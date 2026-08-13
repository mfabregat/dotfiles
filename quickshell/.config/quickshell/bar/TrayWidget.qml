// bar/TrayWidget.qml — StatusNotifier tray items (max 4, clipped).
// Left click: activate · right click: native DBusMenu.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs

Item {
    id: root

    required property var barWindow

    readonly property int shown: Math.min(SystemTray.items.values.length, 4)

    width: 30
    // Layouts honor Layout.preferredHeight (bound `height` gets overridden)
    Layout.preferredHeight: shown * 30
    height: shown * 30
    clip: true // overflow (5+ items) is hidden, never overlaps the clock

    Column {
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: SystemTray.items

            delegate: Rectangle {
                required property var modelData
                readonly property bool canActivate: !modelData.onlyMenu

                width: 28
                height: 28
                radius: 6
                color: itemArea.containsMouse ? Theme.bgHover : "transparent"

                Image {
                    id: icon
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: modelData.icon
                    sourceSize { width: 16; height: 16 }
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    text: modelData.title ? modelData.title.charAt(0).toUpperCase() : "?"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu || !canActivate)
                                modelData.display(root.barWindow, width / 2, height / 2);
                            else
                                modelData.activate();
                        }
                    }
                    onPressed: (mouse) => {
                        if (mouse.button === Qt.RightButton)
                            modelData.display(root.barWindow, width / 2, height / 2);
                    }
                }
            }
        }
    }
}
