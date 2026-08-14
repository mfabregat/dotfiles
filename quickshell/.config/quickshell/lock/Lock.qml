// lock/Lock.qml — session lock (ext-session-lock-v1) + IPC entry point.
//
// Instantiated once in shell.qml. The WlSessionLock stays `locked: false`
// at startup — the lock is only engaged on request (IPC / idle / power
// menu), so a quickshell restart never leaves the session locked behind a
// dead surface (restarting quickshell *while* locked is still unsafe: the
// compositor keeps the session locked — see the plan's phase-6 notes).
//
// The surface component (one instance per screen, created at lock time)
// renders the blurred wallpaper + password field; all surfaces share the
// single `Pam` instance below.
//
// Entry points:
//   - sway:        bindsym $mod+P exec quickshell ipc call lock lock
//   - swayidle:    timeout 300 'quickshell ipc call lock lock'
//   - power menu:  quickshell ipc call lock lock (popups/PowerMenu.qml)
//
// DPMS: turning it back on is swayidle's `resume` job (any unlock involves
// typing → input → resume → `swaymsg output "*" dpms on`). No spawn here.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs

Scope {
    id: root

    /// Whether the session is locked (drives WlSessionLock.locked).
    property bool locked: false

    // Target-state logging (setLocked(true) doesn't emit lockStateChanged,
    // so log on the property instead — covers IPC lock/unlock AND the PAM
    // unlock path symmetrically; the compositor-side confirmation comes
    // from onSecureStateChanged).
    onLockedChanged: console.log("[lock] state: " + (root.locked ? "locked" : "unlocked"))

    WlSessionLock {
        id: lock

        locked: root.locked
        onSecureStateChanged: console.log("[lock] compositor secure: " + lock.secure)

        WlSessionLockSurface {
            // Opaque base (doc: transparent lock surfaces are unreliable);
            // LockSurface paints the blurred wallpaper over it.
            color: Theme.dark0

            LockSurface {
                anchors.fill: parent
                pam: auth
            }
        }
    }

    // Password authentication (custom pam.d service — see lock/Pam.qml).
    // NOTE: id must NOT collide with LockSurface's `required property pam`
    // — inside the surface Component, a same-named initializer would resolve
    // to the instance's own unset property instead of this id (verified
    // 2026-08-14: binding loop + null pam; distinct names resolve fine).
    Pam {
        id: auth

        onUnlocked: root.locked = false
    }

    // IPC entry point: quickshell ipc call lock lock|unlock|isLocked
    IpcHandler {
        target: "lock"

        function lock(): void { root.locked = true; }
        function unlock(): void { root.locked = false; }
        function isLocked(): bool { return root.locked; }
    }
}
