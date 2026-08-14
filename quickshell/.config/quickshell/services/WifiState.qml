// services/WifiState.qml — native NetworkManager state + actions.
// Uses Quickshell.Networking directly — no nmcli subprocesses: devices and
// networks are tracked object models, and connect/disconnect/PSK/scan are
// module methods (verified against the installed 0.3.0-2 qmltypes and the
// v0.3.0 docs; this desktop has no wifi hardware, so the wifi UI hides
// itself — the ethernet row still works).
//
// Scanner lifecycle: continuous scanning costs battery, so the wifi
// scanner runs only while a network UI (bar menu / control center) is
// visible. Popups call useScanner(true/false) on show/hide (refcounted).
pragma Singleton

import Quickshell
import Quickshell.Networking
import QtQuick

Singleton {
    id: root

    /// First wifi device (null on machines without wifi).
    readonly property var wifiDevice: findWifi(Networking.devices.values)
    /// The wifi device's networks (tracked object-model read → array).
    readonly property var networks: wifiDevice ? wifiDevice.networks.values : []
    /// rfkill software block (writable, tracked).
    property bool wifiEnabled: Networking.wifiEnabled
    /// Connected network on any device.
    readonly property var activeNet: findActive(Networking.devices.values)
    /// Network whose connection attempt is in flight (row spinner).
    property var pending: null
    /// Network awaiting a PSK (its row shows an inline password field).
    property var pskNetwork: null
    /// Last connection failure, shown in the section header.
    property string error: ""

    /// Networks sorted for display: connected first, then signal strength.
    readonly property var sortedNetworks: root.networks.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.signalStrength - a.signalStrength))

    // ── Scanner refcount ───────────────────────────────────────────────
    property int scanUsers: 0
    onScanUsersChanged: {
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = root.scanUsers > 0;
    }
    function useScanner(active: bool): void {
        root.scanUsers += active ? 1 : -1;
    }

    // ── Actions ────────────────────────────────────────────────────────
    function enableWifi(on: bool): void {
        Networking.wifiEnabled = on;
    }

    function rescan(): void {
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = true;
    }

    /// Connect to / disconnect from `net`. Known networks connect without
    /// a prompt (the backend has stored secrets); unknown open networks
    /// connect directly; unknown secured ones open the inline PSK row
    /// first — per the module docs, connectWithPsk() should only be
    /// called when a prompt is actually required.
    function connect(net: var): void {
        root.error = "";
        if (net.connected) {
            net.disconnect();
            return;
        }
        if (net.known) {
            root.pending = net;
            net.connect();
        } else if (net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe) {
            root.pending = net;
            net.connectWithPsk("");
        } else {
            root.pskNetwork = net;
        }
    }

    /// Submit the PSK typed into the inline row.
    function connectWithPsk(psk: string): void {
        const net = root.pskNetwork;
        if (!net) return;
        root.pskNetwork = null;
        root.error = "";
        root.pending = net;
        net.connectWithPsk(psk);
    }

    function cancelPsk(): void {
        root.pskNetwork = null;
    }

    // ── Failure + completion wiring ────────────────────────────────────
    // One connectionFailed handler per network, attached idempotently
    // (the module reuses network objects across scans). The signal
    // carries the reason; NoSecrets re-opens the PSK row (wrong/missing
    // key — per the docs connectWithPsk with a wrong PSK emits it).
    property var attached: []
    function ensureAttached(): void {
        for (const n of root.networks) {
            if (root.attached.indexOf(n) >= 0) continue;
            root.attached.push(n);
            n.connectionFailed.connect(reason => root.onConnectionFailed(n, reason));
        }
    }
    onNetworksChanged: root.ensureAttached()

    function onConnectionFailed(net: var, reason: int): void {
        if (root.pending === net) root.pending = null;
        root.error = "Connection failed: " + ConnectionFailReason.toString(reason);
        if (reason === ConnectionFailReason.NoSecrets) root.pskNetwork = net;
    }

    // The pending network came up (or an old psk prompt was resolved by
    // a successful connect) — clear the transient state.
    onActiveNetChanged: {
        if (!root.activeNet) return;
        if (root.pending === root.activeNet) root.pending = null;
        if (root.pskNetwork === root.activeNet) root.pskNetwork = null;
    }

    function findWifi(devices: var): var {
        for (const d of devices) {
            if (d.type === DeviceType.Wifi) return d;
        }
        return null;
    }

    function findActive(devices: var): var {
        for (const d of devices) {
            for (const n of d.networks.values) {
                if (n.connected) return n;
            }
        }
        return null;
    }
}
