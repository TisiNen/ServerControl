import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "code/model.js" as Model
import "code/templates.js" as Templates

// Settings page "Servers": the server list on the left, the selected
// server's fields and functions on the right.
//
// The page works on `servers`, a parsed copy of the config. Every edit
// replaces it with a changed copy and writes the JSON to `cfg_servers`,
// which enables Apply. Plasma saves `cfg_servers` on Apply or OK.
KCM.SimpleKCM {
    id: page

    // Set by Plasma from the config keys and their defaults. This page
    // edits `servers` and reads the General settings for the editor.
    property string cfg_servers
    property string cfg_serversDefault
    property int cfg_defaultInterval
    property int cfg_defaultIntervalDefault
    property string cfg_sshOptions
    property string cfg_sshOptionsDefault
    property bool cfg_tailscaleEnabled
    property bool cfg_tailscaleEnabledDefault
    property string cfg_tailscaleCommand
    property string cfg_tailscaleCommandDefault
    property string cfg_icon
    property string cfg_iconDefault

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

    // Adds a function from a template in templates.js and selects it.
    function addFunction(templateId) {
        const names = {
            ping: i18nc("default name of a ping status check", "Online"),
            wake: i18nc("default name of a Wake-on-LAN action", "Wake"),
            poweroff: i18nc("default name of a power off action", "Power off"),
            reboot: i18nc("default name of a reboot action", "Reboot"),
            custom: i18n("New function")
        };
        edit(list => list[currentServerIndex].functions.push(
            Templates.fromTemplate(templateId, names[templateId], list)));
        currentFunctionIndex = currentServer.functions.length - 1;
    }

    // Adds a flag toggle for the file at `path` on the server. Without a
    // name, the file name is used.
    function addFlagToggle(path, name) {
        const fnName = name.trim() || Templates.flagName(path) || i18n("Flag");
        edit(list => list[currentServerIndex].functions.push(
            Templates.flagToggle(path.trim(), fnName, list)));
        currentFunctionIndex = currentServer.functions.length - 1;
    }

    // Opens the dialog that asks for the flag file's path.
    function askFlagPath() {
        flagPath.text = "";
        flagName.text = "";
        flagDialog.open();
        flagPath.forceActiveFocus();
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

    // `value` undefined removes the field, e.g. `interval` to use the default.
    function setFunctionField(key, value) {
        edit(list => {
            const fn = list[currentServerIndex].functions[currentFunctionIndex];
            if (value === undefined) {
                delete fn[key];
            } else {
                fn[key] = value;
            }
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
                    icon.name: "network-server-symbolic"
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
                        Kirigami.FormData.label: i18nc("@label:textbox", "Tailscale host:")
                        Layout.fillWidth: true
                        // Only with Tailscale support on (General page). A
                        // host set earlier is kept while it is hidden.
                        visible: page.cfg_tailscaleEnabled
                        text: page.currentServer ? page.currentServer.tailscaleHost || "" : ""
                        placeholderText: i18n("Tailscale IP or MagicDNS name; not reachable over Tailscale if empty")
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        onTextEdited: page.setServerField("tailscaleHost", text.trim())
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
                                text: i18n("Status (ping)")
                                icon.name: "network-connect"
                                onTriggered: page.addFunction("ping")
                            }
                            QQC2.MenuItem {
                                text: i18n("Wake-on-LAN")
                                icon.name: "system-run"
                                onTriggered: page.addFunction("wake")
                            }
                            QQC2.MenuItem {
                                text: i18n("Power off")
                                icon.name: "system-shutdown"
                                onTriggered: page.addFunction("poweroff")
                            }
                            QQC2.MenuItem {
                                text: i18n("Reboot")
                                icon.name: "system-reboot"
                                onTriggered: page.addFunction("reboot")
                            }
                            QQC2.MenuItem {
                                text: i18n("Flag toggle…")
                                icon.name: "flag"
                                onTriggered: page.askFlagPath()
                            }
                            QQC2.MenuSeparator {}
                            QQC2.MenuItem {
                                text: i18nc("an empty function", "Custom")
                                icon.name: "document-new"
                                onTriggered: page.addFunction("custom")
                            }
                        }

                        // Asks for the flag file of a new flag toggle.
                        Kirigami.Dialog {
                            id: flagDialog

                            readonly property bool valid: flagPath.text.trim() !== ""

                            function add() {
                                if (valid) {
                                    page.addFlagToggle(flagPath.text, flagName.text);
                                    close();
                                }
                            }

                            title: i18nc("@title:window", "Add Flag Toggle")
                            padding: Kirigami.Units.largeSpacing
                            preferredWidth: Kirigami.Units.gridUnit * 24
                            standardButtons: QQC2.Dialog.Cancel
                            customFooterActions: [
                                Kirigami.Action {
                                    icon.name: "list-add"
                                    text: i18nc("@action:button", "Add")
                                    enabled: flagDialog.valid
                                    onTriggered: flagDialog.add()
                                }
                            ]

                            ColumnLayout {
                                spacing: Kirigami.Units.largeSpacing

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: i18n("A switch that is on while a file exists on the server. Turning it on creates the file with touch, turning it off removes it. The commands run over {ssh}.")
                                    wrapMode: Text.Wrap
                                }

                                Kirigami.FormLayout {
                                    Layout.fillWidth: true

                                    QQC2.TextField {
                                        id: flagPath

                                        Kirigami.FormData.label: i18nc("@label:textbox", "File on the server:")
                                        Layout.fillWidth: true
                                        placeholderText: i18n("Absolute path, e.g. /var/lib/nightly/skip-alarm")
                                        font: Kirigami.Theme.fixedWidthFont
                                        onAccepted: flagDialog.add()
                                    }

                                    QQC2.TextField {
                                        id: flagName

                                        Kirigami.FormData.label: i18nc("@label:textbox", "Name:")
                                        Layout.fillWidth: true
                                        placeholderText: Templates.flagName(flagPath.text) || i18n("The file name if empty")
                                        onAccepted: flagDialog.add()
                                    }
                                }
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
                    defaultInterval: page.cfg_defaultInterval
                    sshOptions: page.cfg_sshOptions
                    tailscaleEnabled: page.cfg_tailscaleEnabled
                    primaryStatus: page.currentFunction !== null && page.currentFunction.id === page.primaryStatusId
                    onFieldEdited: (key, value) => page.setFunctionField(key, value)
                    onTypeSelected: type => page.setFunctionType(type)
                }
            }
        }
    }
}
