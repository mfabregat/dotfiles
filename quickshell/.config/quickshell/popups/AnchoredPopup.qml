// popups/AnchoredPopup.qml — PopupWindow base anchored to the bar, with
// on-screen clamping.
//
// sway applies the xdg_positioner as-is (no constraint adjustment is sent),
// so the anchor Y is clamped here: the popup stays vertically centered on
// its trigger widget and never runs off the bottom of the screen.
//
// The anchor rect Y is a reactive binding on the window height: popup
// heights settle asynchronously (e.g. the Pipewire sink list), and the
// binding re-evaluates — and the positioner is re-sent — when they do.
import Quickshell
import QtQuick

PopupWindow {
    id: root

    /// The bar window this popup belongs to.
    required property var anchorWindow

    /// Widget the popup is currently anchored to (set by showAt).
    property var anchorItem: null
    /// Anchor point: the widget's left edge and vertical center, in the
    /// bar window's coordinates (set by showAt).
    property real itemX: 0
    property real itemCenterY: 0
    /// The popup's screen (for clamping).
    readonly property int screenHeight: root.anchorWindow && root.anchorWindow.screen
        ? root.anchorWindow.screen.height : 1080
    /// Height used for clamping (window height, once mapped).
    readonly property int effH: Math.max(root.height, 40)

    anchor {
        window: anchorWindow
        edges: Edges.Left
        gravity: Edges.Left
    }

    // Reactive anchor rect: re-evaluates when the popup height settles.
    anchor.rect.x: root.anchorItem ? root.itemX : 0
    anchor.rect.y: root.anchorItem
        ? Math.max(root.effH / 2 + 4,
                   Math.min(root.itemCenterY, root.screenHeight - root.effH / 2 - 4))
        : 0
    anchor.rect.width: 1
    anchor.rect.height: 1

    /// Open the popup anchored to the given widget (must live in the bar window).
    function showAt(item: var): void {
        const p = item.mapToItem(root.anchorWindow.contentItem, 0, 0);
        root.itemX = p.x;
        root.itemCenterY = p.y + item.height / 2;
        root.anchorItem = item;
        root.visible = true;
    }
}
