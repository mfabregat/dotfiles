// Theme.qml — gruvbox palette + design tokens (ported from waybar style.css / rofi config)
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // ── Gruvbox dark palette (same values as the old waybar/rofi configs) ──
    readonly property color dark0: "#282828"
    readonly property color dark1: "#3c3836"
    readonly property color dark2: "#504945"
    readonly property color dark3: "#665c54"
    readonly property color dark4: "#7c6f64"
    readonly property color gray: "#928374"

    readonly property color light0: "#fbf1c7"
    readonly property color light1: "#ebdbb2"
    readonly property color light2: "#d5c4a1"
    readonly property color light3: "#bdae93"
    readonly property color light4: "#a89984"

    readonly property color brightRed: "#fb4934"
    readonly property color brightGreen: "#b8bb26"
    readonly property color brightYellow: "#fabd2f"
    readonly property color brightBlue: "#83a598"
    readonly property color brightPurple: "#d3869b"
    readonly property color brightAqua: "#8ec07c"
    readonly property color brightOrange: "#fe8019"

    readonly property color neutralRed: "#cc241d"
    readonly property color neutralGreen: "#98971a"
    readonly property color neutralYellow: "#d79921"
    readonly property color neutralBlue: "#458588"
    readonly property color neutralPurple: "#b16286"
    readonly property color neutralAqua: "#689d6a"
    readonly property color neutralOrange: "#d65d0e"

    // ── Semantic aliases ──
    readonly property color fg: light0
    readonly property color fgDim: light3
    readonly property color bg: dark0
    readonly property color bgAlt: dark1
    readonly property color bgHover: dark2
    readonly property color accent: brightGreen
    readonly property color urgent: brightRed
    readonly property color warn: brightYellow

    // ── Design tokens (plain numbers — tweak freely) ──────────────────
    readonly property string fontFamily: "Noto Sans Nerd Font Propo"
    readonly property string fontMono: "JetBrainsMono Nerd Font Propo"
    readonly property int barWidth: 32

    readonly property int spacing: 3
    readonly property int padding: 5
    readonly property int radius: 6
    readonly property int innerMargin: 3                            // bar window content margin
    readonly property int widgetMargin: 2                           // widget-internal margin
    readonly property int widgetWidth: 22                           // bar widget width
    readonly property int pillWidth: 21                             // workspaces/taskbar/tray pills
    readonly property int pillHeight: 18
    readonly property int popupRowHeight: 24                        // popup menu rows
    readonly property int calendarCell: 23                          // calendar day cell

    readonly property int iconSize: 12
    readonly property int iconSizeLarge: 14
    readonly property int fontSizeTiny: 6
    readonly property int fontSizeSmall: 8
    readonly property int fontSize: 9
    readonly property int fontSizeLarge: 11
    readonly property int textSize: 10

    // Mpris rotated strips: visual width of the text lines
    readonly property int titleStrip: 13
    readonly property int artistStrip: 11
}
