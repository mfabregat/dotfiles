// popups/ClipboardPopup.qml — clipboard history (search + copy).
// One fullscreen window per screen; only the focused monitor's instance
// is visible (launcher pattern). Toggled from sway: `quickshell ipc call
// clipboard toggle` ($mod+Shift+v). Clicking a row copies it to the
// clipboard and closes; ✕ removes a single entry; Esc / backdrop closes.
//
// Needs wl-clipboard (services/Clipboard.qml probes for it) — without it
// the history stays empty and the popup shows a hint instead.
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
    exclusionMode: ExclusionMode.Ignore

    readonly property var i3Monitor: I3.monitors.values.length ? I3.monitorFor(root.screen) : null
    visible: Clipboard.open && root.i3Monitor !== null && root.i3Monitor.focused

    /// Filtered history (re-evaluates on every keystroke / ring change).
    property var filtered: Clipboard.items.filter(t =>
        t.toLowerCase().includes(searchInput.text.toLowerCase()))

    readonly property int listH: Math.min(root.filtered.length, 8) * Theme.popupRowHeight

    // Fresh open: clear the previous query and arm keyboard focus.
    onVisibleChanged: {
        if (root.visible) {
            searchInput.text = "";
            Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    // Backdrop: click-away closes.
    MouseArea {
        anchors.fill: parent
        onClicked: Clipboard.open = false
    }

    // ── Centered card ──────────────────────────────────────────────────
    PopupShell {
        id: card
        anchors.centerIn: parent
        width: 400

        // Header: title · count · clear
        Item {
            width: parent.width
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Clipboard"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.right: clearBtn.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: Clipboard.items.length > 0
                text: Clipboard.items.length + " items"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: clearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Clipboard.items.length > 0
                text: ""
                color: clearArea.containsMouse ? Theme.urgent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Clipboard.clear()
                }
            }
        }

        // Search row: glyph · input · clear (launcher pattern)
        Item {
            width: parent.width
            implicitHeight: 30

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
                anchors.right: searchClear.left
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

                Keys.onEscapePressed: { Clipboard.open = false; event.accepted = true; }
                Keys.onUpPressed: { list.currentIndex = Math.max(0, list.currentIndex - 1); event.accepted = true; }
                Keys.onDownPressed: { list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1); event.accepted = true; }
                Keys.onReturnPressed: { root.copySelected(); event.accepted = true; }
                Keys.onEnterPressed: { root.copySelected(); event.accepted = true; }
            }

            Text {
                id: searchClear
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                visible: searchInput.text.length > 0
                text: "×"
                color: searchClearArea.containsMouse ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: searchClearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: searchInput.text = ""
                }
            }
        }

        // History list (native ListView; inline delegates only — no
        // `required property var modelData`, landmine 9)
        ListView {
            id: list
            width: parent.width
            height: root.listH
            visible: root.filtered.length > 0
            model: root.filtered
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true

            delegate: Rectangle {
                readonly property string item: modelData
                readonly property bool selected: ListView.isCurrentItem

                width: list.width
                height: Theme.popupRowHeight
                radius: Theme.radius
                color: selected ? Theme.accent : (rowArea.containsMouse ? Theme.bgHover : "transparent")
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: delBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.preview(item)
                    color: selected ? Theme.dark0 : Theme.fg
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    id: delBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: selected ? Theme.dark0 : delArea.containsMouse ? Theme.urgent : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: delArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Clipboard.removeAt(index)
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: list.currentIndex = index
                    onClicked: {
                        list.currentIndex = index;
                        root.copySelected();
                    }
                }
            }
        }

        // Empty states
        Text {
            width: parent.width
            visible: root.filtered.length === 0 && !Clipboard.available
            text: "Clipboard history needs wl-clipboard"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: root.filtered.length === 0 && Clipboard.available && Clipboard.items.length === 0
            text: "No clipboard history yet — copy something"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            visible: root.filtered.length === 0 && Clipboard.items.length > 0
            text: "No matches"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Actions ────────────────────────────────────────────────────────
    function copySelected(): void {
        const hit = root.filtered[list.currentIndex];
        if (!hit) return;
        Clipboard.copy(hit);
        Clipboard.open = false;
    }

    /// One-line preview for a row: collapse whitespace, let elide trim.
    function preview(t: string): string {
        return t.replace(/\s+/g, " ").trim();
    }
}
