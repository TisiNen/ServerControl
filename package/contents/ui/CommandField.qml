import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "code/commands.js" as Commands

// A text field for one shell command, used in the settings. Below it: the
// command as it will run on this server, and a warning for unknown
// placeholders or placeholders whose server field is empty.
ColumnLayout {
    id: field

    required property var server
    required property string command
    property string placeholderText: ""

    // Emitted on every keystroke with the new text.
    signal edited(string text)

    readonly property var unknown: Commands.unknownPlaceholders(command)
    readonly property var empty: Commands.emptyPlaceholders(command, server)

    spacing: 0

    QQC2.TextField {
        Layout.fillWidth: true
        // Commands are long; this widens the whole form.
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        text: field.command
        placeholderText: field.placeholderText
        font: Kirigami.Theme.fixedWidthFont
        onTextEdited: field.edited(text)
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: field.command !== ""
        // Wrapped labels report their unwrapped width as implicit width,
        // which would widen the whole form; fillWidth gives them the rest.
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        text: Commands.substitute(field.command, field.server)
        font: Kirigami.Theme.fixedWidthFont
        opacity: 0.7
        wrapMode: Text.WrapAnywhere
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
