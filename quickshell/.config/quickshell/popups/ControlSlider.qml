// popups/ControlSlider.qml — gruvbox horizontal slider (control center).
// The parent binds `value` for the display position; user interaction
// emits `userSet(real)` live during the drag. While pressed the handle
// follows the mouse (dragValue) instead of the binding, so the slider
// never fights the parent's reactive updates mid-drag; after release the
// bound value takes over again.
import QtQuick
import qs

Item {
    id: root

    property real from: 0
    property real to: 100
    /// Display position (bound by the parent, e.g. from a service).
    property real value: 0
    /// True while the user is dragging.
    readonly property bool pressed: area.pressed
    /// Value at the current drag position (display while pressed).
    readonly property real dragValue: root.valueFromX(area.mouseX)

    signal userSet(real v)

    implicitWidth: 180
    implicitHeight: 20

    function valueFromX(x: real): real {
        const span = root.to - root.from;
        const frac = span === 0 ? 0
            : Math.max(0, Math.min(1, (x - 4) / Math.max(1, root.width - 8)));
        return root.from + frac * span;
    }

    // Track
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: 2
        color: Theme.dark2
    }

    // Fill (left of the handle center)
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: 2
        color: Theme.accent
        width: handle.x + handle.width / 2
    }

    // Handle
    Rectangle {
        id: handle
        width: 14
        height: 14
        radius: 7
        color: root.pressed ? Theme.fg : Theme.light0
        y: (parent.height - height) / 2
        x: {
            const span = root.to - root.from;
            const frac = span === 0 ? 0
                : (root.pressed ? root.dragValue : root.value - root.from) / span;
            return Math.max(0, Math.min(parent.width - width, frac * (parent.width - width)));
        }
        Behavior on x { enabled: !root.pressed; NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.userSet(root.dragValue)
        onPositionChanged: { if (pressed) root.userSet(root.dragValue); }
        onReleased: root.userSet(root.dragValue)
    }
}
