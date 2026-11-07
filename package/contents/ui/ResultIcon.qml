import QtQuick
import org.kde.kirigami as Kirigami

// ✓ or ✗ for the result of a command (see functionResults in main.qml).
// Hidden while `result` is null.
Kirigami.Icon {
    property var result: null

    visible: result !== null
    source: result && result.ok ? "checkmark" : "dialog-close"
    // Recolours the monochrome icon.
    isMask: true
    color: result && result.ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
}
