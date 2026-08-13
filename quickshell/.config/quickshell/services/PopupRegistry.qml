// services/PopupRegistry.qml — routes popup windows to their screen.
// Popup windows are per-screen Variants delegates; widgets look up the
// popup for their own screen at click time.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    property var popups: [] // [{ screen, type, window }]

    function register(screen: var, type: string, win: var): void {
        root.popups.push({ screen: screen, type: type, win: win });
    }

    function find(screen: var, type: string): var {
        for (const p of root.popups) {
            if (p.type === type && p.screen === screen) return p.win;
        }
        return null;
    }

    function closeAll(screen: var): void {
        for (const p of root.popups) {
            if (p.screen === screen && p.win.visible) p.win.hide();
        }
    }
}
