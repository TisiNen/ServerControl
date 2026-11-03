import QtQuick
import org.kde.plasma.plasma5support as P5Support

import "code/commands.js" as Commands

// Runs shell commands asynchronously through the executable data engine.
// run(command, timeoutSeconds, callback) calls back with
// { exitCode, stdout, stderr, timedOut }.
P5Support.DataSource {
    id: runner

    readonly property int runningCount: _running

    property int _counter: 0
    property int _running: 0
    property var _callbacks: ({})

    engine: "executable"
    connectedSources: []

    function run(command, timeoutSeconds, callback) {
        _counter++;
        // Identical command strings would share one source, so make each
        // invocation unique with a trailing shell comment.
        const source = Commands.withTimeout(command, timeoutSeconds) + " # " + _counter;
        _callbacks[source] = callback;
        _running++;
        connectSource(source);
    }

    onNewData: (sourceName, data) => {
        const callback = _callbacks[sourceName];
        delete _callbacks[sourceName];
        disconnectSource(sourceName);
        _running = Math.max(0, _running - 1);

        const exitCode = data["exit code"];
        const timedOut = Commands.isTimeoutExit(exitCode);
        let stderr = String(data["stderr"] || "").trim();
        if (timedOut && stderr === "") {
            stderr = i18n("Timed out");
        }
        if (callback) {
            callback({
                exitCode: exitCode,
                stdout: String(data["stdout"] || ""),
                stderr: stderr,
                timedOut: timedOut
            });
        }
    }
}
