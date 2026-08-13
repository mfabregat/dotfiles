// bar/CpuMemWidget.qml — CPU / memory / temperature status glyphs.
// No numbers: colors alone flag the state (warn -> yellow, critical -> red).
// Hover (200ms) or click opens the details popup.
import QtQuick
import qs
import qs.services

Item {
    id: root

    required property var detailsPopup

    width: Theme.widgetWidth
    implicitHeight: glyphCol.implicitHeight
    visible: CpuMemTemp.available

    function colorFor(value: real): color {
        if (value >= 90) return Theme.urgent;
        if (value >= 70) return Theme.warn;
        return Theme.fgDim;
    }

    function tempColorFor(value: real): color {
        if (value >= 80) return Theme.urgent;
        if (value >= 60) return Theme.warn;
        return Theme.fgDim;
    }

    Column {
        id: glyphCol
        anchors.fill: parent
        spacing: 3

        StatusGlyph {
            glyph: ""
            color: root.colorFor(CpuMemTemp.cpu)
        }
        StatusGlyph {
            glyph: ""
            color: root.colorFor(CpuMemTemp.mem)
        }
        StatusGlyph {
            glyph: ""
            color: root.tempColorFor(CpuMemTemp.temp)
        }
    }

    component StatusGlyph: Text {
        property string glyph: ""

        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: glyph
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeGlyphs
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true

        onClicked: root.detailsPopup.showAt(root) // PopupManager toggles it
        onEntered: openTimer.start()
        onExited: closeTimer.start()
    }

    // Grace timers: quick passes don't pop; moving into the popup (across
    // the gap) doesn't close it.
    Timer {
        id: openTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (area.containsMouse && !root.detailsPopup.visible)
                root.detailsPopup.showAt(root);
        }
    }
    Timer {
        id: closeTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (!root.detailsPopup.hovered) root.detailsPopup.hide();
        }
    }
}
