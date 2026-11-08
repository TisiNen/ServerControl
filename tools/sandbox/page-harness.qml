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
            // Like Plasma's settings dialog: a cfg_ property for every
            // config key.
            Component.onCompleted: {
                const props = {};
                for (const key of Plasmoid.configuration.keys()) {
                    props["cfg_" + key] = Plasmoid.configuration[key];
                }
                setSource("@PAGE@.qml", props);
            }
            onLoaded: frame.steps = frame.makeSteps(item)
        }

        // Each step is [name, function]. Steps for the General page set its
        // cfg_ properties like its controls do; other pages without the
        // functions below get only the first screenshot.
        // The first item named `name` in the tree below `item`, or null.
        function findItem(item, name) {
            if (item.objectName === name) {
                return item;
            }
            for (const child of item.children) {
                const found = findItem(child, name);
                if (found) {
                    return found;
                }
            }
            return null;
        }

        function makeSteps(page) {
            const steps = [["loaded", () => {}]];
            if (page.hasOwnProperty("cfg_sshOptions") && typeof page.selectServer !== "function") {
                steps.push(["no-batchmode", () => {
                    page.cfg_sshOptions = "-p 2222";
                    page.cfg_defaultInterval = 120;
                }]);
                steps.push(["empty-options", () => page.cfg_sshOptions = ""]);
            }
            if (typeof page.importText === "function") {
                steps.push(["export", () => page.showCurrentSetup()]);
                steps.push(["click-copy", () => {
                    const button = frame.findItem(page, "copySetupButton");
                    if (!button) {
                        throw new Error("page-harness: copySetupButton not found");
                    }
                    button.clicked();
                }]);
                steps.push(["import-bare-list", () => page.importText(
                    '[{"name": "Imported", "host": "h", "functions": [{"type": "status", "command": "true"}, {"type": "bogus"}]}]')]);
                steps.push(["import-setup", () => page.importText(JSON.stringify({
                    version: 1,
                    general: { defaultInterval: 45, sshOptions: "-o BatchMode=yes", unknown: 1 },
                    servers: [{ name: "A", host: "a", functions: [] }, { name: "B", host: "b", functions: [] }]
                }))]);
                steps.push(["export-after-import", () => page.showCurrentSetup()]);
                steps.push(["import-version-2", () => page.importText('{"version": 2, "servers": []}')]);
                steps.push(["import-invalid", () => page.importText("{ not json")]);
                steps.push(["import-no-list", () => page.importText('{"general": {}}')]);
            }
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
            // Runs the button's onClicked like a real click. The dialog
            // opens as a window; the test can't use it, but errors in the
            // handler show up.
            steps.push(["click-choose-icon", () => {
                const button = frame.findItem(page, "chooseIconButton");
                if (!button) {
                    // Thrown, not logged, so the load test fails.
                    throw new Error("page-harness: chooseIconButton not found");
                }
                button.clicked();
            }]);
            steps.push(["add-server", () => page.addServer()]);
            steps.push(["add-ping", () => {
                page.setServerField("host", "example.invalid");
                page.addFunction("ping");
            }]);
            steps.push(["interval-own", () => page.setFunctionField("interval", 45)]);
            steps.push(["interval-default", () => page.setFunctionField("interval", undefined)]);
            steps.push(["add-templates", () => {
                for (const id of ["wake", "poweroff", "reboot", "custom"]) {
                    page.addFunction(id);
                }
            }]);
            // Opens the dialog, then adds directly: the test can't type
            // into it. Screenshots don't show dialogs.
            steps.push(["flag-dialog", () => page.askFlagPath()]);
            steps.push(["add-flag", () => page.addFlagToggle("/tmp/my flags/skip-alarm", "")]);
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
