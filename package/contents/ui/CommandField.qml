import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "code/commands.js" as Commands

// A text field for one shell command, used in the settings. Below it: the
// command as it will run on this server, and a warning for unknown
// placeholders or placeholders whose server field is empty. With Tailscale
// support on and a server with a Tailscale host, the preview shows the LAN
// and the Tailscale version when they differ.
ColumnLayout {
    id: field

    required property var server
    required property string command
    // The General setting {ssh} uses.
    property string sshOptions: Commands.DEFAULT_SSH_OPTIONS
    property string placeholderText: ""
    // The function uses {mac}, so it is disabled while Tailscale is active
    // (see Model.needsLan()).
    property bool lanOnly: false
    // The General setting tailscaleEnabled.
    property bool tailscaleEnabled: false

    // Emitted on every keystroke with the new text.
    signal edited(string text)

    readonly property var unknown: Commands.unknownPlaceholders(command)
    readonly property var empty: Commands.emptyPlaceholders(command, server)
    readonly property string lanCommand: Commands.substitute(command, server, sshOptions, false)
    readonly property string tailscaleCommand: Commands.substitute(command, server, sshOptions, true)
    // Two previews only when Tailscale changes something for this command.
    readonly property bool showBoth: tailscaleEnabled && (server.tailscaleHost || "") !== ""
        && (lanOnly || lanCommand !== tailscaleCommand)

    spacing: 0

    // The grey monospace text of the preview lines.
    component PreviewLabel: QQC2.Label {
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
        opacity: 0.7
        wrapMode: Text.WrapAnywhere
    }
    // The FormLayout label (set where the field is used) lines up with the
    // text field, not with the middle of the field plus its preview lines.
    Kirigami.FormData.buddyFor: textField

    QQC2.TextField {
        id: textField

        Layout.fillWidth: true
        // Commands are long; this widens the whole form.
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        text: field.command
        placeholderText: field.placeholderText
        font: Kirigami.Theme.fixedWidthFont
        onTextEdited: field.edited(text)
    }

    // The preview: the command alone, or a bold "LAN:" and "Tailscale:"
    // in a first column. Separate labels, not rich text, so the commands
    // show exactly as they run (no markup to escape, spaces kept), and
    // wrapped lines stay indented under the command. Invisible items take
    // no cell, so without the prefixes the command is the only one.
    GridLayout {
        Layout.fillWidth: true
        visible: field.command !== ""
        columns: 2
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 0

        PreviewLabel {
            Layout.alignment: Qt.AlignTop
            visible: field.showBoth
            text: i18nc("@info command preview on the local network", "LAN:")
            font.bold: true
            wrapMode: Text.NoWrap
        }

        PreviewLabel {
            Layout.fillWidth: true
            // Wrapped labels report their unwrapped width as implicit width,
            // which would widen the whole form; fillWidth gives them the rest.
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            text: field.lanCommand
        }

        PreviewLabel {
            Layout.alignment: Qt.AlignTop
            visible: field.showBoth
            text: i18nc("@info command preview over Tailscale", "Tailscale:")
            font.bold: true
            wrapMode: Text.NoWrap
        }

        PreviewLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            visible: field.showBoth
            text: field.lanOnly ? i18n("not available, Wake-on-LAN needs the local network")
                : field.tailscaleCommand
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        visible: text !== ""
        text: {
            const lines = [];
            if (field.unknown.length > 0) {
                lines.push(i18np("Unknown placeholder: %2", "Unknown placeholders: %2", field.unknown.length,
                                 field.unknown.map(p => "{" + p + "}").join(", ")));
            }
            if (field.empty.length > 0) {
                lines.push(i18np("Empty for this server: %2", "Empty for this server: %2", field.empty.length,
                                 field.empty.map(p => "{" + p + "}").join(", ")));
            }
            return lines.join("\n");
        }
        color: Kirigami.Theme.neutralTextColor
        font: Kirigami.Theme.smallFont
        wrapMode: Text.Wrap
    }
}
