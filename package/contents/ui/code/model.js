.pragma library

// Phase 1: one hardcoded server. Phase 2 replaces this with the JSON config
// stored in the `servers` config key.
// To try the widget against a real machine, change `name` and `host` below.
function defaultServers() {
    return [
        {
            id: "demo-server",
            name: "NAS",
            host: "192.168.1.10",
            mac: "",
            user: "",
            functions: [
                {
                    id: "demo-status",
                    type: "status",
                    name: "Online",
                    icon: "network-connect",
                    command: "ping -c 1 -W 1 {host}",
                    interval: 30,
                    timeout: 10
                }
            ]
        }
    ];
}

// A server's online state comes from its first `status` function.
function statusFunction(server) {
    const fns = (server && server.functions) || [];
    for (let i = 0; i < fns.length; i++) {
        if (fns[i] && fns[i].type === "status") {
            return fns[i];
        }
    }
    return null;
}
