import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "code/commands.js" as Commands

// Settings page "General": settings that apply to all servers.
// The controls are bound to the cfg_ properties and write them directly;
// Plasma saves them on Apply or OK.
KCM.SimpleKCM {
    id: page

    property int cfg_defaultInterval
    property int cfg_defaultIntervalDefault
    property string cfg_sshOptions
    property string cfg_sshOptionsDefault
    // Not edited here. Declared because Plasma passes every config key to
    // every page, and an undeclared one logs a warning.
    property string cfg_servers
    property string cfg_serversDefault

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
    }
}
