// bar/NightLightWidget.qml — gammastep state (night light).
// Active: sun during daytime, moon while transitioning, orange moon at
// night. Disabled: ban (circle-slash). Click opens the control popup.
import QtQuick
import qs
import qs.services

Rectangle {
    id: root

    required property var nightLightPopup

    readonly property bool night: NightLight.period === "Night"
    readonly property bool transitioning: NightLight.period === "Transition"

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"
    visible: NightLight.available

    Text {
        anchors.centerIn: parent
        // Disabled: ban. Active: moon (night/transition) or sun (daytime).
        text: !NightLight.enabled ? ""
             : root.night || root.transitioning ? ""
             : ""
        color: !NightLight.enabled ? Theme.fgDim
             : root.night ? Theme.warn
             : Theme.fg
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
