// bar/Taskbar.qml — all open windows across every output, from the native
// wlr-foreign-toplevel protocol (no swaymsg subprocesses).
// Click: activate · middle click: close (protocol requests).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups

Column {
    id: root

    spacing: 2

    Repeater {
        model: ToplevelManager.toplevels

        delegate: Rectangle {
            required property var modelData

            // Resolve the real icon name via the app's desktop entry.
            // The applications list is passed in so the binding re-evaluates
            // once the (async) desktop entry scan completes.
            readonly property var entry: findEntry(modelData.appId, DesktopEntries.applications.values)
            readonly property string iconName: entry && entry.icon ? entry.icon : (modelData.appId || "")

            function findEntry(appId: string, apps: var): var {
                if (!appId) return null;
                for (const a of apps) if (a.id === appId) return a;
                const lower = appId.toLowerCase();
                for (const a of apps)
                    if (a.id.toLowerCase().includes(lower) || lower.includes(a.id.toLowerCase())) return a;
                return null;
            }

            width: Theme.pillWidth
            height: Theme.pillWidth
            radius: 6
            color: area.containsMouse ? Theme.bgHover
                 : modelData.activated ? Theme.fgDim
                 : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }

            Image {
                id: icon
                anchors.centerIn: parent
                width: Theme.fontSizeGlyphs
                height: Theme.fontSizeGlyphs
                source: "image://icon/" + iconName
                sourceSize { width: Theme.fontSizeGlyphs; height: Theme.fontSizeGlyphs }
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !icon.visible
                text: modelData.appId ? modelData.appId.charAt(0).toUpperCase() : "?"
                color: modelData.activated ? Theme.dark0 : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        modelData.activate();
                }
                onPressed: (mouse) => {
                    PopupManager.hideOpen();
                    if (mouse.button === Qt.MiddleButton)
                        modelData.close();
                }
            }
        }
    }
}
