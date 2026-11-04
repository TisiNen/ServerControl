import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

PlasmaExtras.Representation {
    id: full

    required property PlasmoidItem plasmoidItem

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 6
    Layout.preferredHeight: Kirigami.Units.gridUnit * 14

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                text: i18n("Server Control")
                elide: Text.ElideRight
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                text: i18n("Check status now")
                display: PlasmaComponents3.AbstractButton.IconOnly
                onClicked: full.plasmoidItem.refreshAll()

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    contentItem: PlasmaComponents3.ScrollView {
        ListView {
            id: list

            model: full.plasmoidItem.serverList
            spacing: Kirigami.Units.smallSpacing
            clip: true

            // Shown only when parsing the config skipped or fixed something;
            // the details go to the log (see main.qml).
            header: full.plasmoidItem.configWarnings.length > 0 ? configWarning : null

            Component {
                id: configWarning

                Kirigami.InlineMessage {
                    width: list.width
                    visible: true
                    type: Kirigami.MessageType.Warning
                    text: i18n("Some server settings are invalid and were ignored. See the system log for details.")
                }
            }

            delegate: ServerDelegate {
                width: ListView.view.width
                plasmoidItem: full.plasmoidItem
            }

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: list.count === 0
                iconName: "network-server"
                text: i18n("No servers configured")
            }
        }
    }
}
