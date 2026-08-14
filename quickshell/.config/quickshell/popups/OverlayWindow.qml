// popups/OverlayWindow.qml — fullscreen transparent overlay window base
// (the launcher pattern), shared by Launcher / NotificationCenter /
// ClipboardPopup / PolkitDialog. Per-screen instance (Variants delegate),
// only the focused monitor's is visible, exclusive keyboard grab, backdrop
// dismissal, Esc close.
//
// Subclasses bind `shown` to their service's open flag, connect
// `closeRequested`, set `focusTarget` (focused on open), and connect
// `opened` for per-open logic (clear search, reset selection, ...) — the
// base owns the onVisibleChanged plumbing so it can't be shadowed.
import Quickshell
import Quickshell.I3
import Quickshell.Wayland._WlrLayerShell
import QtQuick

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    /// Whether this overlay should be visible (usually the service's open
    /// flag). Combined with the focused-monitor check.
    property bool shown: false
    /// Item to focus when the overlay opens (deferred past surface
    /// mapping). null → the built-in focus catcher holds focus.
    property var focusTarget: null
    /// Whether clicking the backdrop emits closeRequested. Polkit sets
    /// this false — an auth prompt is modal.
    property bool dismissOnBackdrop: true
    /// Emitted on Esc or backdrop click; the subclass decides what that
    /// means (close the service, cancel the polkit flow, ...).
    signal closeRequested
    /// Emitted after the overlay becomes visible (post-mapping), so
    /// subclasses run per-open logic without overriding onVisibleChanged.
    signal opened

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Focused monitor's instance only. The I3.monitors.values guard makes
    // the binding track valuesChanged and re-run the lookup once sway IPC
    // connects (I3.monitorFor is a native method — its internals aren't
    // tracked by bindings; re-verified 2026-08-14 with a throwaway: the
    // unguarded call stays null forever).
    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: root.shown && root.i3Monitor !== null && root.i3Monitor.focused

    onVisibleChanged: {
        if (root.visible) {
            Qt.callLater(() => {
                if (root.focusTarget) root.focusTarget.forceActiveFocus();
                root.opened();
            });
        }
    }

    // Backdrop: click-away closes (disabled for modal dialogs — the
    // surface still swallows the click).
    MouseArea {
        anchors.fill: parent
        visible: root.dismissOnBackdrop
        onClicked: root.closeRequested()
    }

    // Esc closes (backstop — inputs that handle Esc themselves accept the
    // event before it reaches here).
    Item {
        id: focusCatcher
        focus: true

        Keys.onEscapePressed: {
            root.closeRequested();
            event.accepted = true;
        }
    }
}
