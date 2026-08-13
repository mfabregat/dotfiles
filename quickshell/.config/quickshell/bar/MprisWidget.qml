// bar/MprisWidget.qml — now playing (spotify preferred).
// Left click: play/pause · right click: next · middle click: open player.
// Title + artist read top-to-bottom; while playing the whole widget turns
// accent-colored (text flips to bg).
//
// NOTE: rotated items are positioned manually — QtQuick layouts mis-size
// rotated children (the unrotated box is laid out, then rotated around the
// origin, so the visual strip spans [x-height, x] × [y, y+width]).
import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    // Players list is passed in so the binding re-evaluates when players
    // appear/disappear (function calls alone are not tracked by QML).
    readonly property var player: pickPlayer(Mpris.players.values)
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: player !== null && player.isPlaying

    /// Vertical space between the workspaces block and the taskbar
    /// (computed in RightBar from the fixed siblings — non-circular).
    required property real freeSpace

    // Length limits: whole text up to the maximums; if it does not fit the
    // free space, shrink the title first (down to minTitleLen), then the
    // artist. All bindings are acyclic: freeSpace comes from the layout's
    // fixed siblings, never from this widget's own size.
    readonly property int maxTitleLen: 140
    readonly property int minTitleLen: 60
    readonly property int maxArtistLen: 80
    readonly property real titleNatural: Math.min(titleText.implicitWidth, maxTitleLen)
    readonly property real artistNatural: Math.min(artistText.implicitWidth, maxArtistLen)
    readonly property real availableLen: Math.max(0, root.freeSpace
        - 4 - iconText.implicitHeight - 3 - 2)

    readonly property real titleLen: root.titleNatural + root.artistNatural <= root.availableLen
        ? root.titleNatural
        : Math.min(Math.max(root.minTitleLen,
                            Math.min(root.titleNatural, root.availableLen - root.artistNatural)),
                   root.availableLen)
    readonly property real artistLen: root.titleNatural + root.artistNatural <= root.availableLen
        ? root.artistNatural
        : Math.max(0, Math.min(root.artistNatural, root.availableLen - root.titleLen))

    width: Theme.widgetWidth
    // Sized by the layout to exactly this (no fill, no loop)
    implicitHeight: 4 + iconText.implicitHeight + 3
        + root.titleLen + 2 + root.artistLen
    visible: hasPlayer
    radius: 7
    color: playing ? Theme.accent
         : area.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: 150 } }

    function pickPlayer(players: var): var {
        // Prefer spotify (matching the old waybar "player": "spotify")
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (p.dbusName.toLowerCase().includes("spotify")) return p;
        }
        // Otherwise the first playing player, else the first player
        for (let i = 0; i < players.length; i++)
            if (players[i].isPlaying) return players[i];
        return players.length > 0 ? players[0] : null;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 3

        Text {
            id: iconText
            Layout.alignment: Qt.AlignHCenter
            text: root.player ? (root.player.dbusName.toLowerCase().includes("spotify") ? "" : "") : ""
            color: root.playing ? Theme.bg : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // Strips area: title strip on top, artist strip below it, both
        // reading top-to-bottom (rotation 90). Manual positions — see note.
        Item {
            id: stripsItem
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: titleText
                rotation: 90
                transformOrigin: Item.TopLeft // rotate around the origin, not the center
                width: root.titleLen
                height: Theme.titleStrip
                x: 16 // visual strip centered (titleStrip 13 in a 22px widget)
                y: 0
                elide: Text.ElideRight
                text: root.player ? root.player.trackTitle || "" : ""
                color: root.playing ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                id: artistText
                rotation: 90
                transformOrigin: Item.TopLeft // rotate around the origin, not the center
                width: root.artistLen
                height: Theme.artistStrip
                x: 15 // visual strip centered (artistStrip 11)
                y: root.titleLen + 2 // follows the title length
                elide: Text.ElideRight
                text: root.player ? root.player.trackArtist || "" : ""
                color: root.playing ? Theme.bg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTiny
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        visible: root.hasPlayer
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                root.player.togglePlaying();
        }
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton && root.player.canGoNext)
                root.player.next();
            else if (mouse.button === Qt.MiddleButton)
                root.focusPlayerWindow();
        }
    }

    // Replaces the old player_focus.sh: raise the window via MPRIS and
    // focus it through sway (works even when raise() is unsupported).
    function focusPlayerWindow(): void {
        if (!root.player) return;
        if (root.player.canRaise) root.player.raise();

        const name = root.player.dbusName.split(".").pop();
        Quickshell.execDetached([
            "sh", "-c",
            `pgrep -x ${name} | head -1 | xargs -r -I{} swaymsg "[pid={}] focus" >/dev/null 2>&1`
        ]);
    }
}
