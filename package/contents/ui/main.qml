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

    // Bookkeeping only, never bound to: server id -> timestamp / flag.
    property var _nextCheck: ({})
    property var _checking: ({})
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

    function setState(id, state) {
        if (serverStates[id] === state) {
            return;
        }
        const next = Object.assign({}, serverStates);
        next[id] = state;
        serverStates = next;
    }

    function checkStatus(server) {
        const fn = Model.statusFunction(server);
        if (!fn || _checking[server.id]) {
            return;
        }
        const generation = _configGeneration;
        _checking[server.id] = true;
        _nextCheck[server.id] = Date.now() + fn.interval * 1000;
        runner.run(Commands.substitute(fn.command, server), fn.timeout, result => {
            if (generation !== _configGeneration) {
                return;
            }
            delete _checking[server.id];
            setState(server.id, result.exitCode === 0 ? "online" : "offline");
        });
    }

    function refreshAll() {
        for (const s of serverList) {
            checkStatus(s);
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
        // Forget state of removed servers and check every server again,
        // since its host or status command may have changed.
        const next = {};
        for (const s of serverList) {
            if (serverStates[s.id] !== undefined) {
                next[s.id] = serverStates[s.id];
            }
        }
        serverStates = next;
        _configGeneration++;
        _checking = {};
        _nextCheck = {};
    }

    Component.onCompleted: applyConfig()

    Connections {
        target: Plasmoid.configuration

        function onServersChanged() {
            root.applyConfig();
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

    // Ticks every second and starts the status checks that are due, so each
    // server can have its own interval (and later a faster one after Wake).
    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            for (const s of root.serverList) {
                if (now >= (root._nextCheck[s.id] || 0)) {
                    root.checkStatus(s);
                }
            }
        }
    }
}
