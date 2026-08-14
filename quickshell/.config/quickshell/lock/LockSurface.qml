// lock/LockSurface.qml — one full-screen surface per monitor (created by
// the WlSessionLock in Lock.qml when the session locks).
//
// Background: the same wallpaper swaybg paints (services/Wallpaper.qml),
// blurred with MultiEffect + a gruvbox dark overlay — no screencopy, so no
// capture warm-up races. Centered: lock glyph, clock/date (SystemClock),
// password field, status line.
//
// All surfaces share the `Pam` instance (buffer/failure/in-progress state),
// so every monitor shows the same state; the compositor routes keyboard
// input to the focused surface, whose field feeds the shared buffer.
import Quickshell
import QtQuick
import QtQuick.Effects
import qs
import qs.services

Item {
    id: root

    required property Pam pam

    // ── Background: blurred wallpaper ─────────────────────────────────
    Item {
        anchors.fill: parent

        // Render the image to a layer, then blur the layer (cheap: the
        // layer is static — the lock screen never animates).
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 0.4
            blurMax: 40
        }

        // Solid gruvbox base while the wallpaper decodes / if it's missing.
        Rectangle {
            anchors.fill: parent
            color: Theme.dark0
        }

        Image {
            anchors.fill: parent
            source: Wallpaper.url
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    // Gruvbox dark tint over the blur.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0x28 / 255, 0x28 / 255, 0x28 / 255, 0.55)
    }

    // ── Centered content ──────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        width: 360
        spacing: 32

        // Lock glyph + clock + date (tight inner spacing).
        Column {
            width: parent.width
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ""
                color: Theme.brightAqua
                font.family: Theme.fontFamily
                font.pixelSize: 40
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(clock.hours).padStart(2, "0") + ":" + String(clock.minutes).padStart(2, "0")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 88
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, d MMMM")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.letterSpacing
            }
        }

        // Password field
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320
            height: 44
            radius: Theme.radius
            color: Theme.dark1
            border.color: pwInput.activeFocus ? Theme.accent : Theme.dark2
            border.width: 1

            TextInput {
                id: pwInput
                anchors.fill: parent
                anchors.margins: 12
                verticalAlignment: Text.AlignVCenter
                focus: true
                enabled: !root.pam.unlockInProgress
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.dark0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                clip: true

                // Shared buffer: the focused surface types into
                // pam.currentText, every surface's field mirrors it
                // (value-equal writes don't loop).
                // NOTE: bare ids only — `root.pwInput` does NOT resolve
                // (ids aren't properties of the root object; verified
                // 2026-08-14 in a throwaway config).
                text: root.pam.currentText
                onTextChanged: root.pam.currentText = pwInput.text

                // Re-armed after a failed attempt (the field was disabled
                // during the PAM conversation).
                onEnabledChanged: {
                    if (pwInput.enabled) Qt.callLater(() => pwInput.forceActiveFocus());
                }

                Keys.onReturnPressed: (event) => { root.pam.tryUnlock(); event.accepted = true; }
                Keys.onEnterPressed: (event) => { root.pam.tryUnlock(); event.accepted = true; }
                Keys.onEscapePressed: (event) => {
                    root.pam.cancel();
                    event.accepted = true;
                }
            }
        }

        // Status line: hint / unlocking… / error (red)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pam.unlockInProgress ? "Unlocking…"
                : root.pam.failureText !== "" ? root.pam.failureText : "Enter password to unlock"
            color: root.pam.failureText !== "" ? Theme.urgent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: root.pam.failureText !== ""
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Clock only ticks while the session is locked — the surface only
    // exists then, so no extra bookkeeping is needed.
}
