import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "code/commands.js" as Commands
import "code/model.js" as Model

// Settings page "General": settings that apply to all servers, and import
// and export of the whole setup. The controls are bound to the cfg_
// properties and write them directly; Plasma saves them on Apply or OK.
KCM.SimpleKCM {
    id: page

    property int cfg_defaultInterval
    property int cfg_defaultIntervalDefault
    property string cfg_sshOptions
    property string cfg_sshOptionsDefault
    property bool cfg_tailscaleEnabled
    property bool cfg_tailscaleEnabledDefault
    property string cfg_tailscaleCommand
    property string cfg_tailscaleCommandDefault
    // Only written by an import. Plasma passes every config key to every
    // page, and an undeclared one logs a warning.
    property string cfg_servers
    property string cfg_serversDefault

    // The result of the last import, shown under the buttons.
    property string importMessage: ""
    property bool importFailed: false

    // Fills the text area with the current setup, as it would be saved now.
    function showCurrentSetup() {
        jsonArea.text = Model.exportSetup(Model.parseServers(cfg_servers).servers, {
            defaultInterval: cfg_defaultInterval,
            sshOptions: cfg_sshOptions,
            tailscaleEnabled: cfg_tailscaleEnabled,
            tailscaleCommand: cfg_tailscaleCommand
        });
        importMessage = "";
    }

    // Replaces the servers, and the general settings found in `text`, in
    // this dialog. Nothing is saved until Apply.
    function importText(text) {
        const setup = Model.parseSetup(text);
        importFailed = setup.error !== "";
        if (importFailed) {
            importMessage = setup.error === "invalidJson" ? i18n("This is not valid JSON: %1", setup.detail)
                : setup.error === "unsupportedVersion"
                ? i18n("This setup has version %1. This widget can only read version 1.", setup.detail)
                : i18n("No server list found. Paste a list of servers, or an exported setup with a “servers” list.");
            return;
        }

        cfg_servers = Model.serializeServers(setup.servers);
        const general = setup.general || {};
        if (general.defaultInterval !== undefined) {
            cfg_defaultInterval = general.defaultInterval;
        }
        if (general.sshOptions !== undefined) {
            cfg_sshOptions = general.sshOptions;
        }
        if (general.tailscaleEnabled !== undefined) {
            cfg_tailscaleEnabled = general.tailscaleEnabled;
        }
        if (general.tailscaleCommand !== undefined) {
            cfg_tailscaleCommand = general.tailscaleCommand;
        }
        for (const w of setup.warnings) {
            console.warn("Server Control import:", w);
        }

        const parts = [i18np("Imported %1 server.", "Imported %1 servers.", setup.servers.length)];
        if (Object.keys(general).length > 0) {
            parts.push(i18n("The general settings in it were imported too."));
        }
        if (setup.warnings.length > 0) {
            parts.push(i18np("%1 problem was fixed or left out; see the system log.",
                             "%1 problems were fixed or left out; see the system log.", setup.warnings.length));
        }
        parts.push(i18n("Apply saves the import; Cancel discards it."));
        importMessage = parts.join(" ");
    }

    Component.onCompleted: showCurrentSetup()

    Kirigami.FormLayout {
        QQC2.SpinBox {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Default check interval:")
            from: 1
            to: 86400
            editable: true
            value: page.cfg_defaultInterval
            textFromValue: (value, locale) => i18ncp("@item:valuesuffix", "%1 second", "%1 seconds", value)
            valueFromText: (text, locale) => parseInt(text) || page.cfg_defaultIntervalDefault
            onValueModified: page.cfg_defaultInterval = value
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            text: i18n("For status checks that don't set their own interval.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            opacity: 0.7
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18nc("@label:textbox", "SSH options:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            text: page.cfg_sshOptions
            font: Kirigami.Theme.fixedWidthFont
            onTextEdited: page.cfg_sshOptions = text
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            text: i18n("{ssh} in a command becomes:")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            opacity: 0.7
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            // A made-up server, only to show the shape of the command.
            text: Commands.sshCommand({ host: "host", user: "user" }, page.cfg_sshOptions)
            font: Kirigami.Theme.fixedWidthFont
            wrapMode: Text.WrapAnywhere
            opacity: 0.7
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            visible: !Commands.hasBatchMode(page.cfg_sshOptions)
            text: i18n("Without “-o BatchMode=yes”, ssh may ask for a password that nobody can enter, and the command waits until its timeout.")
            color: Kirigami.Theme.neutralTextColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18nc("@label:checkbox", "Tailscale:")
            text: i18nc("@option:check", "Enable Tailscale support")
            checked: page.cfg_tailscaleEnabled
            onToggled: page.cfg_tailscaleEnabled = checked
        }

        // The rest of the Tailscale settings show only while it is enabled.
        RowLayout {
            Kirigami.FormData.label: i18nc("@label:textbox", "Tailscale check:")
            Layout.fillWidth: true
            visible: page.cfg_tailscaleEnabled
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                text: page.cfg_tailscaleCommand
                placeholderText: i18n("Empty: Tailscale never counts as active")
                font: Kirigami.Theme.fixedWidthFont
                onTextEdited: page.cfg_tailscaleCommand = text
            }

            QQC2.ToolButton {
                icon.name: "edit-undo"
                text: i18nc("@action:button", "Reset to default")
                display: QQC2.AbstractButton.IconOnly
                enabled: page.cfg_tailscaleCommand !== page.cfg_tailscaleCommandDefault
                onClicked: page.cfg_tailscaleCommand = page.cfg_tailscaleCommandDefault
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            visible: page.cfg_tailscaleEnabled
            text: i18n("Runs with the status checks. Exit code 0 means Tailscale is active: servers are then reached at their Tailscale host, servers without one show as not reachable, and Wake-on-LAN is disabled.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            opacity: 0.7
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group", "Import and Export")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            text: i18n("The whole setup as JSON: all servers with their functions, and the settings on this page. Copy it as a backup or to another computer. To import, paste a setup or a list of servers and click Import.")
            wrapMode: Text.Wrap
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            // A fixed height, not Layout.preferredHeight: FormLayout sizes
            // its fields by their implicit size, which for a ScrollView is
            // the whole text. The text then scrolls inside.
            implicitHeight: Kirigami.Units.gridUnit * 14
            clip: true

            QQC2.TextArea {
                id: jsonArea

                font: Kirigami.Theme.fixedWidthFont
                wrapMode: TextEdit.Wrap
                placeholderText: i18n("Paste a setup here")
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                icon.name: "view-refresh"
                text: i18nc("@action:button", "Show Current Setup")
                onClicked: page.showCurrentSetup()
            }

            QQC2.Button {
                // Found and clicked by the sandbox test (page-harness.qml).
                objectName: "copySetupButton"
                icon.name: "edit-copy"
                text: i18nc("@action:button", "Copy")
                enabled: jsonArea.text !== ""
                // QML has no clipboard API; the text area copies its
                // selection.
                onClicked: {
                    jsonArea.selectAll();
                    jsonArea.copy();
                    jsonArea.deselect();
                }
            }

            QQC2.Button {
                icon.name: "document-import"
                text: i18nc("@action:button", "Import")
                enabled: jsonArea.text.trim() !== ""
                onClicked: page.importText(jsonArea.text)
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            visible: page.importMessage !== ""
            type: page.importFailed ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
            text: page.importMessage
        }
    }
}
