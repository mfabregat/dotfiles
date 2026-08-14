// bar/NightLightWidget.qml — night light state; click opens the popup.
// Moon glyph turns warm while the filter is active.
import QtQuick
import qs
import qs.services

Rectangle {
    id: root

    required property var nightLightPopup

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    Text {
        anchors.centerIn: parent
        text: ""
        color: NightLight.enabled ? Theme.warn : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeGlyphs
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.nightLightPopup.showAt(root)
    }
}
