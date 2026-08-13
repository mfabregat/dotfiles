// popups/NotificationPopup.qml — transient notification popups, one window
// per screen (Variants in shell.qml). Shows the popups routed to this
// screen (≤ 3, newest on top) in a small column just left of the bar.
// Urgency styling lives in NotificationRow (critical = red border; it also
// never auto-dismisses). Hovering a popup pauses its timer.
//
// Sizing note: the window's implicit height follows the ListView's
// contentHeight (a Column+Repeater did not pick up delegate sizes — the
// implicit size of a Column is not recomputed when Repeater-created items
// appear; verified in a throwaway config).
import Quickshell
import QtQuick
import qs
import qs.popups
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Stable snapshot of the target screen for filtering. The window's
    // `screen` (and possibly modelData) can be re-evaluated by the
    // compositor when the window maps/unmaps, which fed back into
    // `shown` → `visible` (binding loop seen in the logs).
    property var routeScreen: null
    Component.onCompleted: root.routeScreen = root.modelData

    anchors { top: true; right: true }
    margins { top: 8; right: Theme.barWidth + 8 }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore // transient — never shrink tiling area

    /// Popups routed to this screen (re-evaluates on every service list
    /// reassignment).
    readonly property var shown: Notifications.popups.filter(w => w.screen === root.routeScreen)

    visible: root.shown.length > 0
    implicitWidth: 340
    implicitHeight: Math.min(list.contentHeight,
                             (root.routeScreen ? root.routeScreen.height : 1080) - 16)

    ListView {
        id: list
        anchors.fill: parent
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown

        delegate: Item {
            // Inline wrapper delegate: a file-component delegate cannot see
            // the Repeater/ListView `modelData` — the outer Variants
            // delegate's `required property var modelData` (the screen)
            // shadows it (verified in a throwaway config). Inline scopes
            // resolve it correctly, so resolve here and pass by property.
            width: list.width
            implicitHeight: row.implicitHeight
            NotificationRow {
                id: row
                width: parent.width
                pausable: true
                clickable: true
                wrapper: modelData
            }
        }
    }
}
