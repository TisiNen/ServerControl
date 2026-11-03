import QtQuick
import org.kde.plasma.plasmoid

import "code/model.js" as Model
import "code/commands.js" as Commands

PlasmoidItem {
    id: root

    readonly property var servers: Model.defaultServers()

    // server id -> "online" | "offline". Missing means not checked yet.
    property var serverStates: ({})

    // Number of user-triggered actions in flight; drives the panel spinner.
    // Status checks don't count, or the spinner would flash on every poll.
    property int actionsRunning: 0
    readonly property bool busy: actionsRunning > 0

    readonly property int onlineCount: {
        let n = 0;
        for (const s of servers) {
            if (serverStates[s.id] === "online") {
                n++;
            }
        }
        return n;
    }
    // "all" | "some" | "none"
    readonly property string overallState: servers.length > 0 && onlineCount === servers.length ? "all"
        : onlineCount > 0 ? "some" : "none"

    // Bookkeeping only, never bound to: server id -> timestamp / flag.
    property var _nextCheck: ({})
    property var _checking: ({})

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
        _checking[server.id] = true;
        _nextCheck[server.id] = Date.now() + Math.max(1, fn.interval || 30) * 1000;
        runner.run(Commands.substitute(fn.command, server), fn.timeout || 10, result => {
            delete _checking[server.id];
            setState(server.id, result.exitCode === 0 ? "online" : "offline");
        });
    }

    function refreshAll() {
        for (const s of servers) {
            checkStatus(s);
        }
    }

    toolTipMainText: i18n("Server Control")
    toolTipSubText: servers.length === 0 ? i18n("No servers configured")
        : servers.map(s => i18nc("tooltip line: server name, state", "%1: %2", s.name, stateText(s))).join("\n")

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
            for (const s of root.servers) {
                if (now >= (root._nextCheck[s.id] || 0)) {
                    root.checkStatus(s);
                }
            }
        }
    }
}
