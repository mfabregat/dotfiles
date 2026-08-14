// popups/ToggleSwitch.qml — gruvbox pill switch (control center, network
// sections). Parent binds `checked`; toggling emits `toggled(bool)`.
import QtQuick
import qs

Item {
    id: root

    property bool checked: false
    signal toggled(bool on)

    implicitWidth: 34
    implicitHeight: 18

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.dark2
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        id: knob
        width: 14
        height: 14
        radius: 7
        color: Theme.light0
        y: (parent.height - height) / 2
        x: root.checked ? parent.width - width - 2 : 2
        Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
}
