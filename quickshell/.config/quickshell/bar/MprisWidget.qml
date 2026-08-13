// bar/MprisWidget.qml — now playing (spotify preferred).
// Left click: play/pause · right click: next · middle click: focus window.
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

    width: 30
    height: hasPlayer ? 150 : 0
    visible: hasPlayer
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

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
        anchors.margins: 3
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.player ? (root.player.dbusName.toLowerCase().includes("spotify") ? "" : "") : ""
            color: root.player && root.player.isPlaying ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: 15
        }

        // Rotated track title (reads bottom-to-top, like the old bar)
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: true

            Text {
                id: titleText
                anchors.centerIn: parent
                rotation: -90
                width: 120
                height: 18
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: root.player ? root.player.trackTitle || "" : ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.player ? (root.player.isPlaying ? "" : "") : ""
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        visible: root.hasPlayer

        onClicked: root.player.togglePlaying()
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton && root.player.canGoNext)
                root.player.next();
            else if (mouse.button === Qt.MiddleButton)
                root.focusPlayerWindow();
        }
    }

    // Replaces the old player_focus.sh: try MPRIS raise(), fall back to
    // focusing the player process window via sway IPC.
    function focusPlayerWindow(): void {
        if (!root.player) return;
        if (root.player.canRaise) { root.player.raise(); return; }

        const name = root.player.dbusName.split(".").pop();
        Quickshell.execDetached([
            "sh", "-c",
            `pgrep -x ${name} | head -1 | xargs -r -I{} swaymsg "[pid={}] focus" >/dev/null 2>&1`
        ]);
    }
}
