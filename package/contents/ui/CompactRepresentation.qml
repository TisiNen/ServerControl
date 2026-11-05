import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

MouseArea {
    id: compact

    required property PlasmoidItem plasmoidItem

    // Remember the state at press time, so a click on the icon while the
    // popup is open closes it instead of closing and reopening it.
    property bool wasExpanded: false

    readonly property color dotColor: plasmoidItem.overallState === "all" ? Kirigami.Theme.positiveTextColor
        : plasmoidItem.overallState === "some" ? Kirigami.Theme.neutralTextColor
        : Kirigami.Theme.disabledTextColor

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    onPressed: wasExpanded = plasmoidItem.expanded
    onClicked: plasmoidItem.expanded = !wasExpanded

    // While an action runs, the icon dims and a spinner turns over it.
    // The dot stays, so the servers' state is always visible.
    Kirigami.Icon {
        anchors.fill: parent
        source: Plasmoid.icon
        active: compact.containsMouse
        opacity: compact.plasmoidItem.busy ? 0.4 : 1
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        width: Math.round(Math.min(compact.width, compact.height) * 0.7)
        height: width
        running: compact.plasmoidItem.busy
        visible: running
    }

    // Declared last, so it is drawn on top of the spinner.
    Rectangle {
        id: dot

        width: Math.max(6, Math.round(Math.min(compact.width, compact.height) * 0.4))
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: compact.dotColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 1
    }
}
