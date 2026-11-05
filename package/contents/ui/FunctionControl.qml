import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

import "code/model.js" as Model

// One function of a server in the popup: a small indicator for an extra
// status function, a button for an action, a switch for a toggle.
Item {
    id: control

    required property var server
    required property var fn
    required property PlasmoidItem plasmoidItem

    // The user asked to run the function. For a toggle, `turnOn` is the
    // wanted state; for an action it is always true. Whoever handles this
    // shows the confirmation dialog if the function needs one.
    signal activated(bool turnOn)

    readonly property string key: Model.functionKey(server, fn)
    // See functionStates in main.qml. "" means not read yet.
    readonly property string fnState: plasmoidItem.functionStates[key] || ""
    readonly property bool running: plasmoidItem.runningFunctions[key] === true
    readonly property string unavailableReason:
        Model.unavailableReason(fn, server, plasmoidItem.serverStates[server.id] || "")

    readonly property string toolTipText: {
        switch (unavailableReason) {
        case "needsOnline":
            return i18n("Available only while %1 is online", server.name);
        case "needsOffline":
            return i18n("Available only while %1 is offline", server.name);
        case "unknown":
            return i18n("Waiting for the status of %1", server.name);
        }
        if (fn.type === "toggle" && fnState === "unknown") {
            return i18n("Current state unknown: the check timed out");
        }
        return "";
    }

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    RowLayout {
        id: layout

        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // Extra status function: a dot like the server's, plus the name.
        Rectangle {
            visible: control.fn.type === "status"
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.gridUnit * 0.5
            implicitHeight: implicitWidth
            radius: width / 2
            color: control.fnState === "ok" ? Kirigami.Theme.positiveTextColor
                : control.fnState === "fail" ? Kirigami.Theme.disabledTextColor
                : "transparent"
            border.width: control.fnState === "" ? 1 : 0
            border.color: Kirigami.Theme.disabledTextColor
        }

        PlasmaComponents3.Label {
            visible: control.fn.type === "status"
            text: control.plasmoidItem.functionName(control.fn)
            font: Kirigami.Theme.smallFont
        }

        PlasmaComponents3.ToolButton {
            visible: control.fn.type === "action"
            enabled: control.unavailableReason === "" && !control.running
            icon.name: control.fn.icon
            text: control.plasmoidItem.functionName(control.fn)
            onClicked: control.activated(true)
        }

        PlasmaComponents3.Switch {
            visible: control.fn.type === "toggle"
            enabled: control.unavailableReason === "" && !control.running
            text: control.plasmoidItem.functionName(control.fn)
            checked: control.fnState === "on"
            onToggled: {
                const turnOn = checked;
                // Clicking set `checked` directly, which removed the binding
                // above. Restore it: the switch shows the real state, which
                // is read again after the command has run.
                checked = Qt.binding(() => control.fnState === "on");
                control.activated(turnOn);
            }
        }

        PlasmaComponents3.BusyIndicator {
            visible: control.running
            running: visible
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
    }

    // Disabled controls get no hover events, so a tooltip on the button
    // itself would never show why it is disabled. The HoverHandler sits on
    // this enabled wrapper instead.
    HoverHandler {
        id: hover
    }

    PlasmaComponents3.ToolTip {
        text: control.toolTipText
        visible: hover.hovered && text !== ""
        delay: Kirigami.Units.toolTipDelay
    }
}
