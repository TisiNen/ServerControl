import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "code/model.js" as Model

// Settings page "Servers": the server list on the left, the selected
// server's fields and functions on the right.
//
// The page works on `servers`, a parsed copy of the config. Every edit
// replaces it with a changed copy and writes the JSON to `cfg_servers`,
// which enables Apply. Plasma saves `cfg_servers` on Apply or OK.
KCM.SimpleKCM {
    id: page

    // Set by Plasma from the `servers` config key and its default.
    property string cfg_servers
    property string cfg_serversDefault

    property var servers: []
    // Problems found when the saved config was parsed. Saving writes the
    // fixed list, so they go away on Apply.
    property var loadWarnings: []
    property int currentServerIndex: -1
    property int currentFunctionIndex: -1

    readonly property var currentServer: servers[currentServerIndex] || null
    readonly property var currentFunction: currentServer ? currentServer.functions[currentFunctionIndex] || null : null

    // The JSON this page wrote last, to tell its own changes of
    // cfg_servers from outside ones (e.g. the Defaults button).
    property string _written: ""

    function load() {
        const parsed = Model.parseServers(cfg_servers);
        _written = cfg_servers;
        servers = parsed.servers;
        loadWarnings = parsed.warnings;
        selectServer(servers.length > 0 ? 0 : -1);
    }

    Component.onCompleted: load()
    onCfg_serversChanged: {
        if (cfg_servers !== _written) {
            load();
        }
    }

    // Calls change(list) on a copy of `servers`, then stores the copy.
    function edit(change) {
        const next = Model.copyServers(servers);
        change(next);
        servers = next;
        _written = Model.serializeServers(next);
        cfg_servers = _written;
    }

    function selectServer(index) {
        currentServerIndex = index;
        const server = servers[index];
        currentFunctionIndex = server && server.functions.length > 0 ? 0 : -1;
    }

    function addServer() {
        edit(list => list.push(Model.newServer(i18n("New server"), list)));
        selectServer(servers.length - 1);
        serverName.forceActiveFocus();
        serverName.selectAll();
    }

    function removeServer(index) {
        edit(list => list.splice(index, 1));
        selectServer(Math.min(index, servers.length - 1));
    }

    // The index `selected` has after moving `index` by `delta`: the
    // selection follows the selected item, wherever it moves.
    function indexAfterMove(selected, index, delta) {
        return selected === index ? index + delta : selected === index + delta ? index : selected;
    }

    function moveServer(index, delta) {
        if (index + delta < 0 || index + delta >= servers.length) {
            return;
        }
        edit(list => Model.moveItem(list, index, index + delta));
        currentServerIndex = indexAfterMove(currentServerIndex, index, delta);
    }

    function setServerField(key, value) {
        edit(list => {
            list[currentServerIndex][key] = value;
        });
    }

    function addFunction(type) {
        edit(list => list[currentServerIndex].functions.push(Model.newFunction(type, i18n("New function"), list)));
        currentFunctionIndex = currentServer.functions.length - 1;
    }

    function removeFunction(index) {
        edit(list => list[currentServerIndex].functions.splice(index, 1));
        // Keep the same function selected; if it was the removed one,
        // select the one that took its place.
        const selected = currentFunctionIndex > index ? currentFunctionIndex - 1 : currentFunctionIndex;
        currentFunctionIndex = Math.min(selected, currentServer.functions.length - 1);
    }

    function moveFunction(index, delta) {
        if (index + delta < 0 || index + delta >= currentServer.functions.length) {
            return;
        }
        edit(list => Model.moveItem(list[currentServerIndex].functions, index, index + delta));
        currentFunctionIndex = indexAfterMove(currentFunctionIndex, index, delta);
    }

    function setFunctionField(key, value) {
        edit(list => {
            list[currentServerIndex].functions[currentFunctionIndex][key] = value;
        });
    }

    function setFunctionType(type) {
        edit(list => {
            const fns = list[currentServerIndex].functions;
            fns[currentFunctionIndex] = Model.changeFunctionType(fns[currentFunctionIndex], type);
        });
    }

    function serverLabel(server) {
        return server.name || server.host || i18n("Unnamed server");
    }

    function typeLabel(type) {
        switch (type) {
        case "status":
            return i18nc("function type", "Status");
        case "action":
            return i18nc("function type", "Action");
        default:
            return i18nc("function type", "Toggle");
        }
    }

    // Id of the current server's first status function, "" if none.
    readonly property string primaryStatusId: {
        const fn = currentServer ? Model.statusFunction(currentServer) : null;
        return fn ? fn.id : "";
    }

    // The small icon-only buttons of the lists; the text shows as tooltip.
    component ListToolButton: QQC2.ToolButton {
        display: QQC2.AbstractButton.IconOnly
        QQC2.ToolTip.text: text
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.loadWarnings.length > 0
            type: Kirigami.MessageType.Warning
            text: i18np("The saved settings had %1 problem. Invalid entries were fixed or left out, and are saved that way when you apply.",
                        "The saved settings had %1 problems. Invalid entries were fixed or left out, and are saved that way when you apply.",
                        page.loadWarnings.length)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            // ---- Server list ----
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                Layout.maximumWidth: Kirigami.Units.gridUnit * 11
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    level: 4
                    text: i18nc("@title", "Servers")
                }

                QQC2.Frame {
                    Layout.fillWidth: true
                    padding: 1

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: page.servers

                            delegate: QQC2.ItemDelegate {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                text: page.serverLabel(modelData)
                                icon.name: "network-server"
                                highlighted: index === page.currentServerIndex
                                onClicked: page.selectServer(index)
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            visible: page.servers.length === 0
                            text: i18n("No servers")
                            opacity: 0.7
                        }
                    }
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        icon.name: "list-add"
                        text: i18nc("@action:button", "Add")
                        onClicked: page.addServer()
                    }

                    ListToolButton {
                        icon.name: "go-up"
                        text: i18nc("@action:button", "Move up")
                        enabled: page.currentServerIndex > 0
                        onClicked: page.moveServer(page.currentServerIndex, -1)
                    }

                    ListToolButton {
                        icon.name: "go-down"
                        text: i18nc("@action:button", "Move down")
                        enabled: page.currentServerIndex >= 0 && page.currentServerIndex < page.servers.length - 1
                        onClicked: page.moveServer(page.currentServerIndex, 1)
                    }

                    ListToolButton {
                        icon.name: "edit-delete"
                        text: i18nc("@action:button", "Remove server")
                        enabled: page.currentServer !== null
                        onClicked: page.removeServer(page.currentServerIndex)
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillHeight: true
            }

            // ---- Selected server ----
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit * 4
                    visible: page.currentServer === null
                    icon.name: "network-server"
                    text: i18n("No servers yet")
                    explanation: i18n("Click “Add” to create the first one.")
                }

                Kirigami.FormLayout {
                    id: serverForm

                    Layout.fillWidth: true
                    visible: page.currentServer !== null

                    QQC2.TextField {
                        id: serverName

                        Kirigami.FormData.label: i18nc("@label:textbox", "Name:")
                        Layout.fillWidth: true
                        text: page.currentServer ? page.currentServer.name : ""
                        placeholderText: i18n("Shown in the popup; the host if empty")
                        onTextEdited: page.setServerField("name", text)
                    }

                    QQC2.TextField {
                        Kirigami.FormData.label: i18nc("@label:textbox", "Host:")
                        Layout.fillWidth: true
                        text: page.currentServer ? page.currentServer.host : ""
                        placeholderText: i18n("Host name or IP address, e.g. 192.168.1.10")
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        onTextEdited: page.setServerField("host", text.trim())
                    }

                    QQC2.TextField {
                        Kirigami.FormData.label: i18nc("@label:textbox", "MAC address:")
                        Layout.fillWidth: true
                        text: page.currentServer ? page.currentServer.mac : ""
                        placeholderText: i18n("For Wake-on-LAN, e.g. aa:bb:cc:dd:ee:ff")
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        onTextEdited: page.setServerField("mac", text.trim())
                    }

                    QQC2.TextField {
                        Kirigami.FormData.label: i18nc("@label:textbox", "SSH user:")
                        Layout.fillWidth: true
                        text: page.currentServer ? page.currentServer.user : ""
                        placeholderText: i18n("Used by {ssh}; your own user name if empty")
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        onTextEdited: page.setServerField("user", text.trim())
                    }

                    Kirigami.Separator {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: i18nc("@title:group", "Functions")
                    }

                    // The function list, in popup order (the first status
                    // check is the server's dot, not a control).
                    QQC2.Frame {
                        Layout.fillWidth: true
                        padding: 1

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Repeater {
                                model: page.currentServer ? page.currentServer.functions : []

                                delegate: QQC2.ItemDelegate {
                                    id: fnRow

                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    highlighted: index === page.currentFunctionIndex
                                    onClicked: page.currentFunctionIndex = index

                                    contentItem: RowLayout {
                                        spacing: Kirigami.Units.smallSpacing

                                        Kirigami.Icon {
                                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                            source: fnRow.modelData.icon
                                        }

                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: fnRow.modelData.name || i18n("Unnamed function")
                                            elide: Text.ElideRight
                                        }

                                        QQC2.Label {
                                            text: fnRow.modelData.id === page.primaryStatusId ? i18n("Online/Server state")
                                                : page.typeLabel(fnRow.modelData.type)
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.7
                                        }

                                        ListToolButton {
                                            icon.name: "go-up"
                                            text: i18nc("@action:button", "Move up")
                                            enabled: fnRow.index > 0
                                            onClicked: page.moveFunction(fnRow.index, -1)
                                        }

                                        ListToolButton {
                                            icon.name: "go-down"
                                            text: i18nc("@action:button", "Move down")
                                            enabled: fnRow.index < page.currentServer.functions.length - 1
                                            onClicked: page.moveFunction(fnRow.index, 1)
                                        }

                                        ListToolButton {
                                            icon.name: "edit-delete"
                                            text: i18nc("@action:button", "Remove function")
                                            onClicked: page.removeFunction(fnRow.index)
                                        }
                                    }
                                }
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                Layout.margins: Kirigami.Units.largeSpacing
                                visible: page.currentServer !== null && page.currentServer.functions.length === 0
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                                text: i18n("No functions. Without a status check, the server has no online state.")
                                wrapMode: Text.Wrap
                                opacity: 0.7
                            }
                        }
                    }

                    QQC2.Button {
                        id: addFunctionButton

                        icon.name: "list-add"
                        text: i18nc("@action:button", "Add Function")
                        onClicked: addFunctionMenu.popup(addFunctionButton, 0, height)

                        QQC2.Menu {
                            id: addFunctionMenu

                            QQC2.MenuItem {
                                text: i18n("Status check")
                                icon.name: "network-connect"
                                onTriggered: page.addFunction("status")
                            }
                            QQC2.MenuItem {
                                text: i18n("Action (a button)")
                                icon.name: "system-run"
                                onTriggered: page.addFunction("action")
                            }
                            QQC2.MenuItem {
                                text: i18n("Toggle (an on/off switch)")
                                icon.name: "system-run"
                                onTriggered: page.addFunction("toggle")
                            }
                        }
                    }
                }

                FunctionEditor {
                    Layout.fillWidth: true
                    visible: page.currentFunction !== null
                    twinFormLayouts: [serverForm]
                    // A placeholder keeps the bindings valid while nothing
                    // is selected; the editor is hidden then.
                    fn: page.currentFunction || { type: "action", name: "", icon: "" }
                    server: page.currentServer || {}
                    primaryStatus: page.currentFunction !== null && page.currentFunction.id === page.primaryStatusId
                    onFieldEdited: (key, value) => page.setFunctionField(key, value)
                    onTypeSelected: type => page.setFunctionType(type)
                }
            }
        }
    }
}
