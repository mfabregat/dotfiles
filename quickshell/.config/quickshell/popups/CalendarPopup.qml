// popups/CalendarPopup.qml — month calendar popup (LayerPopup-based).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

LayerPopup {
    id: root

    readonly property int cell: 30
    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property var cells: []

    implicitWidth: 7 * cell + Theme.padding * 2
    implicitHeight: 28 + 6 * cell + Theme.padding * 2

    // Header: ‹ August 2026 ›
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        NavButton {
            text: ""
            onClicked: {
                root.viewMonth--;
                if (root.viewMonth < 0) { root.viewMonth = 11; root.viewYear--; }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
        }

        NavButton {
            text: ""
            onClicked: {
                root.viewMonth++;
                if (root.viewMonth > 11) { root.viewMonth = 0; root.viewYear++; }
            }
        }
    }

    // Weekday headers
    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: ["L", "M", "X", "J", "V", "S", "D"]
            Text {
                Layout.preferredWidth: root.cell
                Layout.preferredHeight: 14
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
            }
        }
    }

    // Day grid (Monday-first, matching the locale)
    Grid {
        columns: 7
        spacing: 0

        Repeater {
            model: root.cells

            delegate: Rectangle {
                required property var modelData
                readonly property int day: modelData.d
                readonly property bool isToday: day > 0
                    && root.viewYear === root.today.getFullYear()
                    && root.viewMonth === root.today.getMonth()
                    && day === root.today.getDate()

                width: root.cell
                height: root.cell
                radius: 5
                color: isToday ? Theme.brightYellow : "transparent"

                Text {
                    anchors.centerIn: parent
                    visible: day > 0
                    text: day
                    color: isToday ? Theme.dark0 : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: isToday
                }
            }
        }
    }

    component NavButton: Rectangle {
        id: btn

        property string text: ""
        signal clicked

        width: 22
        height: 20
        radius: 5
        color: btnArea.containsMouse ? Theme.bgHover : "transparent"

        Text {
            anchors.centerIn: parent
            text: btn.text
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    // Monday-first grid (week starts Monday in the locale)
    function rebuildCells(): void {
        const grid = [];
        const first = new Date(root.viewYear, root.viewMonth, 1);
        const offset = (first.getDay() + 6) % 7;
        for (let i = 0; i < offset; i++) grid.push({ d: 0 });
        const daysInMonth = new Date(root.viewYear, root.viewMonth + 1, 0).getDate();
        for (let d = 1; d <= daysInMonth; d++) grid.push({ d: d });
        while (grid.length % 7 !== 0) grid.push({ d: 0 });
        root.cells = grid;
    }

    onViewYearChanged: rebuildCells()
    onViewMonthChanged: rebuildCells()
    Component.onCompleted: rebuildCells()
}
