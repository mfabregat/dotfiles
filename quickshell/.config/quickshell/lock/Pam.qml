// lock/Pam.qml — password authentication for the lock screen.
//
// Wraps a PamContext with a *custom* PAM service (`passwd` under
// lock/assets/pam.d) so no system PAM edits are needed and — deliberately —
// pam_faillock is NOT in the chain: a wrong password on the lock screen can
// never lock the account for 10 minutes (the system-auth chain would). The
// custom service is `auth required pam_unix.so` (password only, no
// fingerprint), matching the plan.
//
// This component is instantiated once inside Lock.qml and shared by every
// per-screen LockSurface: `currentText` / `unlockInProgress` / `showFailure`
// are the single source of truth so all monitors show the same state.
import Quickshell
import Quickshell.Services.Pam
import QtQuick

Scope {
    id: root

    /// The unlock request succeeded — Lock.qml drops the WlSessionLock.
    signal unlocked()

    /// Shared password buffer (mirrored by every surface's input field).
    property string currentText: ""
    property bool unlockInProgress: false
    /// A failed attempt (wrong password / PAM error).
    property bool showFailure: false
    /// PAM's last message, e.g. the unix_chkpwd "password incorrect" note.
    property string pamMessage: ""
    readonly property bool active: pam.active

    // Typing again clears the failure state (swaylock-style).
    onCurrentTextChanged: root.showFailure = false

    /// Start the PAM conversation with the buffered password.
    function tryUnlock(): void {
        if (root.unlockInProgress) return;
        if (root.currentText.length === 0) return;
        root.unlockInProgress = true;
        pam.start();
    }

    /// Abort an in-flight conversation (Esc on the lock screen).
    function cancel(): void {
        if (pam.active) pam.abort();
        root.unlockInProgress = false;
    }

    /// Clear the buffer (Esc with nothing in flight).
    function clear(): void {
        root.currentText = "";
        root.showFailure = false;
    }

    PamContext {
        id: pam

        // Bundled service file: lock/assets/pam.d/passwd. Quickshell.shellPath
        // resolves against the config root; pam_start_confdir uses ONLY this
        // directory (no fallback to /etc/pam.d), so the file must exist.
        config: "passwd"
        configDirectory: Quickshell.shellPath("lock/assets/pam.d")

        // pam_unix asks for the password exactly once per conversation:
        // respond with the buffered text (the buffer is cleared on
        // completion, not here — keep it for any follow-up prompt).
        // (bare `pam.` — ids don't resolve via `root.<id>`; verified
        // 2026-08-14 in a throwaway config)
        onPamMessage: {
            root.pamMessage = pam.message;
            if (pam.responseRequired) {
                pam.respond(root.currentText);
            }
        }

        onCompleted: result => {
            root.unlockInProgress = false;
            root.currentText = "";
            if (result === PamResult.Success) {
                root.pamMessage = "";
                root.showFailure = false;
                root.unlocked();
            } else if (result === PamResult.MaxTries) {
                root.pamMessage = "Too many attempts";
                root.showFailure = true;
            } else {
                root.pamMessage = "Incorrect password";
                root.showFailure = true;
            }
        }

        onError: err => {
            root.unlockInProgress = false;
            root.pamMessage = "Authentication error";
            root.showFailure = true;
        }
    }
}
