// lock/Pam.qml — password authentication for the lock screen.
//
// Wraps a PamContext with a *custom* PAM service (`passwd` under
// lock/assets/pam.d) so no system PAM edits are needed and — deliberately —
// pam_faillock is NOT in the chain: a wrong password on the lock screen can
// never lock the account for 10 minutes (the system-auth chain would). The
// custom service is `auth required pam_unix.so` (password only, no
// fingerprint), matching the plan.
//
// Instantiated once inside Lock.qml and shared by every per-screen
// LockSurface: `currentText` / `unlockInProgress` / `failureText` are the
// single source of truth so all monitors show the same state.
//
// Conversation lifecycle (verified in the 0.3.0 source): pam.start() spawns
// a fresh subprocess; pam_unix prompts once for the password (pamMessage,
// responseRequired) and respond() feeds it back. On completion the
// conversation is torn down (`conversation = null`), so a failed attempt
// can simply start() again. abort() (Esc) SIGKILLs the subprocess and
// emits nothing — no spurious failure state. Errors emit `error` AND then
// `completed(Error)` — handle Error in onCompleted only.
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
    /// Failure/error message to show in red ("" = no failure).
    property string failureText: ""

    // Typing again clears the failure state (swaylock-style).
    onCurrentTextChanged: root.failureText = ""

    /// Start the PAM conversation with the buffered password.
    function tryUnlock(): void {
        if (root.unlockInProgress || root.currentText.length === 0) return;
        root.failureText = "";
        root.unlockInProgress = true;
        pam.start();
    }

    /// Abort an in-flight conversation and clear the buffer (Esc).
    function cancel(): void {
        if (pam.active) pam.abort();
        root.unlockInProgress = false;
        root.currentText = "";
        root.failureText = "";
    }

    PamContext {
        id: pam

        // Bundled service file: lock/assets/pam.d/passwd. Quickshell.shellPath
        // resolves against the config root; pam_start_confdir uses ONLY this
        // directory (no fallback to /etc/pam.d), so the file must exist.
        config: "passwd"
        configDirectory: Quickshell.shellPath("lock/assets/pam.d")

        // pam_unix asks for the password exactly once per conversation:
        // respond with the buffered text (cleared on completion).
        // (bare `pam.` — ids don't resolve via `root.<id>`; verified
        // 2026-08-14 in a throwaway config)
        onPamMessage: {
            if (pam.responseRequired) pam.respond(root.currentText);
        }

        onCompleted: result => {
            root.unlockInProgress = false;
            root.currentText = "";
            if (result === PamResult.Success) {
                root.failureText = "";
                root.unlocked();
            } else if (result === PamResult.MaxTries) {
                root.failureText = "Too many attempts";
            } else if (result === PamResult.Error) {
                root.failureText = "Authentication error";
            } else {
                root.failureText = "Incorrect password";
            }
        }
    }
}
