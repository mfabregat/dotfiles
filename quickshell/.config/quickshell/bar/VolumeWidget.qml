// bar/VolumeWidget.qml — default sink volume/mute (Pipewire).
// Left click: mute · right click: audio menu · scroll: volume.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    required property var audioMenu

    readonly property var node: Pipewire.defaultAudioSink
    readonly property bool hasNode: node !== null
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property bool muted: node && node.audio ? node.audio.muted : false

    width: Theme.widgetWidth
    height: Theme.unit * 10
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    // Bind the default sink so volume/mute become writable and reactive
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: !root.hasNode ? "" : root.muted ? "" : ""
            color: root.muted ? Theme.urgent : (root.volume > 0.5 ? Theme.fg : Theme.fgDim)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.hasNode ? Math.round(root.volume * 100) + "%" : ""
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton // right = device menu

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton && root.node && root.node.audio)
                root.node.audio.muted = !root.node.audio.muted;
        }
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.audioMenu.showAt(root);
        }
        onWheel: (wheel) => {
            if (!root.node || !root.node.audio) return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            root.node.audio.volume = Math.min(1, Math.max(0, root.volume + step));
        }
    }
}
