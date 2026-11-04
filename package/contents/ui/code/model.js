.pragma library

// The server list is stored as one JSON string in the `servers` config key.
// parseServers() turns that string into clean objects the UI can rely on:
// every field it reads exists and has the right type. Unknown fields (e.g.
// `tailscaleHost`, reserved for a later phase) are kept as they are.

const FUNCTION_TYPES = ["status", "action", "toggle"];
const AVAILABLE_WHEN = ["online", "offline", "always"];

const DEFAULT_INTERVAL = 30;
const DEFAULT_TIMEOUT = 10;
const DEFAULT_ICONS = {
    status: "network-connect",
    action: "system-run",
    toggle: "system-run"
};

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function asString(value, fallback) {
    return typeof value === "string" ? value : fallback;
}

// A positive number of seconds. Accepts numeric strings like "30".
function asSeconds(value, fallback) {
    if (typeof value !== "number" && typeof value !== "string") {
        return fallback;
    }
    const n = Number(value);
    return isFinite(n) && n > 0 ? n : fallback;
}

function oneOf(value, allowed, fallback) {
    return allowed.indexOf(value) >= 0 ? value : fallback;
}

// Returns `id` if it is a non-empty, unused string, otherwise `fallback`
// (made unique with a suffix). Records the result in `used`.
// The fallback is derived from the position, not random, so a config
// without ids gets the same ids on every parse and state keyed by id survives.
function uniqueId(id, fallback, used) {
    let result = typeof id === "string" && id !== "" ? id : fallback;
    if (used[result]) {
        let n = 2;
        while (used[result + "-" + n]) {
            n++;
        }
        result = result + "-" + n;
    }
    used[result] = true;
    return result;
}

// Returns a normalized copy of one function, or null if it can't be used.
function normalizeFunction(raw, fallbackId, usedIds, warnings, where) {
    if (!isPlainObject(raw)) {
        warnings.push(where + ": not an object, skipped");
        return null;
    }
    if (FUNCTION_TYPES.indexOf(raw.type) < 0) {
        warnings.push(where + ": unknown type " + JSON.stringify(raw.type) + ", skipped");
        return null;
    }

    const fn = Object.assign({}, raw);
    const id = uniqueId(raw.id, fallbackId, usedIds);
    if (id !== raw.id) {
        warnings.push(where + ": missing or duplicate id, using " + JSON.stringify(id));
    }
    fn.id = id;
    fn.name = asString(raw.name, "");
    fn.icon = asString(raw.icon, "") || DEFAULT_ICONS[fn.type];
    fn.timeout = asSeconds(raw.timeout, DEFAULT_TIMEOUT);

    switch (fn.type) {
    case "status":
        fn.command = asString(raw.command, "");
        fn.interval = asSeconds(raw.interval, DEFAULT_INTERVAL);
        break;
    case "action":
        fn.command = asString(raw.command, "");
        fn.verifyCommand = asString(raw.verifyCommand, "");
        break;
    case "toggle":
        fn.stateCommand = asString(raw.stateCommand, "");
        fn.onCommand = asString(raw.onCommand, "");
        fn.offCommand = asString(raw.offCommand, "");
        break;
    }
    if (fn.type !== "status") {
        fn.availableWhen = oneOf(raw.availableWhen, AVAILABLE_WHEN, "always");
        fn.confirm = raw.confirm === true;
    }
    return fn;
}

// Returns a normalized copy of one server, or null if it can't be used.
function normalizeServer(raw, index, usedIds, warnings) {
    const where = "server " + (index + 1);
    if (!isPlainObject(raw)) {
        warnings.push(where + ": not an object, skipped");
        return null;
    }

    const server = Object.assign({}, raw);
    const id = uniqueId(raw.id, "server-" + (index + 1), usedIds);
    if (id !== raw.id) {
        warnings.push(where + ": missing or duplicate id, using " + JSON.stringify(id));
    }
    server.id = id;
    server.name = asString(raw.name, "").trim() || asString(raw.host, "") || id;
    server.host = asString(raw.host, "").trim();
    server.mac = asString(raw.mac, "").trim();
    server.user = asString(raw.user, "").trim();
    if (raw.tailscaleHost !== undefined) {
        server.tailscaleHost = asString(raw.tailscaleHost, "").trim();
    }

    if (raw.functions !== undefined && !Array.isArray(raw.functions)) {
        warnings.push(where + ": `functions` is not a list, ignored");
    }
    const rawFunctions = Array.isArray(raw.functions) ? raw.functions : [];
    const usedFunctionIds = {};
    server.functions = [];
    for (let i = 0; i < rawFunctions.length; i++) {
        const fn = normalizeFunction(rawFunctions[i], id + "-fn-" + (i + 1), usedFunctionIds,
                                     warnings, where + ", function " + (i + 1));
        if (fn) {
            server.functions.push(fn);
        }
    }
    return server;
}

// Parses the `servers` config string. Never throws.
// Returns { servers: [...], warnings: [...] }. `warnings` are English
// developer messages for the log; the UI only shows that there were some.
// An empty string is a valid, empty config.
function parseServers(text) {
    const warnings = [];
    if (typeof text !== "string" || text.trim() === "") {
        return { servers: [], warnings: warnings };
    }

    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        warnings.push("config is not valid JSON: " + e.message);
        return { servers: [], warnings: warnings };
    }
    if (!Array.isArray(data)) {
        warnings.push("config is not a list of servers");
        return { servers: [], warnings: warnings };
    }

    const usedIds = {};
    const servers = [];
    for (let i = 0; i < data.length; i++) {
        const server = normalizeServer(data[i], i, usedIds, warnings);
        if (server) {
            servers.push(server);
        }
    }
    return { servers: servers, warnings: warnings };
}

// The inverse of parseServers(), for writing the config key.
function serializeServers(servers) {
    return JSON.stringify(Array.isArray(servers) ? servers : []);
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
