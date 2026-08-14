// popups/AudioMenu.qml — sound popup: volume slider + mute + output
// device picker (replaces waybar audio_menu.sh and the control center's
// volume section). The default sink is marked with a raised row + 3px
// accent indicator; everything else stays quiet until hovered.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups

AnchoredPopup {
    id: root

    implicitWidth: 280
    implicitHeight: Math.min(popupShell.implicitHeight, 420)

    readonly property var node: Pipewire.defaultAudioSink
    readonly property int volPct: node && node.audio ? Math.round(node.audio.volume * 100) : 0

    // Keep the default sink alive while watching it (official example
    // pattern — without a tracker the node may be released).
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    PopupShell {
        id: popupShell
        anchors.fill: parent

        // ── Volume ────────────────────────────────────────────────────
        SectionLabel { text: "Sound" }

        Item {
            width: parent.width
            height: 20

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.node && root.node.audio && root.node.audio.muted ? "" : ""
                color: root.node && root.node.audio && root.node.audio.muted ? Theme.urgent : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "Volume"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.right: muteSwitch.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.volPct + "%"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            ToggleSwitch {
                id: muteSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.node && root.node.audio ? root.node.audio.muted : false
                onToggled: on => {
                    if (root.node && root.node.audio) {
                        root.node.audio.muted = on;
                    }
                }
            }
        }

        ControlSlider {
            width: parent.width
            from: 0
            to: 100
            value: root.volPct
            onUserSet: v => {
                if (root.node && root.node.audio) {
                    root.node.audio.volume = v / 100;
                }
            }
        }

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

}
