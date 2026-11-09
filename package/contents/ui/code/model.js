.pragma library

// The server list is stored as one JSON string in the `servers` config key.
// parseServers() turns that string into clean objects the UI can rely on:
// every field it reads exists and has the right type. Unknown fields are
// kept as they are.

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
        // Optional: without one, the default interval from the General
        // settings applies (see statusInterval()). An invalid one is dropped.
        if (asSeconds(raw.interval, 0) > 0) {
            fn.interval = asSeconds(raw.interval, 0);
        } else {
            delete fn.interval;
        }
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

// The functions shown as controls in the popup: all except the first
// status function, which is shown as the server's dot.
function controlFunctions(server) {
    const primary = statusFunction(server);
    return ((server && server.functions) || []).filter(fn => fn !== primary);
}

// Key for per-function state, unique across servers.
function functionKey(server, fn) {
    return server.id + "/" + fn.id;
}

// ---------------------------------------------------------------------------
// Tailscale. While it is active (see tailscaleCommand in main.xml), servers
// are reached at their `tailscaleHost`; servers without one can't be reached.

// Whether commands for `server` go to its Tailscale host.
function viaTailscale(server, tailscaleActive) {
    return tailscaleActive === true && !!(server && server.tailscaleHost);
}

// False for a server without a Tailscale host while Tailscale is active.
function reachable(server, tailscaleActive) {
    return tailscaleActive !== true || viaTailscale(server, tailscaleActive);
}

// Whether a function uses {mac} in any of its commands. Wake-on-LAN needs
// the local network: a broadcast doesn't cross Tailscale, and a server
// that is off isn't in the tailnet.
function needsLan(fn) {
    const fields = ["command", "verifyCommand", "stateCommand", "onCommand", "offCommand"];
    return fields.some(field => /\{mac\}/.test(String(fn[field] || "")));
}

// Why a function can't run right now, or "" if it can.
// `serverState` is "online", "offline" or "" (not checked yet).
// Returns "unreachable", "needsLan", "needsOnline", "needsOffline" or
// "unknown"; the UI translates it.
// While Tailscale is active, nothing runs on a server without a Tailscale
// host, and nothing that uses {mac}.
// A server without a status function can't be online or offline, so its
// functions are otherwise always available.
function unavailableReason(fn, server, serverState, tailscaleActive) {
    if (fn.type === "status") {
        return "";
    }
    if (!reachable(server, tailscaleActive)) {
        return "unreachable";
    }
    if (tailscaleActive === true && needsLan(fn)) {
        return "needsLan";
    }
    if (fn.availableWhen === "always" || !statusFunction(server)) {
        return "";
    }
    if (serverState !== "online" && serverState !== "offline") {
        return "unknown";
    }
    if (fn.availableWhen !== serverState) {
        return fn.availableWhen === "online" ? "needsOnline" : "needsOffline";
    }
    return "";
}

// Faster status polling after an action that should change the server's
// online state (Wake, Power off, Reboot), so the change shows up quickly.
const FAST_POLL_INTERVAL = 5;
const FAST_POLL_DURATION = 120;

// An action that can only run online or only offline is expected to change
// the online/server state. Actions available `always` (e.g. opening a web page)
// don't trigger faster polling.
function changesOnlineState(fn) {
    return fn.type === "action" && (fn.availableWhen === "online" || fn.availableWhen === "offline");
}

// A status function's own interval, or `defaultInterval` (the General
// setting) if it has none.
function statusInterval(fn, defaultInterval) {
    return fn.interval || asSeconds(defaultInterval, DEFAULT_INTERVAL);
}

// Seconds until a status function runs again. `fastPollUntil` is the end of
// the server's fast-polling period (a timestamp in ms, 0 if none).
function checkInterval(fn, defaultInterval, fastPollUntil, now) {
    const interval = statusInterval(fn, defaultInterval);
    return fastPollUntil > now ? Math.min(interval, FAST_POLL_INTERVAL) : interval;
}

// How long the inline result of a command stays visible, in seconds.
// Failures stay longer, so the message can be read.
const RESULT_OK_SECONDS = 3;
const RESULT_FAIL_SECONDS = 10;

// ---------------------------------------------------------------------------
// Editing, used by the settings page. The page edits a copy of the parsed
// list and writes it back with serializeServers().

// Fields that belong to one function type. changeFunctionType() drops the
// ones the new type doesn't use, so the saved JSON stays clean.
const TYPE_FIELDS = {
    status: ["command", "interval"],
    action: ["command", "verifyCommand", "availableWhen", "confirm"],
    toggle: ["stateCommand", "onCommand", "offCommand", "availableWhen", "confirm"]
};

// A deep copy, so edits don't touch the list bindings still show.
function copyServers(servers) {
    return JSON.parse(JSON.stringify(servers));
}

