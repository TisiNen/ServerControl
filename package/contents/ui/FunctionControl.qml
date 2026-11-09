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
    // See functionResults in main.qml. null when there is nothing to show.
    readonly property var result: plasmoidItem.functionResults[key] || null
    // Show ✓ / ✗ in place of the icon or handle. A toggle shows only ✗: on
    // success, the switch itself moving to the new state is the feedback.
    readonly property bool showResult: result !== null && !running
        && (fn.type === "action" || !result.ok)
    // Whether the control looks clickable. It stays so while its result
    // shows, even if the function just became unavailable: after Wake, the
    // server comes online during the ✓, and greying out the button then
    // would look as if Wake had failed. Clicks are still ignored then.
    readonly property bool looksEnabled: !running && (unavailableReason === "" || showResult)
    // A toggle whose state command timed out. It stays clickable, but a
    // click reads the state again instead of switching (see retryToggle()).
    readonly property bool stateUnknown: fn.type === "toggle" && fnState === "unknown"
        && unavailableReason === "" && !running && !showResult

    readonly property string toolTipText: {
        // The full error output; the line under the server shows only the end.
        if (showResult && !result.ok && result.stderr !== "") {
            return result.stderr.length > 500 ? result.stderr.slice(0, 500) + "…" : result.stderr;
        }
        switch (unavailableReason) {
        case "needsOnline":
            return i18n("Available only while %1 is online", server.name);
        case "needsOffline":
            return i18n("Available only while %1 is offline", server.name);
        case "unknown":
            return i18n("Waiting for the status of %1", server.name);
        }
        if (stateUnknown) {
            return i18n("Current state unknown: the check timed out. Click to check again.");
        }
        return "";
    }

    // The height the content needs. The server row sets rowHeight to the
    // largest contentHeight of its controls: buttons, switches and labels
    // differ in height, and Flow aligns its items at the top.
    readonly property real contentHeight: layout.implicitHeight
    property real rowHeight: 0

    implicitWidth: layout.implicitWidth
    implicitHeight: Math.max(contentHeight, rowHeight)

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.smallSpacing

        // Extra status function: a dot like the server's, plus the name.
        Rectangle {
            visible: control.fn.type === "status"
            Layout.alignment: Qt.AlignVCenter
            // Buttons and switches bring their own padding; the indicator
            // has none, so it gets margins to keep it from crowding them.
            Layout.leftMargin: Kirigami.Units.largeSpacing
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
            Layout.rightMargin: Kirigami.Units.largeSpacing
            text: control.plasmoidItem.functionName(control.fn)
        }

        // While a command runs, a spinner takes the place of the button's
        // icon or the switch's handle; afterwards the result (✓ / ✗) does.
        // Both keep their size, so the row doesn't reflow.
        PlasmaComponents3.ToolButton {
            id: button

            visible: control.fn.type === "action"
            enabled: control.looksEnabled
            // An empty icon name would remove the icon and shrink the button;
            // a blank image keeps its space for the spinner.
            icon.name: control.running || control.showResult ? "" : control.fn.icon
            icon.source: Qt.resolvedUrl("../images/blank.svg")
            text: control.plasmoidItem.functionName(control.fn)
            onClicked: {
                if (control.unavailableReason === "") {
                    control.activated(true);
                }
            }

            PlasmaComponents3.BusyIndicator {
                // Where the button draws its icon: flat buttons use smallMedium.
                x: button.leftPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                visible: control.running
                running: visible
            }

            ResultIcon {
                x: button.leftPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                result: control.showResult ? control.result : null
            }
        }

        PlasmaComponents3.Switch {
            id: toggleSwitch

            visible: control.fn.type === "toggle"
            enabled: control.looksEnabled
            text: control.plasmoidItem.functionName(control.fn)
            checked: control.fnState === "on"
            // Fade the handle out rather than hiding it: the switch places its
            // text after a visible indicator, so `visible: false` would move it.
            // The spinner, the result or the warning icon below takes its place.
            indicator.opacity: control.running || control.showResult || control.stateUnknown ? 0 : 1
            onToggled: {
                const turnOn = checked;
                // Clicking set `checked` directly, which removed the binding
                // above. Restore it: the switch shows the real state, which
                // is read again after the command has run.
                checked = Qt.binding(() => control.fnState === "on");
                if (control.unavailableReason !== "") {
                    return; // only looks enabled, see looksEnabled
                }
                if (control.stateUnknown) {
                    // No confirmation: reading the state changes nothing.
                    control.plasmoidItem.retryToggle(control.server, control.fn);
                } else {
                    control.activated(turnOn);
                }
            }

            PlasmaComponents3.BusyIndicator {
                anchors.centerIn: toggleSwitch.indicator
                width: toggleSwitch.indicator.height
                height: width
                visible: control.running
                running: visible
            }

            // State unknown: a warning sign instead of the handle, so it
            // looks neither like a working switch nor like a disabled one.
            Kirigami.Icon {
                anchors.centerIn: toggleSwitch.indicator
                width: toggleSwitch.indicator.height
                height: width
                source: "dialog-warning"
                visible: control.stateUnknown
            }

            ResultIcon {
                anchors.centerIn: toggleSwitch.indicator
                width: toggleSwitch.indicator.height
                height: width
                result: control.showResult ? control.result : null
            }
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
