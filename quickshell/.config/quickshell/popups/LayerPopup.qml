// popups/LayerPopup.qml — popup window based on a layer-shell PanelWindow.
//
// Quickshell 0.3.0's PopupWindow is broken on wlr-layer-shell compositors
// ("Cannot attach popup ... as the popup is not an xdg_popup" — the surface
// is created as a layer surface and can never become an xdg_popup). Known
// issue, so popups are implemented as layer-shell panels instead.
//
// IMPORTANT: only windows created as Variants delegates (or file roots)
// map in 0.3.0 — direct children never do. Popups must be instantiated via
// Variants per screen and registered with PopupRegistry.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs
import qs.services

PanelWindow {
    id: root

    /// Type name used for registry lookup ("calendar", "audio", "power", ...)
    required property string popupType
    // The window's `screen` (inherited from QsWindow) identifies this popup's
    // screen; the Variants delegate assigns it.

    default property alias content: shell.content

    /// The inner PopupShell (content column). Accessible from subclasses.
    /// (Plain property, not an alias: aliases to ids are file-private.)
    property Item popupShell: shell

    anchors {
        top: true
        right: true
    }
    implicitWidth: 240
    color: "transparent"
    // Eager creation: 0.3.0 races lazy window creation, so popups are always
    // mapped and parked off-screen (topMargin -10000) until showAt repositions.
    visible: true

    // Don't reserve screen space and don't take keyboard focus (menus)
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Offset from the screen edges: right = bar + gap, top = computed on open
    property int topMargin: -10000
    margins {
        top: root.topMargin
        right: Theme.barWidth + Theme.spacing * 2
    }

    PopupShell {
        id: shell
        anchors.fill: parent
    }

    Component.onCompleted: {
        PopupRegistry.register(root.screen, root.popupType, root);
    }

    /// Open the popup centered vertically on the given screen Y coordinate
    /// (e.g. the widget's mapToGlobal(0, 0).y).
    function showAt(screenY: real): void {
        PopupRegistry.closeAll(root.screen);
        const sh = root.screen ? root.screen.height : 1080;
        root.topMargin = Math.max(4, Math.min(screenY - root.implicitHeight / 2,
                                              sh - root.implicitHeight - 4));
        root.visible = true;
        const bd = PopupRegistry.find(root.screen, "backdrop");
        if (bd) bd.show();
    }

    function hide(): void {
        if (root.topMargin < -1000) return; // already parked
        root.topMargin = -10000;
        const bd = PopupRegistry.find(root.screen, "backdrop");
        if (bd) bd.hide();
    }
}
