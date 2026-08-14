// popups/ScreenshotPicker.qml — drag-to-select screenshot picker (grim
// backend). One fullscreen window per screen; every instance shows while
// Screenshot.open is true (the drag happens on whichever screen the mouse
// is on; a click captures that screen fullscreen). The focused monitor's
// instance grabs the keyboard (Esc cancels).
//
// Capture ordering (verified 2026-08-14): grim composites layer-shell
// surfaces, so the picker windows are hidden BEFORE the capture runs —
// services/Screenshot.qml sets open=false first and re-opens the picker
// if the capture fails.
import Quickshell
import Quickshell.I3
import Quickshell.Wayland._WlrLayerShell
import QtQuick
import qs
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    readonly property bool focused: root.i3Monitor !== null && root.i3Monitor.focused

    WlrLayershell.keyboardFocus: root.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: Screenshot.open && root.i3Monitor !== null

    // ── Selection state (window-local coords) ─────────────────────────
    property real sx: 0
    property real sy: 0
    property real ex: 0
    property real ey: 0
    readonly property real rsx: Math.min(root.sx, root.ex)
    readonly property real rsy: Math.min(root.sy, root.ey)
    readonly property real sw: Math.abs(root.sx - root.ex)
    readonly property real sh: Math.abs(root.sy - root.ey)
    readonly property bool selecting: root.sw > 3 || root.sh > 3

    onVisibleChanged: {
        if (root.visible) {
            root.sx = root.sy = root.ex = root.ey = 0;
            Qt.callLater(() => catcher.forceActiveFocus());
        }
    }

    // ── Interaction ────────────────────────────────────────────────────
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.CrossCursor

        onPressed: {
            root.sx = mouse.x;
            root.sy = mouse.y;
            root.ex = mouse.x;
            root.ey = mouse.y;
        }
        onPositionChanged: {
            if (pressed) {
                root.ex = mouse.x;
                root.ey = mouse.y;
            }
        }
        onReleased: {
            if (root.selecting) {
                Screenshot.captureRect(root.rsx, root.rsy, root.sw, root.sh, root.screen);
            } else {
                // Click (no drag): capture this screen fullscreen.
                Screenshot.captureRect(0, 0, root.screen.width, root.screen.height, root.screen);
            }
        }
    }

    // Esc cancels (only the focused instance receives keys).
    Item {
        id: catcher
        focus: true

        Keys.onEscapePressed: {
            Screenshot.open = false;
            event.accepted = true;
        }
    }

    // ── Visuals ────────────────────────────────────────────────────────
    // Dim outside the selection: four rectangles around it (no layer
    // masks — the same visual effect, cheap). The picker hides before the
    // capture, so none of this ever appears in the shot.
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.45)
        x: 0; y: 0
        width: root.width
        height: root.rsy
        visible: root.selecting
    }
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.45)
        x: 0; y: root.rsy + root.sh
        width: root.width
        height: Math.max(0, root.height - root.rsy - root.sh)
        visible: root.selecting
    }
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.45)
        x: 0; y: root.rsy
        width: root.rsx
        height: root.sh
        visible: root.selecting
    }
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.45)
        x: root.rsx + root.sw; y: root.rsy
        width: Math.max(0, root.width - root.rsx - root.sw)
        height: root.sh
        visible: root.selecting
    }

    // Selection border + size label
    Rectangle {
        x: root.rsx
        y: root.rsy
        width: root.sw
        height: root.sh
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
        radius: 2
        visible: root.selecting
    }

    Text {
        x: root.rsx
        y: Math.max(4, root.rsy - 20)
        visible: root.selecting
        text: Math.round(root.sw) + "×" + Math.round(root.sh)
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
    }

    // Hint (top center, on a readable pill)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        height: hint.implicitHeight + 12
        width: hint.implicitWidth + 24
        radius: 8
        color: Theme.bg
        border.color: Theme.dark2
        border.width: 1

        Text {
            id: hint
            anchors.centerIn: parent
            text: "Drag to select · click = fullscreen · Esc = cancel"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
