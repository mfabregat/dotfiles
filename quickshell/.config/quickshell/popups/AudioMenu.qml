// popups/AudioMenu.qml — output device picker (replaces waybar audio_menu.sh).
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs

AnchoredPopup {
    id: root

    implicitWidth: 260
    implicitHeight: Math.min(popupShell.implicitHeight, 420)

    PopupShell {
        id: popupShell
        anchors.fill: parent

        Text {
            text: "Output devices"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
        }

        Repeater {
            model: Pipewire.nodes

            delegate: Rectangle {
                required property var modelData
                readonly property bool visibleRow: modelData.isSink && !modelData.isStream
                readonly property bool isDefault: modelData === Pipewire.defaultAudioSink

                width: parent.width
                height: visibleRow ? 32 : 0
                visible: visibleRow
                radius: 6
                color: rowArea.containsMouse ? Theme.bgHover
                     : isDefault ? Theme.dark1 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Text {
                        text: isDefault ? "" : ""
                        color: isDefault ? Theme.accent : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.description || modelData.name || ("Node " + modelData.id)
                        color: isDefault ? Theme.fg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        text: modelData.audio ? Math.round(modelData.audio.volume * 100) + "%" : ""
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
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
