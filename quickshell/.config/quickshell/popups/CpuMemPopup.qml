// popups/CpuMemPopup.qml — system status details (CPU / MEM / TEMP).
// Data comes from the existing CpuMemTemp poller (1s, shared with the
// glyphs) — this popup adds zero polling. Hover-driven: no input grab;
// closes when the pointer leaves it. The history canvas repaints only
// when its values change (cheap, skipped while hidden).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

AnchoredPopup {
    id: root

    grabOnOpen: false // hover-driven — must not grab input

    readonly property bool hovered: hoverArea.containsMouse

    implicitWidth: 220
    implicitHeight: popupShell.implicitHeight

    PopupShell {
        id: popupShell
        anchors.fill: parent

        // CPU model name (read once at startup)
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: CpuMemTemp.cpuName || "System"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Sparkline {
            label: "CPU"
            color: Theme.accent
            values: CpuMemTemp.cpuHistory
            percent: CpuMemTemp.cpu
        }
        Sparkline {
            label: "MEM"
            color: Theme.brightAqua
            values: CpuMemTemp.memHistory
            percent: CpuMemTemp.mem
        }

        // Per-core usage (htop-style compact grid)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            // Keeps the grid aligned with the TEMP row's icon column
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 1
            }

            Text {
                text: "CORE"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                font.letterSpacing: Theme.letterSpacing
                Layout.preferredWidth: 36
            }

            Grid {
                Layout.fillWidth: true
                columns: 8
                spacing: 2

                Repeater {
                    model: CpuMemTemp.cores

                    delegate: Rectangle {
                        required property real modelData
                        width: 10
                        height: 14
                        radius: 2
                        color: Theme.dark2

                        Rectangle {
                            width: parent.width
                            height: parent.height * Math.min(100, Math.max(0, modelData)) / 100
                            radius: 2
                            color: root.coreColor(modelData)
                        }
                    }
                }
            }
        }

        // TEMP row
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: ""
                color: root.tempColorFor(CpuMemTemp.temp)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeGlyphs
                Layout.preferredWidth: 20
            }

            Text {
                text: "TEMP"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                font.letterSpacing: Theme.letterSpacing
                Layout.preferredWidth: 36
            }

            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Theme.dark2

                Rectangle {
                    width: parent.width * Math.min(100, Math.max(0, CpuMemTemp.temp)) / 100
                    height: parent.height
                    radius: 2
                    color: root.tempColorFor(CpuMemTemp.temp)
                }
            }

            Text {
                text: Math.round(CpuMemTemp.temp) + "°C"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        onExited: root.hide()
    }

    function colorFor(value: real): color {
        if (value >= 90) return Theme.urgent;
        if (value >= 70) return Theme.warn;
        return Theme.accent;
    }

    function tempColorFor(value: real): color {
        if (value >= 80) return Theme.urgent;
        if (value >= 60) return Theme.warn;
        return Theme.accent;
    }

    function coreColor(value: real): color {
        if (value >= 90) return Theme.urgent;
        if (value >= 70) return Theme.warn;
        return Theme.accent;
    }

    // Sparkline row: label + Canvas bar history + current percent.
    // Repaints only when the values change (cheap; skipped while hidden).
    component Sparkline: RowLayout {
        id: row

        property string label: ""
        property color color: Theme.accent
        property var values: []
        property real percent: 0

        Layout.fillWidth: true
        height: 28
        spacing: 6

        Text {
            text: row.label
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            font.letterSpacing: Theme.letterSpacing
            Layout.preferredWidth: 36
        }

        Canvas {
            id: graph
            property var values: row.values // repaint trigger (reactive)

            Layout.fillWidth: true
            Layout.fillHeight: true

            onValuesChanged: requestPaint()

            onPaint: {
                const ctx = graph.getContext("2d");
                ctx.clearRect(0, 0, graph.width, graph.height);
                ctx.fillStyle = Theme.dark2;
                ctx.fillRect(0, 0, graph.width, graph.height);

                const values = Array.isArray(row.values) ? row.values : [];
                const barW = graph.width / Math.max(1, values.length);
                for (let i = 0; i < values.length; i++) {
                    const v = Math.min(100, Math.max(0, Number(values[i]) || 0));
                    const h = Math.max(v > 0 ? 1 : 0, (v / 100) * graph.height);
                    ctx.fillStyle = row.color;
                    ctx.fillRect(i * barW, graph.height - h, Math.max(1, barW - 1), h);
                }
            }
        }

        Text {
            text: Math.round(row.percent) + "%"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
        }
    }
}
