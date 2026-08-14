// bar/MprisWidget.qml — now playing (spotify preferred, browsers ignored).
// Left click: play/pause · right click: next · middle click: open player.
// Title + artist read top-to-bottom; while playing the whole widget turns
// accent-colored (text flips to bg).
//
// NOTE: rotated items are positioned manually — QtQuick layouts mis-size
// rotated children (the unrotated box is laid out, then rotated around the
// origin, so the visual strip spans [x-height, x] × [y, y+width]).
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups

Rectangle {
    id: root

    // Players list is passed in so the binding re-evaluates when players
    // appear/disappear — reading `.values` (a tracked property) inside the
    // JS function keeps it reactive (native method internals aren't
    // tracked; QML JS function calls are).
    readonly property var player: pickPlayer(Mpris.players.values)
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: player !== null && player.isPlaying

    /// Vertical space between the workspaces block and the taskbar
    /// (computed in RightBar from the fixed siblings — non-circular).
    required property real freeSpace

    // Length limits: whole text up to the maximums; if it does not fit the
    // free space, shrink the title first, then the artist. All bindings
    // are acyclic: freeSpace comes from the layout's fixed siblings, never
    // from this widget's own size.
    readonly property int maxTitleLen: 180
    readonly property int maxArtistLen: 180
    // Extra empty space below the artist strip; counted in both availableLen
    // and implicitHeight so the widget never exceeds its freeSpace cap.
    readonly property real bottomPad: Theme.spacing
    readonly property real titleNatural: Math.min(titleText.implicitWidth, maxTitleLen)
    readonly property real artistNatural: Math.min(artistText.implicitWidth, maxArtistLen)
    readonly property real availableLen: Math.max(0, root.freeSpace
        - 4 - iconText.implicitHeight - 3 - 2 - dashText.height - 2 - root.bottomPad)

    readonly property real titleLen: root.titleNatural + root.artistNatural <= root.availableLen
        ? root.titleNatural
        : Math.min(root.titleNatural, root.availableLen - root.artistNatural)
    readonly property real artistLen: root.titleNatural + root.artistNatural <= root.availableLen
        ? root.artistNatural
        : Math.max(0, Math.min(root.artistNatural, root.availableLen - root.titleLen))

    width: Theme.widgetWidth
    // Sized by the layout to exactly this (no fill, no loop)
    implicitHeight: 4 + iconText.implicitHeight + 3
        + root.titleLen + 2 + dashText.height + 2 + root.artistLen + root.bottomPad
    visible: hasPlayer
    radius: 7
    color: playing ? Theme.accent
         : area.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: 150 } }

    // Browsers register an MPRIS player for tab audio (YouTube etc.); the
    // widget should only show real players, so exclude them here.
    function isBrowserPlayer(p: var): bool {
        const hay = ((p.dbusName || "") + " " + (p.desktopEntry || "") + " "
            + (p.identity || "")).toLowerCase();
        return /(?:^|[._ -])(?:firefox|chromium|chrome|brave|vivaldi|edge|opera|epiphany|qutebrowser|falkon|konqueror|webkit2|webkitgtk)(?:[._ -]|$)/
            .test(hay);
    }

    function pickPlayer(players: var): var {
        // Prefer spotify (matching the old waybar "player": "spotify")
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (isBrowserPlayer(p)) continue;
            if (p.dbusName.toLowerCase().includes("spotify")) return p;
        }
        // Otherwise the first playing player, else the first player
        for (let i = 0; i < players.length; i++) {
            if (isBrowserPlayer(players[i])) continue;
            if (players[i].isPlaying) return players[i];
        }
        for (let i = 0; i < players.length; i++)
            if (!isBrowserPlayer(players[i])) return players[i];
        return null;
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
            font.pixelSize: Theme.fontSizeGlyphs
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // Strips area: title strip on top, artist strip below it, both
        // reading top-to-bottom (rotation 90). Both strips center
        // automatically: a TopLeft-rotated text's visual strip spans
        // [x-height, x], so x = (parent.width + height) / 2 centers it
        // with no explicit dimensions (strip width = the font line height).
        Item {
            id: stripsItem
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: titleText
                rotation: 90
                transformOrigin: Item.TopLeft // rotate around the origin, not the center
                width: root.titleLen
                x: Math.ceil((parent.width + height) / 2)
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
                x: Math.ceil((parent.width + height) / 2)
                y: root.titleLen + 2 + dashText.height + 2 // follows title + dash
                elide: Text.ElideRight
                text: root.player ? root.player.trackArtist || "" : ""
                color: root.playing ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize // same size as the title
                Behavior on color { ColorAnimation { duration: 150 } }
                font.bold: true
            }

            Text {
                id: dashText
                rotation: 90
                text: "-"
                color: root.playing ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                x: Math.ceil((parent.width - width) / 2)
                y: Math.ceil(root.titleLen + 2)
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
            PopupManager.hideOpen();
            if (mouse.button === Qt.RightButton && root.player.canGoNext)
                root.player.next();
            else if (mouse.button === Qt.MiddleButton)
                root.focusPlayerWindow();
        }
    }


    // Replaces the old player_focus.sh: raise via MPRIS, then focus the
    // matching toplevel through wlr-foreign-toplevel (native, no
    // pgrep/swaymsg subprocess). Match the player's desktopEntry against
    // the toplevel's appId (exact first, then substring both ways).
    function focusPlayerWindow(): void {
        if (!root.player) return;
        if (root.player.canRaise) root.player.raise();

        const appId = (root.player.desktopEntry || "").toLowerCase();
        if (!appId) return;
        const tops = ToplevelManager.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const tid = (tops[i].appId || "").toLowerCase();
            if (tid === appId || tid.includes(appId) || appId.includes(tid)) {
                tops[i].activate();
                return;
            }
        }
    }
}
