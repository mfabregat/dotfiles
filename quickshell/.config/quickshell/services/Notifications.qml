// services/Notifications.qml — notification daemon + popup/history state.
//
// Owns the org.freedesktop.Notifications server, keeps a capped history for
// the center, drives popup visibility/timeouts, and exposes the IPC entry
// point (`quickshell ipc call notifications toggle|open|close|test|dnd|clear|count`).
//
// Lifecycle (verified against quickshell 0.3.0 source, 2026-08):
// - The server emits `notification` synchronously; setting `tracked = true`
//   inside the handler retains it (untracked ones are deleted right after).
// - A tracked Notification is *deleted* by the server once closed (dismiss /
//   expire / app CloseNotification): its `closed` signal fires first, then
//   the object dies. We drop our references on `closed` and never touch a
//   closed notification again.
// - Invoking an action or inline reply closes the notification too (unless
//   the app sets the `resident` hint) — handled by the same `closed` path.
// - keepOnReload: false — reloads close every notification (reason Expired)
//   and this singleton is recreated fresh, so no stale state survives.
//
// List mutations always reassign the whole array (bindings in popups/center
// re-evaluate only on property reassignment — landmine 2 pattern).
pragma Singleton

import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    // ── Server ─────────────────────────────────────────────────────────
    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false
        onNotification: notif => root.addNotification(notif)
    }

    // ── State ──────────────────────────────────────────────────────────
    /// History: wrapper objects, newest first (the center's model).
    property var notifications: []
    /// Wrappers currently shown as popups, newest first (≤ popupLimit).
    property var popups: []
    /// Notifications that arrived since the center was last opened.
    property int unread: 0
    /// Do-not-disturb: popups suppressed (critical still interrupts).
    property bool dnd: false
    /// Center open state (bell click / $mod+n via IPC).
    property bool centerOpen: false

    // Enabling DND ends any popups still on screen (new ones are stored but
    // never shown; critical still interrupts, matching swaync).
    onDndChanged: {
        if (root.dnd) {
            for (const w of root.popups.slice()) root.endPopup(w);
        }
    }

    readonly property int historyLimit: 50
    readonly property int popupLimit: 3
    readonly property int tickMs: 250
    // Popup auto-dismiss timeouts per urgency. Critical stays until closed
    // (timeout 0); an app-specified expire_timeout overrides these.
    readonly property int timeoutLow: 5000
    readonly property int timeoutNormal: 7000
    readonly property int timeoutCritical: 0

    // ── Popup timeout driver ───────────────────────────────────────────
    // Runs only while popups exist; each tick accumulates elapsed time on
    // the popup wrappers (paused ones are skipped while hovered).
    Timer {
        id: ticker
        interval: root.tickMs
        repeat: true
        running: root.popups.length > 0
        onTriggered: {
            for (const w of root.popups) {
                if (w.paused || w.timeoutMs <= 0) continue;
                w.elapsed += root.tickMs;
                if (w.elapsed >= w.timeoutMs) root.endPopup(w);
            }
        }
    }

    // ── Ingress ────────────────────────────────────────────────────────
    function addNotification(notif: var): void {
        notif.tracked = true;

        const wrap = {
            notification: notif,
            screen: root.focusedScreen(),
            timeoutMs: root.timeoutFor(notif),
            elapsed: 0,
            paused: false,
            transient: notif.transient,
            time: Date.now(),
        };

        // History (newest first, capped; the overflow is closed server-side).
        let next = [wrap].concat(root.notifications);
        if (next.length > root.historyLimit) {
            const dropped = next.pop();
            if (dropped.notification) dropped.notification.dismiss();
        }
        root.notifications = next;

        // Popup (suppressed by DND / open center; critical always shows).
        // Popup membership IS the popups array — no separate flag.
        const isCritical = notif.urgency === NotificationUrgency.Critical;
        if ((!root.dnd || isCritical) && !root.centerOpen) {
            root.popups = [wrap].concat(root.popups);
            if (root.popups.length > root.popupLimit) {
                root.popups.pop(); // oldest leaves the window, stays in history
            }
            root.unread += 1;
        }

        // Server closes the Notification object after `closed` — drop it.
        notif.closed.connect(() => root.removeWrapper(wrap));

        console.log("[notifications] " + (notif.appName || "?") + ": " + notif.summary);
    }

    function timeoutFor(notif: var): int {
        // Resident notifications (e.g. always-on status) never auto-dismiss.
        if (notif.resident) return 0;
        if (notif.expireTimeout > 0) return notif.expireTimeout;
        if (notif.urgency === NotificationUrgency.Critical) return root.timeoutCritical;
        if (notif.urgency === NotificationUrgency.Low) return root.timeoutLow;
        return root.timeoutNormal;
    }

    /// The screen a popup should appear on: the monitor focused on arrival
    /// (by name), falling back to the first screen.
    function focusedScreen(): var {
        const mon = I3.focusedMonitor;
        const screens = Quickshell.screens;
        if (mon) {
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].name === mon.name) return screens[i];
            }
        }
        return screens.length ? screens[0] : null;
    }

    // ── Popup lifecycle ────────────────────────────────────────────────
    /// Stop showing `w` as a popup. Transient notifications (screen
    /// recorders, ...) vanish entirely; the rest stay in history.
    function endPopup(w: var): void {
        if (!root.popups.includes(w)) return;
        root.popups = root.popups.filter(x => x !== w);
        if (w.transient && w.notification) w.notification.dismiss();
    }

    /// Dismiss `w` everywhere (popup + history) and close it server-side.
    function discard(w: var): void {
        if (!w) return;
        if (w.notification) w.notification.dismiss();
        root.removeWrapper(w);
    }

    /// Remove `w` from all lists (idempotent — safe on double paths, e.g.
    /// dismiss() → closed signal → removeWrapper, then our own call).
    function removeWrapper(w: var): void {
        if (root.notifications.includes(w)) {
            root.notifications = root.notifications.filter(x => x !== w);
        }
        if (root.popups.includes(w)) {
            root.popups = root.popups.filter(x => x !== w);
        }
        root.unread = Math.max(0, root.unread - 1);
        if (w.notification) w.notification = null; // server deleted the object
    }

    function clearAll(): void {
        for (const w of root.notifications) {
            if (w.notification) w.notification.dismiss();
        }
        root.notifications = [];
        root.popups = [];
        root.unread = 0;
    }

    // ── Center ─────────────────────────────────────────────────────────
    function toggleCenter(): void {
        if (root.centerOpen) root.closeCenter();
        else root.openCenter();
    }

    function openCenter(): void {
        root.centerOpen = true;
        root.unread = 0;
        for (const w of root.popups.slice()) root.endPopup(w);
    }

    function closeCenter(): void {
        root.centerOpen = false;
    }

    // ── Test + IPC ─────────────────────────────────────────────────────
    // gdbus parses the args per the Notify signature (susssasa{sv}i) and
    // needs no libnotify. Runs detached so `ipc call` returns immediately.
    function sendTest(): void {
        root.execNotify("Quickshell", "Normal notification", "This one auto-dismisses after a few seconds.", "dialog-information", "{}", 5000);
        root.execNotify("Quickshell", "Low urgency", "A quieter notification.", "dialog-information", "{'urgency': <byte 0>}", 5000);
        root.execNotify("Quickshell", "Critical notification", "This one stays until you dismiss it.", "dialog-error", "{'urgency': <byte 2>}", 0);
    }

    function execNotify(app: string, summary: string, body: string, icon: string, hints: string, timeout: int): void {
        Quickshell.execDetached(root.testArgs(app, summary, body, icon, hints, timeout));
    }

    function testArgs(app: string, summary: string, body: string, icon: string, hints: string, timeout: int): var {
        return [
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications",
            "--method", "org.freedesktop.Notifications.Notify",
            app, "0", icon, summary, body, "[]", hints, String(timeout)
        ];
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void { root.toggleCenter(); }
        function open(): void { root.openCenter(); }
        function close(): void { root.closeCenter(); }
        function test(): void { root.sendTest(); }
        function dnd(): void { root.dnd = !root.dnd; }
        function clear(): void { root.clearAll(); }
        function count(): int { return root.notifications.length; }
    }
}
