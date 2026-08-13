// bar/TrayWidget.qml — StatusNotifier tray items.
// Left click: activate · right click: native DBusMenu.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs

Item {
    id: root

    required property var barWindow

    width: 30
    height: Math.min(Math.max(trayCol.implicitHeight, 0), 150)

    Column {
        id: trayCol
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

                    onClicked: {
                        if (modelData.onlyMenu || !canActivate)
                            modelData.display(root.barWindow, width / 2, height / 2);
                        else
                            modelData.activate();
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
