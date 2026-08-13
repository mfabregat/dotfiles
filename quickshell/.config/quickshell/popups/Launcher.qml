// popups/Launcher.qml — application launcher (drun), one fullscreen window
// per screen; only the focused monitor's instance is visible.
//
// Toggled from sway: `quickshell ipc call launcher toggle` ($mod+d).
// Fuzzy search over desktop entries (name / generic / keywords / exec);
// Enter launches the selection, Esc closes, clicking outside closes.
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

    // Fullscreen transparent surface: the backdrop catches click-away and
    // exclusive keyboard focus powers typing + Esc while open (unmapped
    // when hidden, so focus returns to the session). Only the centered
    // card is drawn (rofi-like, no dim).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Focused monitor's launcher only. The I3.monitors.values guard makes
    // the lookup re-run once sway IPC connects (a bare function call in a
    // binding would evaluate once, to null — landmine 2 in the plan).
    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: LauncherState.open && root.i3Monitor !== null && root.i3Monitor.focused

    // Both arguments are tracked properties, so this re-evaluates on every
    // keystroke and once the (async) desktop entry scan completes.
    property var results: buildResults(searchInput.text, DesktopEntries.applications.values)

    function launchSelected(): void {
        const hit = root.results[resultsList.currentIndex];
        if (!hit) return;
        hit.entry.execute();
        LauncherState.open = false;
    }

    /// Move the selection by `delta` rows (clamped). The results ListView
    /// follows via highlightFollowsCurrentItem.
    function moveSelection(delta: int): void {
        if (root.results.length === 0) return;
        resultsList.currentIndex = Math.max(0,
            Math.min(resultsList.currentIndex + delta, root.results.length - 1));
    }

    // Fresh open: clear the previous query, select the top result, and grab
    // keyboard focus (deferred so the layer surface is mapped first).
    onVisibleChanged: {
        if (root.visible) {
            searchInput.text = "";
            resultsList.currentIndex = 0;
            Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    // Results rebuilt (every keystroke): selection returns to the top.
    onResultsChanged: {
        resultsList.currentIndex = 0;
    }

    // ── Backdrop + centered card ──────────────────────────────
    MouseArea {
        id: backdrop
        anchors.fill: parent
        onClicked: LauncherState.open = false
    }

    PopupShell {
        id: card
        anchors.centerIn: parent
        width: 400

        // Search row: glyph · input · clear (anchors-based so the input
        // spans the gap and the clear button can appear/disappear).
        Item {
            width: parent.width
            implicitHeight: 32

            Text {
                id: searchGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
            }

            TextInput {
                id: searchInput
                anchors.left: searchGlyph.right
                anchors.leftMargin: 8
                anchors.right: clearBtn.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                focus: true // re-arms on every show; forceActiveFocus confirms
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.dark0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                clip: true

                Keys.onEscapePressed: { LauncherState.open = false; event.accepted = true; }
                Keys.onUpPressed: { root.moveSelection(-1); event.accepted = true; }
                Keys.onDownPressed: { root.moveSelection(1); event.accepted = true; }
                Keys.onReturnPressed: { root.launchSelected(); event.accepted = true; }
                Keys.onEnterPressed: { root.launchSelected(); event.accepted = true; }
            }

            Text {
                id: clearBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                text: "×"
                visible: searchInput.text.length > 0
                color: clearArea.containsMouse ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: searchInput.text = ""
                }
            }
        }

        // Results — at most 8 rows visible; the card shrinks with fewer.
        // Native ListView: lazily instantiates rows, wheel-scrolls, and
        // follows the selection (highlightFollowsCurrentItem).
        // NOTE: no `required property var modelData` here — declaring it
        // kills the `index` context property in this quickshell/Qt combo
        // (verified 2026-08-13); implicit modelData + index work fine.
        ListView {
            id: resultsList
            width: parent.width
            height: Math.min(root.results.length, 8) * Theme.popupRowHeight
            model: root.results
            clip: true
            highlightFollowsCurrentItem: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                readonly property var entry: modelData.entry
                readonly property bool selected: ListView.isCurrentItem

                width: resultsList.width
                height: Theme.popupRowHeight
                radius: Theme.radius
                color: selected ? Theme.accent : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Image {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    source: "image://icon/" + (entry.icon || "")
                    sourceSize { width: 20; height: 20 }
                    visible: status === Image.Ready
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.right: genericText.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.name
                    color: selected ? Theme.dark0 : Theme.fg
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    id: genericText
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.genericName
                    color: selected ? Theme.dark0 : Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: resultsList.currentIndex = index
                    onClicked: {
                        resultsList.currentIndex = index;
                        root.launchSelected();
                    }
                }
            }
        }

        // Empty state
        Text {
            width: parent.width
            visible: root.results.length === 0
            text: "No matches"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }

        // Footer hint
        Text {
            width: parent.width
            text: "Enter launch · Esc close · ↑↓ move"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Fuzzy matching ────────────────────────────────────────
    // Every whitespace token must be a subsequence of the searchable text;
    // scores favor consecutive runs and word starts, plus a bonus when the
    // query prefixes the entry name. (Mirrored in /tmp/scorer_test.js.)
    function buildResults(query: string, apps: var): var {
        const out = [];
        for (const a of apps) {
            if (a.noDisplay) continue;
            const s = scoreEntry(a, query);
            if (s >= 0) out.push({ entry: a, score: s });
        }
        out.sort((x, y) => y.score - x.score || x.entry.name.localeCompare(y.entry.name));
        return out;
    }

    function scoreEntry(entry: var, query: string): int {
        const q = query.trim().toLowerCase();
        if (q.length === 0) return 0;
        const hay = (entry.name + " " + entry.genericName + " "
            + (entry.keywords || []).join(" ") + " "
            + (entry.categories || []).join(" ") + " "
            + (entry.execString || "")).toLowerCase();
        const tokens = q.split(/\s+/);
        let score = 0;
        for (const tok of tokens) {
            const s = subseqScore(hay, tok);
            if (s < 0) return -1;
            score += s;
        }
        if (entry.name.toLowerCase().startsWith(tokens[0])) score += 40;
        return score;
    }

    function subseqScore(hay: string, tok: string): int {
        let score = 0;
        let run = 0;
        let prev = -2;
        for (const ch of tok) {
            const idx = hay.indexOf(ch, prev + 1);
            if (idx < 0) return -1;
            if (idx === prev + 1) {
                run++;
                score += 2 + run * 2;
            } else {
                run = 0;
                const wordStart = idx === 0 || hay[idx - 1] === " " || hay[idx - 1] === "-";
                score += wordStart ? 8 : 1;
            }
            prev = idx;
        }
        return score;
    }
}
