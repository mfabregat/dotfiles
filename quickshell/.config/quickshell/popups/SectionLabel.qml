// popups/SectionLabel.qml — small-caps micro-label section header
// (PowerSection, AudioMenu, BacklightPopup, PolkitDialog). Extracted at
// the 4th copy (plan rule).
import QtQuick
import qs

Text {
    id: root

    text: ""
    color: Theme.fgDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSmall
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Theme.letterSpacing
}
