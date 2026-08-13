// popups/PopupManager.qml — tracks the currently open popup so any bar
// interaction can dismiss it deterministically. Native dismissal (xdg
// grab via grabFocus) is compositor-dependent; this is the app-side
// counterpart: at most one popup open at a time, bar presses close it.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    /// The AnchoredPopup currently open, or null.
    property var openPopup: null

    /// Open `popup` (closing whatever was open). Toggles closed if it is
    /// already the open one.
    function open(popup: var): void {
        if (root.openPopup === popup) {
            root.hideOpen();
            return;
        }
        if (root.openPopup) root.openPopup.hide();
        root.openPopup = popup;
    }

    /// Close the open popup, if any.
    function hideOpen(): void {
        if (!root.openPopup) return;
        const popup = root.openPopup;
        root.openPopup = null;
        popup.hide();
    }

    /// Called by popups when they close for any reason (hide(), native
    /// dismissal, hover-exit) so the registry never goes stale.
    function closed(popup: var): void {
        if (root.openPopup === popup) root.openPopup = null;
    }
}
