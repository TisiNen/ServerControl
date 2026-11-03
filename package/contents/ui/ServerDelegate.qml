import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

Item {
    id: delegate

    required property var modelData
    required property PlasmoidItem plasmoidItem

    // "online" | "offline" | "" (not checked yet)
    readonly property string serverState: plasmoidItem.serverStates[modelData.id] || ""

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2

    RowLayout {
        id: row

        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.gridUnit * 0.6
            implicitHeight: implicitWidth
            radius: width / 2
            color: delegate.serverState === "online" ? Kirigami.Theme.positiveTextColor
                : delegate.serverState === "offline" ? Kirigami.Theme.disabledTextColor
                : "transparent"
            border.width: delegate.serverState === "" ? 1 : 0
            border.color: Kirigami.Theme.disabledTextColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: delegate.modelData.name
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: delegate.modelData.host
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }

        PlasmaComponents3.Label {
            text: delegate.plasmoidItem.stateText(delegate.modelData)
            color: delegate.serverState === "online" ? Kirigami.Theme.positiveTextColor
                : Kirigami.Theme.disabledTextColor
        }
    }
}
