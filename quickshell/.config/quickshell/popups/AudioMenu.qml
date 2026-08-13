// popups/AudioMenu.qml — output device picker (replaces waybar audio_menu.sh).
// The default sink is marked with a raised row + 3px accent indicator;
// everything else stays quiet until hovered.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs

AnchoredPopup {
    id: root

    implicitWidth: 280
    implicitHeight: Math.min(popupShell.implicitHeight, 420)

    PopupShell {
        id: popupShell
        anchors.fill: parent

        SectionLabel { text: "Output" }

        Repeater {
            model: Pipewire.nodes

            delegate: Rectangle {
                required property var modelData
                readonly property bool visibleRow: modelData.isSink && !modelData.isStream
                readonly property bool isDefault: modelData === Pipewire.defaultAudioSink

                width: parent.width
                height: visibleRow ? Theme.popupRowHeight : 0
                visible: visibleRow
                radius: Theme.radius
                color: rowArea.containsMouse ? Theme.bgHover
                     : isDefault ? Theme.bgAlt : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                // Active device indicator
                Rectangle {
                    visible: isDefault
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: Math.round(parent.height * 0.45)
                    radius: 2
                    color: Theme.accent
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: isDefault ? "" : ""
                        color: isDefault ? Theme.accent : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.description || modelData.name || ("Node " + modelData.id)
                        color: isDefault ? Theme.fg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        text: modelData.audio ? Math.round(modelData.audio.volume * 100) + "%" : ""
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Pipewire.preferredDefaultAudioSink = modelData;
                        root.hide(); // apply and close
                    }
                }
            }
        }
    }

    // ── Section header (small caps micro-label) ────────────────────────
    component SectionLabel: Text {
        text: ""
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing
    }
}
