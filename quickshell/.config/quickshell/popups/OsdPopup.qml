// popups/OsdPopup.qml — volume/brightness on-screen display, one window
// per screen (Variants in shell.qml). Only the instance routed by Osd.screen
// (the monitor focused when the change happened) is visible.
//
// Display-only: an empty input mask lets clicks pass through to windows
// beneath (official volume-osd example pattern). Bottom-centered via the
// layer-shell spec (bottom anchor + no horizontal anchor → centered).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Stable snapshot for routing and sizing (never read the window's
    // `screen` inside a visibility-dependent binding — plan landmine 10).
    property var routeScreen: null
    Component.onCompleted: root.routeScreen = root.modelData

    anchors.bottom: true
    margins.bottom: (root.routeScreen ? root.routeScreen.height : 1080) / 5
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore // transient — never shrink tiling area
    mask: Region {} // input passthrough (rendering unaffected)

    visible: Osd.active && Osd.screen === root.routeScreen
    implicitWidth: 340
    implicitHeight: 60

    // ── Card ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.popupRadius
        color: Theme.bg
        border.color: Theme.dark2
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padding
            spacing: 12

            Text {
                text: root.glyphText
                color: root.glyphColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs + 4
            }

            Text {
                text: Osd.level + "%"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            // Progress track + fill
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: Theme.dark2

                Rectangle {
                    width: parent.width * Math.min(1, Math.max(0, Osd.level / 100))
                    height: parent.height
                    radius: 4
                    color: root.levelColor
                }
            }
        }
    }

    // ── Derived visuals ────────────────────────────────────────────────
    readonly property string glyphText: {
        if (Osd.kind === "brightness") return "";
        if (Osd.muted) return "";
        if (Osd.level > 50) return "";
        return "";
    }

    readonly property color glyphColor: Osd.muted ? Theme.urgent : Theme.fg
    readonly property color levelColor: Osd.muted ? Theme.urgent
        : (Osd.kind === "brightness" ? Theme.brightYellow : Theme.accent)
}
