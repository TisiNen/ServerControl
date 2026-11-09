import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

import "code/model.js" as Model

Item {
    id: serverRow

    required property var modelData
    required property PlasmoidItem plasmoidItem

    // Forwarded from a FunctionControl; FullRepresentation decides whether
    // to confirm first.
    signal functionActivated(var fn, bool turnOn)

    // "online" | "offline" | "" (not checked yet)
    readonly property string serverState: plasmoidItem.serverStates[modelData.id] || ""
    readonly property real dotSize: Kirigami.Units.gridUnit * 0.6

    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: serverRow.dotSize
                implicitHeight: implicitWidth
                radius: width / 2
                color: serverRow.serverState === "online" ? Kirigami.Theme.positiveTextColor
                    : serverRow.serverState === "offline" ? Kirigami.Theme.disabledTextColor
                    : "transparent"
                border.width: serverRow.serverState === "" ? 1 : 0
                border.color: Kirigami.Theme.disabledTextColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: serverRow.modelData.name
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: serverRow.modelData.host
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
            }

            PlasmaComponents3.Label {
                text: serverRow.plasmoidItem.stateText(serverRow.modelData)
                color: serverRow.serverState === "online" ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
            }
        }

        // The server's functions, wrapping onto more lines when the popup
        // is narrow. Indented to line up with the name.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: serverRow.dotSize + Kirigami.Units.largeSpacing
            visible: functions.count > 0
            spacing: Kirigami.Units.smallSpacing

            // The tallest control's height. Every control takes it and
            // centers its content, so buttons, switches and indicators line up.
            readonly property real rowHeight: {
                let height = 0;
                for (let i = 0; i < functions.count; i++) {
                    const item = functions.itemAt(i);
                    if (item) {
                        height = Math.max(height, item.contentHeight);
                    }
                }
                return height;
            }

            Repeater {
                id: functions

                model: Model.controlFunctions(serverRow.modelData)

                delegate: FunctionControl {
                    required property var modelData

                    rowHeight: parent ? parent.rowHeight : 0
                    server: serverRow.modelData
                    fn: modelData
                    plasmoidItem: serverRow.plasmoidItem
                    onActivated: turnOn => serverRow.functionActivated(modelData, turnOn)
                }
            }
        }

        // The error of each function whose last command failed, under the
        // controls. Disappears together with the ✗.
        Repeater {
            model: Model.controlFunctions(serverRow.modelData)

            delegate: PlasmaComponents3.Label {
                required property var modelData

                readonly property var result:
                    serverRow.plasmoidItem.functionResults[Model.functionKey(serverRow.modelData, modelData)] || null

                Layout.fillWidth: true
                Layout.leftMargin: serverRow.dotSize + Kirigami.Units.largeSpacing
                visible: result !== null && !result.ok
                text: visible ? i18nc("@info function name: error message", "%1: %2",
                                      serverRow.plasmoidItem.functionName(modelData),
                                      serverRow.plasmoidItem.resultText(result))
                    : ""
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
