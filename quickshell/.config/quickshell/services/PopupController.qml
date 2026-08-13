// services/PopupController.qml — coordinates popups and the dismissal
// backdrop. sway gives xdg_popups no click-outside dismissal (no grab), so
// a fullscreen backdrop click-catcher handles it: opening a popup shows
// the backdrop for its screen; pressing anywhere dismisses everything.
//
// Note: popups are hidden by setting `visible` directly (never via their
// hide() — that would re-enter dismiss()).
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    property var popups: []    // [{ screen, win }]  — AnchoredPopup instances
    property var backdrops: [] // [{ screen, win }]  — PopupBackdrop instances

    function registerPopup(screen: var, win: var): void {
        root.popups.push({ screen: screen, win: win });
    }

    function registerBackdrop(screen: var, win: var): void {
        root.backdrops.push({ screen: screen, win: win });
    }

    /// Called when `win` opens: close other popups on the screen, show backdrop.
    function openPopup(screen: var, win: var): void {
        for (const p of root.popups) {
            if (p.screen === screen && p.win !== win) p.win.visible = false;
        }
        for (const b of root.backdrops) {
            if (b.screen === screen) b.win.show();
        }
    }

    /// Hide every popup and the backdrop on the given screen.
    function dismiss(screen: var): void {
        for (const p of root.popups) {
            if (p.screen === screen) p.win.visible = false;
        }
        for (const b of root.backdrops) {
            if (b.screen === screen) b.win.hide();
        }
    }
}