// All ids in use, servers and functions.
function usedIds(servers) {
    const used = {};
    for (const s of servers) {
        used[s.id] = true;
        for (const fn of s.functions || []) {
            used[fn.id] = true;
        }
    }
    return used;
}

// A new random id that isn't used anywhere in `servers` yet.
function newId(prefix, servers) {
    const used = usedIds(servers);
    let id;
    do {
        id = prefix + "-" + Math.random().toString(36).slice(2, 10);
    } while (used[id]);
    return id;
}

// An empty server. `name` comes from the caller, since i18n() isn't
// available in a library script.
function newServer(name, servers) {
    return { id: newId("server", servers), name: name, host: "", mac: "", user: "", functions: [] };
}

// A copy of `fn` as another type. Name, icon, timeout and the fields both
// types share (e.g. `command` from status to action) are kept; fields the
// new type doesn't use are dropped. A default icon follows the new type.
function changeFunctionType(fn, type) {
    const result = Object.assign({}, fn, { type: type });
    for (const t in TYPE_FIELDS) {
        for (const field of TYPE_FIELDS[t]) {
            if (TYPE_FIELDS[type].indexOf(field) < 0) {
                delete result[field];
            }
        }
    }
    if (fn.icon === DEFAULT_ICONS[fn.type]) {
        delete result.icon;
    }
    return normalizeFunction(result, fn.id, {}, [], "changed function");
}

// Moves list[from] to list[to] in place. Returns false if either index is
// out of range.
function moveItem(list, from, to) {
    if (from < 0 || from >= list.length || to < 0 || to >= list.length) {
        return false;
    }
    list.splice(to, 0, list.splice(from, 1)[0]);
    return true;
}

// ---------------------------------------------------------------------------
// Import and export of the whole setup, used by the General settings page.
// Format: { "version": 1, "general": { defaultInterval, sshOptions, tailscaleEnabled,
// tailscaleCommand },
// "servers": [ ... ] }. Import also accepts a bare server list.

const SETUP_VERSION = 1;

// The whole setup as indented JSON text. `servers` is a parsed list,
// `general` holds the General settings.
function exportSetup(servers, general) {
    return JSON.stringify({ version: SETUP_VERSION, general: general, servers: servers }, null, 2);
}

const GENERAL_KEYS = ["defaultInterval", "sshOptions", "tailscaleEnabled", "tailscaleCommand"];

// The known General settings in `raw`, checked. Invalid or unknown ones
// are left out with a warning.
function parseGeneral(raw, warnings) {
    if (!isPlainObject(raw)) {
        warnings.push("`general` is not an object, ignored");
        return null;
    }
    const general = {};
    for (const key in raw) {
        const value = raw[key];
        if (key === "defaultInterval" && asSeconds(value, 0) > 0) {
            // The config key is an integer.
            general.defaultInterval = Math.max(1, Math.round(asSeconds(value, 0)));
        } else if ((key === "sshOptions" || key === "tailscaleCommand") && typeof value === "string") {
            general[key] = value;
        } else if (key === "tailscaleEnabled" && typeof value === "boolean") {
            general[key] = value;
        } else if (GENERAL_KEYS.indexOf(key) >= 0) {
            warnings.push("general." + key + ": invalid value " + JSON.stringify(value) + ", ignored");
        } else {
            warnings.push("general." + key + ": unknown setting, ignored");
        }
    }
    return general;
}

// Reads an exported setup or a bare server list. Never throws.
// Returns { error, detail, servers, general, warnings }:
// - `error` is "" or a code the UI translates: "invalidJson" (`detail`:
//   the parser's message), "unsupportedVersion" (`detail`: the version) or
//   "noServerList".
// - `servers` is parsed like the config, by parseServers().
// - `general` holds the valid General settings found, or null if the text
//   has none (a bare list, or no `general` key).
// - `warnings` are English developer messages, as from parseServers().
function parseSetup(text) {
    const result = { error: "", detail: "", servers: [], general: null, warnings: [] };
    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        result.error = "invalidJson";
        result.detail = e.message;
        return result;
    }

    let list = null;
    if (Array.isArray(data)) {
        list = data;
    } else if (isPlainObject(data)) {
        if (data.version !== undefined && Number(data.version) !== SETUP_VERSION) {
            result.error = "unsupportedVersion";
            result.detail = String(data.version);
            return result;
        }
        if (Array.isArray(data.servers)) {
            list = data.servers;
        }
        if (data.general !== undefined) {
            result.general = parseGeneral(data.general, result.warnings);
        }
    }
    if (list === null) {
        result.error = "noServerList";
        return result;
    }

    const parsed = parseServers(JSON.stringify(list));
    result.servers = parsed.servers;
    result.warnings = result.warnings.concat(parsed.warnings);
    return result;
}
