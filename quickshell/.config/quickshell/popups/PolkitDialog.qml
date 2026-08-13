// popups/PolkitDialog.qml — authentication prompt, one fullscreen window
// per screen (Variants in shell.qml); only the focused monitor's instance
// is visible (launcher pattern: exclusive keyboard grab powers typing and
// Esc while open). The fullscreen transparent surface also swallows clicks
// (no backdrop handler) — a modal auth prompt, like polkit-gnome.
//
// AuthFlow conversation (see services/Polkit.qml): Enter submits via
// flow.submit(); a failed attempt keeps the SAME flow alive (new session
// started internally) with the error in supplementaryMessage — the input
// is cleared and refocused for the retry. Success / cancel ends the flow
// → agent.flow goes null → Polkit.active false → the dialog hides itself.
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

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Focused monitor's instance only (launcher pattern; the monitors
    // guard tracks valuesChanged and re-runs the lookup once sway IPC
    // connects — I3.monitorFor's internals aren't tracked by bindings).
    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: Polkit.active && root.i3Monitor !== null && root.i3Monitor.focused

    // Live flow reference — bindings re-evaluate when the agent replaces
    // or clears it (never cache the flow object).
    readonly property var flow: Polkit.flow

    function doSubmit(): void {
        if (!root.flow || !root.flow.isResponseRequired) return;
        Polkit.submit(pwInput.text);
    }

    function doCancel(): void {
        if (root.flow) Polkit.cancel();
    }

    // Fresh prompt (or focus moved to this screen's instance): clear the
    // previous attempt and grab keyboard focus (deferred so the layer
    // surface is mapped first).
    onVisibleChanged: {
        if (root.visible) {
            pwInput.text = "";
            Qt.callLater(() => pwInput.forceActiveFocus());
        }
    }

    // A failed attempt reuses the same flow with a fresh session: clear
    // the input and refocus for the retry.
    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            pwInput.text = "";
            Qt.callLater(() => pwInput.forceActiveFocus());
        }
    }

    // ── Helpers (identity objects aren't QML-registered — guard) ───────
    function identityLabel(ident: var): string {
        if (!ident) return "";
        try { return ident.displayName || ident.string || String(ident.id); }
        catch (e) { return ""; }
    }

    function identitySub(ident: var): string {
        if (!ident) return "";
        try { return ident.isGroup ? "group" : "user"; }
        catch (e) { return ""; }
    }

    function isSelected(ident: var): bool {
        const sel = root.flow ? root.flow.selectedIdentity : null;
        if (!ident || !sel) return false;
        try { return ident === sel || ident.id === sel.id; }
        catch (e) { return false; }
    }

    // ── Card ───────────────────────────────────────────────────────────
    PopupShell {
        id: card
        anchors.centerIn: parent
        width: 420

        Column {
            width: parent.width
            spacing: 10

            // Header: app/policy icon + message
            Row {
                width: parent.width
                spacing: 12

                Item {
                    width: 40
                    height: 40

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: Theme.brightYellow
                        font.family: Theme.fontFamily
                        font.pixelSize: 24
                        visible: !appIcon.visible
                    }

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: root.flow && root.flow.iconName
                            ? Quickshell.iconPath(root.flow.iconName) : ""
                        sourceSize { width: 40; height: 40 }
                        visible: status === Image.Ready
                    }
                }

                Text {
                    width: parent.width - 52
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.flow ? root.flow.message : ""
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    wrapMode: Text.Wrap
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Prompt / waiting state
            Text {
                width: parent.width
                text: root.flow && root.flow.isResponseRequired
                    ? (root.flow.inputPrompt !== "" ? root.flow.inputPrompt : "Enter your password:")
                    : "Authenticating…"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            // Response input (hidden while no response is required)
            Rectangle {
                width: parent.width
                height: 34
                radius: Theme.radius
                color: Theme.dark1
                border.color: pwInput.activeFocus ? Theme.accent : Theme.dark2
                border.width: 1
                visible: root.flow && root.flow.isResponseRequired

                TextInput {
                    id: pwInput
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: Text.AlignVCenter
                    focus: true // re-arms on every show; forceActiveFocus confirms
                    echoMode: root.flow && root.flow.responseVisible
                        ? TextInput.Normal : TextInput.Password
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.dark0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    clip: true

                    Keys.onEscapePressed: (event) => { root.doCancel(); event.accepted = true; }
                    Keys.onReturnPressed: (event) => { root.doSubmit(); event.accepted = true; }
                    Keys.onEnterPressed: (event) => { root.doSubmit(); event.accepted = true; }
                }
            }

            // Supplementary message: errors after a failed attempt, or info
            Text {
                width: parent.width
                visible: root.flow && root.flow.supplementaryMessage !== ""
                text: root.flow ? root.flow.supplementaryMessage : ""
                color: root.flow && root.flow.supplementaryIsError ? Theme.urgent : Theme.fgDim
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // Identity selector — only when polkitd offers more than one.
            // (Inline delegate: `modelData` must be resolved here — plan
            // landmine 14.)
            Column {
                width: parent.width
                spacing: 4
                visible: root.flow && root.flow.identities
                    && root.flow.identities.length > 1

                Text {
                    text: "Authenticate as"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: Theme.letterSpacing
                }

                Repeater {
                    model: root.flow ? root.flow.identities : []

                    delegate: Rectangle {
                        property var identity: modelData

                        readonly property bool selected: root.isSelected(identity)

                        width: parent.width
                        height: Theme.popupRowHeight
                        radius: Theme.radius
                        color: rowArea.containsMouse ? Theme.bgHover
                             : selected ? Theme.dark2 : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.identityLabel(identity)
                            color: selected ? Theme.fg : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.identitySub(identity)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                // Changing the identity aborts the current
                                // conversation and starts a new one.
                                if (root.flow) root.flow.selectedIdentity = identity;
                            }
                        }
                    }
                }
            }

            // Actions
            Row {
                anchors.right: parent.right
                spacing: 8

                ActionButton {
                    text: "Cancel"
                    onClicked: root.doCancel()
                }

                ActionButton {
                    text: "OK"
                    enabled: root.flow && root.flow.isResponseRequired
                    onClicked: root.doSubmit()
                }
            }
        }
    }

    // ── Small styled button (PowerMenu row pattern) ────────────────────
    component ActionButton: Rectangle {
        id: btn

        property string text: ""
        property bool enabled: true
        signal clicked

        width: 88
        height: 30
        radius: Theme.radius
        color: btnArea.containsMouse && btn.enabled ? Theme.bgHover : Theme.dark1
        border.color: Theme.dark2
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }
        opacity: btn.enabled ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: btn.text
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { if (btn.enabled) btn.clicked(); }
        }
    }
}
