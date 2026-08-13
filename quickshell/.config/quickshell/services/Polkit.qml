// services/Polkit.qml — polkit authentication agent
// (Quickshell.Services.Polkit).
//
// Registers the agent on the session bus (path /org/quickshell/Polkit);
// polkitd routes authentication requests here. popups/PolkitDialog.qml
// reads `active` / `flow` and drives the conversation: submit() on Enter,
// cancel() on Esc / the cancel button.
//
// AuthFlow conversation (quickshell 0.3.0, verified against the source):
// a request arrives → agent.isActive, agent.flow set with message/icon;
// when polkitd wants input, flow.isResponseRequired becomes true with
// inputPrompt + responseVisible (echo). QML submits via flow.submit().
// A wrong password keeps the SAME flow object (a fresh session is started
// internally) with supplementaryMessage/supplementaryIsError updated and
// the `failed` flag set — the dialog clears its input and lets the user
// retry. Success or cancel ends the flow → agent.flow goes null.
pragma Singleton

import Quickshell
import Quickshell.Services.Polkit
import QtQuick

Singleton {
    id: root

    PolkitAgent {
        id: agent
        path: "/org/quickshell/Polkit"
    }

    readonly property bool active: agent.isActive
    readonly property bool registered: agent.isRegistered
    readonly property var flow: agent.flow

    // Conversation outcome logging (verification; the dialog reacts via
    // bindings on the flow's own properties/signals).
    //
    // NOTE: connections are made in JS on the flow object, NOT via a QML
    // Connections block: on SUCCESS the agent clears `flow` to null BEFORE
    // the signal is emitted (AuthFlow::completed → mRequest->complete →
    // finishAuthenticationRequest → bActiveFlow=null, then emit) — a
    // Connections.target binding would already be detached. Failure keeps
    // the flow alive (fresh session), so the failure path is unaffected.
    onFlowChanged: {
        const f = root.flow;
        if (!f) return;
        f.authenticationSucceeded.connect(() => console.log("[polkit] authentication succeeded"));
        f.authenticationFailed.connect(() => console.log("[polkit] authentication failed (retry)"));
        f.authenticationRequestCancelled.connect(() => console.log("[polkit] request cancelled"));
    }

    onRegisteredChanged: console.log("[polkit] agent registered: " + root.registered)
    onActiveChanged: console.log("[polkit] request active: " + root.active)

    /// Submit the user's response (typically the password).
    function submit(value: string): void {
        if (root.flow) root.flow.submit(value);
    }

    /// Cancel the ongoing request from the user side.
    function cancel(): void {
        if (root.flow) root.flow.cancelAuthenticationRequest();
    }
}
