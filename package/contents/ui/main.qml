import QtQuick
import org.kde.plasma.plasmoid

import "code/model.js" as Model
import "code/commands.js" as Commands

PlasmoidItem {
    id: root

    // The `servers` config key, parsed by applyConfig(). Not a binding:
    // Plasma re-evaluates bindings at startup even when the config is
    // unchanged, which would reset all state and log every warning twice.
    property var parsedConfig: Model.parseServers("")
    readonly property var serverList: parsedConfig.servers
    readonly property var configWarnings: parsedConfig.warnings

    // server id -> "online" | "offline". Missing means not checked yet.
    property var serverStates: ({})
    // Model.functionKey() -> state of one function. Missing means not read yet.
    // Extra status functions: "ok" | "fail".
    // Toggles: "on" | "off" | "unknown" (the state command timed out).
    property var functionStates: ({})
    // Model.functionKey() -> true while an action or toggle command runs.
    property var runningFunctions: ({})
    // Model.functionKey() -> result of the last action or toggle command,
    // shown inline for a few seconds: { ok, detail, verified, expiresAt, ... }.
    // See setResult() and expireResults().
    property var functionResults: ({})

    // Number of user-triggered actions in flight; drives the panel spinner.
    // Status checks don't count, or the spinner would flash on every poll.
    property int actionsRunning: 0
    readonly property bool busy: actionsRunning > 0

    readonly property int onlineCount: {
        let n = 0;
        for (const s of serverList) {
            if (serverStates[s.id] === "online") {
                n++;
            }
        }
        return n;
    }
    // "all" | "some" | "none"
    readonly property string overallState: serverList.length > 0 && onlineCount === serverList.length ? "all"
        : onlineCount > 0 ? "some" : "none"

    // Bookkeeping only, never bound to: function key -> timestamp / flag / number.
    property var _nextCheck: ({})
    property var _checking: ({})
    // Only the newest read of a toggle may set its state; older ones can
    // finish later and would show a stale value.
    property var _readSeq: ({})
    // server id -> timestamp until which its status is polled faster.
    property var _fastPollUntil: ({})
    // Bumped on every config change, so results of checks started with the
    // old config are dropped instead of overwriting fresh state.
    property int _configGeneration: 0
    property string _appliedConfig: ""

    function stateText(server) {
        if (!Model.statusFunction(server)) {
            return i18n("No status check");
        }
        switch (serverStates[server.id]) {
        case "online":
            return i18n("Online");
        case "offline":
            return i18n("Offline");
        default:
            return i18n("Checking…");
        }
    }

    // A command with its placeholders filled in for `server`, using the
    // SSH options from the General settings.
    function commandFor(command, server) {
        return Commands.substitute(command, server, Plasmoid.configuration.sshOptions);
    }

    // The name shown for a function in the popup and the confirmation dialog.
    function functionName(fn) {
        return fn.name || i18n("Unnamed function");
    }

    // Maps are replaced, never mutated, so bindings that read them update.
    function setServerState(server, state) {
        const previous = serverStates[server.id];
        if (previous === state) {
            return;
        }
        const next = Object.assign({}, serverStates);
        next[server.id] = state;
        serverStates = next;
        // Toggles that need the server online can be read now.
        if (state === "online") {
            refreshToggles(server);
        }
    }

    function setFunctionState(key, state) {
        if (functionStates[key] === state) {
            return;
        }
        const next = Object.assign({}, functionStates);
        next[key] = state;
        functionStates = next;
    }

    function setRunning(key, running) {
        const next = Object.assign({}, runningFunctions);
        if (running) {
            next[key] = true;
        } else {
            delete next[key];
        }
        runningFunctions = next;
    }

    function serverStateOf(server) {
        return serverStates[server.id] || "";
    }

    // Runs one status function. The first one sets the server's online
    // state; any others only set their own "ok"/"fail".
    function checkStatus(server, fn) {
        const key = Model.functionKey(server, fn);
        if (_checking[key]) {
            return;
        }
        const primary = fn === Model.statusFunction(server);
        const generation = _configGeneration;
        _checking[key] = true;
        const now = Date.now();
        _nextCheck[key] = now + Model.checkInterval(fn, Plasmoid.configuration.defaultInterval,
                                                    _fastPollUntil[server.id] || 0, now) * 1000;
        runner.run(commandFor(fn.command, server), fn.timeout, result => {
            if (generation !== _configGeneration) {
                return;
            }
            delete _checking[key];
            if (primary) {
                setServerState(server, result.exitCode === 0 ? "online" : "offline");
            } else {
                setFunctionState(key, result.exitCode === 0 ? "ok" : "fail");
            }
        });
    }

    // `done` (optional) is called when the command has finished, even if
    // its result is dropped.
    function readToggle(server, fn, done) {
        const key = Model.functionKey(server, fn);
        const seq = (_readSeq[key] || 0) + 1;
        const generation = _configGeneration;
        _readSeq[key] = seq;
        runner.run(commandFor(fn.stateCommand, server), fn.timeout, result => {
            if (done) {
                done();
            }
            if (generation !== _configGeneration || _readSeq[key] !== seq) {
                return;
            }
            setFunctionState(key, result.timedOut ? "unknown" : result.exitCode === 0 ? "on" : "off");
        });
    }

    // Clicking a toggle whose state is "unknown" reads the state again
    // instead of running onCommand/offCommand: without the current state,
    // the click has no clear meaning. Marked as running, so the switch
    // shows the spinner while it waits.
    function retryToggle(server, fn) {
        const key = Model.functionKey(server, fn);
        if (runningFunctions[key]) {
            return;
        }
        setRunning(key, true);
        readToggle(server, fn, () => setRunning(key, false));
    }

    // Toggle states are not polled. They are read when the popup opens,
    // after an action on the server and when the server comes online.
    // Toggles that can't run in the current server state are skipped,
    // e.g. an SSH check while the server is off.
    function refreshToggles(server) {
        for (const fn of server.functions) {
            if (fn.type === "toggle" && !runningFunctions[Model.functionKey(server, fn)]
                    && Model.unavailableReason(fn, server, serverStateOf(server)) === "") {
                readToggle(server, fn);
            }
        }
    }

    function refreshServer(server) {
        for (const fn of server.functions) {
            if (fn.type === "status") {
                checkStatus(server, fn);
            }
        }
        refreshToggles(server);
    }

    function refreshAll() {
        for (const s of serverList) {
            refreshServer(s);
        }
    }

    // Runs an action, or a toggle's on/off command (`turnOn` says which).
    // The confirmation dialog, if any, has already been shown.
    function runFunction(server, fn, turnOn) {
        const key = Model.functionKey(server, fn);
        if (runningFunctions[key] || Model.unavailableReason(fn, server, serverStateOf(server)) !== "") {
            return;
        }
        const command = fn.type === "toggle" ? (turnOn ? fn.onCommand : fn.offCommand) : fn.command;
        const generation = _configGeneration;
        setRunning(key, true);
        actionsRunning++;

        // Always runs, even after a config change, so the counters stay right.
        const finish = (result, verified) => {
            setRunning(key, false);
            actionsRunning--;
            if (generation !== _configGeneration) {
                return;
            }
            setResult(key, result, verified);
            if (Model.changesOnlineState(fn)) {
                startFastPoll(server);
            }
            refreshServer(server);
        };
        runner.run(commandFor(command, server), fn.timeout, result => {
            // An action's success is decided by its verifyCommand, if set.
            if (fn.type === "action" && fn.verifyCommand !== "") {
                runner.run(commandFor(fn.verifyCommand, server), fn.timeout,
                           verifyResult => finish(verifyResult, true));
            } else {
                finish(result, false);
            }
        });
    }

    // Stores the result of a command for the inline feedback. It shows for
    // a few seconds; the timer below calls expireResults() to remove it.
    function setResult(key, result, verified) {
        const ok = result.exitCode === 0;
        const now = Date.now();
        const next = Object.assign({}, functionResults);
        next[key] = {
            ok: ok,
            detail: Commands.errorLine(result.stderr),
            stderr: result.stderr,
            exitCode: result.exitCode,
            verified: verified,
            expiresAt: now + (ok ? Model.RESULT_OK_SECONDS : Model.RESULT_FAIL_SECONDS) * 1000
        };
        functionResults = next;
    }

    // Removes the results whose time is up. Copies the map only if
    // something changes, so most ticks don't touch any binding.
    function expireResults(now) {
        let next = null;
        for (const key in functionResults) {
            if (now >= functionResults[key].expiresAt) {
                next = next || Object.assign({}, functionResults);
                delete next[key];
            }
        }
        if (next) {
            functionResults = next;
        }
    }

    // The inline message for a failed command.
    function resultText(result) {
        if (result.detail !== "") {
            return result.detail;
        }
        return result.verified ? i18n("Check afterwards failed with exit code %1", result.exitCode)
            : i18n("Failed with exit code %1", result.exitCode);
    }

    // Polls the server's status functions every few seconds for a while,
    // e.g. after Wake, so the new state shows up quickly.
    function startFastPoll(server) {
        const now = Date.now();
        _fastPollUntil[server.id] = now + Model.FAST_POLL_DURATION * 1000;
        for (const fn of server.functions) {
            if (fn.type === "status") {
                const key = Model.functionKey(server, fn);
                _nextCheck[key] = Math.min(_nextCheck[key] || 0, now + Model.checkInterval(
                    fn, Plasmoid.configuration.defaultInterval, _fastPollUntil[server.id], now) * 1000);
            }
        }
    }

    toolTipMainText: i18n("Server Control")
    toolTipSubText: serverList.length === 0 ? i18n("No servers configured")
        : serverList.map(s => i18nc("tooltip line: server name, state", "%1: %2", s.name, stateText(s))).join("\n")

    // Parses the config if it changed since the last call. Never throws:
    // bad entries are skipped and reported in `configWarnings`.
    function applyConfig() {
        const text = Plasmoid.configuration.servers || "";
        if (text === _appliedConfig) {
            return;
        }
        _appliedConfig = text;
        parsedConfig = Model.parseServers(text);
        for (const w of configWarnings) {
            console.warn("Server Control config:", w);
        }
        // Forget the state of removed servers and functions, and check
        // everything again, since hosts or commands may have changed.
        const states = {};
        const fnStates = {};
        for (const s of serverList) {
            if (serverStates[s.id] !== undefined) {
                states[s.id] = serverStates[s.id];
            }
            for (const fn of s.functions) {
                const key = Model.functionKey(s, fn);
                if (functionStates[key] !== undefined) {
                    fnStates[key] = functionStates[key];
                }
            }
        }
        serverStates = states;
        functionStates = fnStates;
        functionResults = {};
        _configGeneration++;
        _checking = {};
        _nextCheck = {};
        _readSeq = {};
        _fastPollUntil = {};
        for (const s of serverList) {
            refreshToggles(s);
        }
    }

    Component.onCompleted: applyConfig()

    Connections {
        target: Plasmoid.configuration

        function onServersChanged() {
            root.applyConfig();
        }

        // Check everything on the next tick with the new settings, instead
        // of waiting for checks scheduled with the old interval.
        function onDefaultIntervalChanged() {
            root._nextCheck = {};
        }

        function onSshOptionsChanged() {
            root._nextCheck = {};
        }
    }

    onExpandedChanged: {
        if (root.expanded) {
            refreshAll();
        }
    }

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
    }

    CommandRunner {
        id: runner
    }

    // Ticks every second: starts the status checks that are due, so each
    // status function can have its own interval (and a faster one after
    // Wake), and removes old inline results.
    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            root.expireResults(now);
            for (const s of root.serverList) {
                for (const fn of s.functions) {
                    if (fn.type === "status" && now >= (root._nextCheck[Model.functionKey(s, fn)] || 0)) {
                        root.checkStatus(s, fn);
                    }
                }
            }
        }
    }
}
