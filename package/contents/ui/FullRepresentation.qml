import QtQuick
import QtQuick.Controls as QQC2
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

    // Runs a function the user clicked, after asking first if it has
    // `confirm` set.
    function activate(server, fn, turnOn) {
        if (fn.confirm) {
            confirmDialog.ask(server, fn, turnOn);
        } else {
            plasmoidItem.runFunction(server, fn, turnOn);
        }
    }

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
                onFunctionActivated: (fn, turnOn) => full.activate(modelData, fn, turnOn)
            }

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: list.count === 0
                iconName: "network-server-symbolic"
                text: i18n("No servers configured")
                // Opens the settings dialog, like "Configure…" in the
                // widget's context menu.
                helpfulAction: QQC2.Action {
                    icon.name: "configure"
                    text: i18n("Configure…")
                    onTriggered: Plasmoid.internalAction("configure").trigger()
                }
            }
        }
    }

    Kirigami.PromptDialog {
        id: confirmDialog

        property var server: null
        property var fn: null
        property bool turnOn: true

        readonly property string functionName: fn ? full.plasmoidItem.functionName(fn) : ""
        readonly property string command: !fn ? ""
            : full.plasmoidItem.commandFor(fn.type === "toggle" ? (turnOn ? fn.onCommand : fn.offCommand) : fn.command, server)

        function ask(server, fn, turnOn) {
            this.server = server;
            this.fn = fn;
            this.turnOn = turnOn;
            open();
        }

        title: !fn ? ""
            : fn.type !== "toggle" ? i18nc("@title:window, %1 function, %2 server", "Run “%1” on %2?", functionName, server.name)
            : turnOn ? i18nc("@title:window, %1 function, %2 server", "Turn on “%1” on %2?", functionName, server.name)
            : i18nc("@title:window, %1 function, %2 server", "Turn off “%1” on %2?", functionName, server.name)
        subtitle: i18n("This runs: %1", command)
        preferredWidth: Math.min(Kirigami.Units.gridUnit * 18, full.width - Kirigami.Units.gridUnit * 2)
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

        onAccepted: full.plasmoidItem.runFunction(server, fn, turnOn)
    }
}
