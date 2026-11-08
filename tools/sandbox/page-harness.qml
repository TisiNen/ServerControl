// Test harness for settings pages, used by load-test.sh --page.
// It replaces main.qml in a copy of the package: plasmoidviewer never opens
// the settings dialog, so this widget shows the page itself, sets its cfg_
// properties like Plasma does, and calls the page's edit functions one step
// at a time. QML errors on the way end up in the load test's report.
// @PAGE@ and @SCREENSHOTS@ are replaced by load-test.sh.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    fullRepresentation: Rectangle {
        id: frame

        Layout.preferredWidth: 860
        Layout.preferredHeight: 900
        color: Kirigami.Theme.backgroundColor

        property int step: 0
        property var steps: []

        // A fixed size: plasmoidviewer shows the applet small, but the
        // screenshots render the loader at its own size.
        Loader {
            id: loader

            width: 860
            height: 900
            Component.onCompleted: setSource("@PAGE@.qml", {
                cfg_servers: Plasmoid.configuration.servers,
                cfg_serversDefault: "[]"
            })
            onLoaded: frame.steps = frame.makeSteps(item)
        }

        // Each step is [name, function]. Pages without the functions get
        // only the first screenshot.
        function makeSteps(page) {
            const steps = [["loaded", () => {}]];
            if (typeof page.selectServer !== "function") {
                return steps;
            }
            for (let s = 0; s < page.servers.length; s++) {
                for (let f = 0; f < Math.max(1, page.servers[s].functions.length); f++) {
                    steps.push(["server" + s + "-fn" + f, () => {
                        page.selectServer(s);
                        page.currentFunctionIndex = page.servers[s].functions.length > 0 ? f : -1;
                    }]);
                }
            }
            steps.push(["add-server", () => page.addServer()]);
            steps.push(["add-status", () => {
                page.setServerField("host", "example.invalid");
                page.addFunction("status");
            }]);
            steps.push(["add-action", () => page.addFunction("action")]);
            steps.push(["add-toggle", () => page.addFunction("toggle")]);
            steps.push(["placeholders", () => page.setFunctionField("stateCommand", "{ssh} test -f {path} && wol {mac}")]);
            steps.push(["type-to-action", () => page.setFunctionType("action")]);
            steps.push(["move-remove", () => {
                page.moveFunction(2, -1);
                page.removeFunction(0);
                page.moveServer(page.currentServerIndex, -1);
            }]);
            steps.push(["remove-all", () => {
                while (page.servers.length > 0) {
                    page.removeServer(0);
                }
            }]);
            return steps;
        }

        Timer {
            interval: 400
            repeat: true
            running: frame.steps.length > 0
            onTriggered: {
                if (frame.step >= frame.steps.length) {
                    stop();
                    return;
                }
                const [name, run] = frame.steps[frame.step];
                const n = frame.step;
                frame.step++;
                run();
                if (@SCREENSHOTS@) {
                    Qt.callLater(() => loader.grabToImage(result => result.saveToFile(
                        "/out/" + String(n).padStart(2, "0") + "-" + name + ".png")));
                }
            }
        }
    }
}
