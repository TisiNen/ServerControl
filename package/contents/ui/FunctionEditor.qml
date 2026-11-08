import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

// The settings form for one function. It doesn't change `fn` itself: each
// edit is reported with a signal and ConfigServers.qml writes it into its
// copy of the config. Fields of other types are hidden, not destroyed.
Kirigami.FormLayout {
    id: editor

    required property var fn
    required property var server
    // The server's first status function decides its online state.
    required property bool primaryStatus
    // From the General settings.
    required property int defaultInterval
    required property string sshOptions

    signal fieldEdited(string key, var value)
    signal typeSelected(string type)

    readonly property bool isStatus: fn.type === "status"
    readonly property bool isAction: fn.type === "action"
    readonly property bool isToggle: fn.type === "toggle"

    // Index of the entry with `value` in a ComboBox model, 0 if none.
    function indexOf(model, value) {
        return Math.max(0, model.findIndex(entry => entry.value === value));
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Name:")
        Layout.fillWidth: true
        text: editor.fn.name
        placeholderText: i18n("Shown on the button or switch")
        onTextEdited: editor.fieldEdited("name", text)
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nc("@label:listbox", "Type:")
        model: [
            { value: "status", text: i18n("Status check") },
            { value: "action", text: i18n("Action (a button)") },
            { value: "toggle", text: i18n("Toggle (an on/off switch)") }
        ]
        textRole: "text"
        valueRole: "value"
        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
        currentIndex: editor.indexOf(model, editor.fn.type)
        onActivated: editor.typeSelected(currentValue)
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        visible: editor.isStatus
        text: editor.primaryStatus
            ? i18n("The first status check decides whether the server is online (exit code 0).")
            : i18n("An additional check: shows as a small ok/failed indicator and doesn't change the online/server state.")
        font: Kirigami.Theme.smallFont
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    RowLayout {
        Kirigami.FormData.label: i18nc("@label", "Icon:")
        Layout.fillWidth: true

        QQC2.Button {
            // Found and clicked by the sandbox test (page-harness.qml).
            objectName: "chooseIconButton"
            icon.name: editor.fn.icon
            text: i18nc("@action:button", "Choose…")
            onClicked: iconDialog.open()
        }

        QQC2.TextField {
            Layout.fillWidth: true
            text: editor.fn.icon
            font.family: Kirigami.Theme.fixedWidthFont.family
            onTextEdited: editor.fieldEdited("icon", text)
        }
    }

    // KDE's icon picker, a separate window. `iconName` is read-only and
    // keeps the last pick, so picking the same icon again for another
    // function doesn't change it. `accepted` covers that case; the change
    // handler covers the case that `accepted` comes before the new name.
    // Applying the same icon twice changes nothing.
    KIconThemes.IconDialog {
        id: iconDialog

        function apply() {
            if (iconName !== "") {
                editor.fieldEdited("icon", iconName);
            }
        }

        onIconNameChanged: apply()
        onAccepted: apply()
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18nc("@title:group", "Commands")
    }

    CommandField {
        Kirigami.FormData.label: editor.isStatus ? i18nc("@label:textbox", "Check:")
            : i18nc("@label:textbox", "Command:")
        Layout.fillWidth: true
        visible: editor.isStatus || editor.isAction
        server: editor.server
        sshOptions: editor.sshOptions
        command: editor.fn.command || ""
        placeholderText: editor.isStatus ? i18n("Exit code 0 means online") : ""
        onEdited: text => editor.fieldEdited("command", text)
    }

    CommandField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Verify:")
        Layout.fillWidth: true
        visible: editor.isAction
        server: editor.server
        sshOptions: editor.sshOptions
        command: editor.fn.verifyCommand || ""
        placeholderText: i18n("Optional; its exit code decides success")
        onEdited: text => editor.fieldEdited("verifyCommand", text)
    }

    CommandField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Read state:")
        Layout.fillWidth: true
        visible: editor.isToggle
        server: editor.server
        sshOptions: editor.sshOptions
        command: editor.fn.stateCommand || ""
        placeholderText: i18n("Exit code 0 means on")
        onEdited: text => editor.fieldEdited("stateCommand", text)
    }

    CommandField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Turn on:")
        Layout.fillWidth: true
        visible: editor.isToggle
        server: editor.server
        sshOptions: editor.sshOptions
        command: editor.fn.onCommand || ""
        onEdited: text => editor.fieldEdited("onCommand", text)
    }

    CommandField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Turn off:")
        Layout.fillWidth: true
        visible: editor.isToggle
        server: editor.server
        sshOptions: editor.sshOptions
        command: editor.fn.offCommand || ""
        onEdited: text => editor.fieldEdited("offCommand", text)
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        text: i18n("Placeholders: {host} {mac} {user} {name} {ssh}. The grey line under a command shows what will run.")
        font: Kirigami.Theme.smallFont
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18nc("@title:group", "Behavior")
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nc("@label:listbox", "Available:")
        visible: !editor.isStatus
        model: [
            { value: "always", text: i18n("Always") },
            { value: "online", text: i18n("When the server is online") },
            { value: "offline", text: i18n("When the server is offline") }
        ]
        textRole: "text"
        valueRole: "value"
        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
        currentIndex: editor.indexOf(model, editor.fn.availableWhen)
        onActivated: editor.fieldEdited("availableWhen", currentValue)
    }

    QQC2.CheckBox {
        visible: !editor.isStatus
        text: i18n("Ask for confirmation before running")
        checked: editor.fn.confirm === true
        onToggled: editor.fieldEdited("confirm", checked)
    }

    // Without its own `interval`, a status function uses the default from
    // the General page; the spin box then shows that value, disabled.
    RowLayout {
        Kirigami.FormData.label: i18nc("@label:spinbox", "Check every:")
        visible: editor.isStatus

        QQC2.SpinBox {
            enabled: !useDefault.checked
            from: 1
            to: 86400
            editable: true
            value: editor.fn.interval || editor.defaultInterval
            textFromValue: (value, locale) => i18ncp("@item:valuesuffix", "%1 second", "%1 seconds", value)
            valueFromText: (text, locale) => parseInt(text) || editor.defaultInterval
            onValueModified: editor.fieldEdited("interval", value)
        }

        QQC2.CheckBox {
            id: useDefault

            text: i18nc("@option:check use the default check interval", "Default")
            checked: !(editor.fn.interval > 0)
            onToggled: editor.fieldEdited("interval", checked ? undefined : editor.defaultInterval)

            QQC2.ToolTip.text: i18n("Use the default interval from the General page")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18nc("@label:spinbox", "Timeout:")
        from: 1
        to: 3600
        editable: true
        value: editor.fn.timeout || 10
        textFromValue: (value, locale) => i18ncp("@item:valuesuffix", "%1 second", "%1 seconds", value)
        valueFromText: (text, locale) => parseInt(text) || 10
        onValueModified: editor.fieldEdited("timeout", value)
    }
}
