.pragma library

// Characters that never need quoting in a POSIX shell word.
const SAFE_WORD = /^[A-Za-z0-9_@%+=:,.\/-]+$/;

function shellQuote(value) {
    const s = String(value === undefined || value === null ? "" : value);
    if (s === "") {
        return "''";
    }
    if (SAFE_WORD.test(s)) {
        return s;
    }
    return "'" + s.replace(/'/g, "'\\''") + "'";
}

// Used when no SSH options are passed. Same as the default of the
// `sshOptions` key in main.xml.
const DEFAULT_SSH_OPTIONS = "-o BatchMode=yes -o ConnectTimeout=5";

// `sshOptions` is the General setting, inserted as typed: it holds several
// shell words, so it isn't quoted. "" means plain `ssh user@host`.
function sshCommand(server, sshOptions) {
    const host = server.host || "";
    const target = server.user ? server.user + "@" + host : host;
    const options = typeof sshOptions === "string" ? sshOptions.trim() : DEFAULT_SSH_OPTIONS;
    return ["ssh", options, shellQuote(target)].filter(part => part !== "").join(" ");
}

// Without BatchMode, ssh asks for a password when key login fails, and the
// command hangs until its timeout. The settings warn about that.
function hasBatchMode(sshOptions) {
    return /batchmode[\s=]+yes/i.test(String(sshOptions || ""));
}

// `viaTailscale` (see viaTailscale() in model.js): {host}, and with it
// {ssh}, use the server's `tailscaleHost`.
function placeholderValues(server, sshOptions, viaTailscale) {
    if (viaTailscale && server.tailscaleHost) {
        server = Object.assign({}, server, { host: server.tailscaleHost });
    }
    return {
        host: shellQuote(server.host),
        mac: shellQuote(server.mac),
        user: shellQuote(server.user),
        name: shellQuote(server.name),
        ssh: sshCommand(server, sshOptions)
    };
}

// Replaces known {placeholders} with shell-quoted values from the server.
// Unknown placeholders are left as they are. `sshOptions` is the General
// setting for {ssh}. With `viaTailscale`, {host} is the Tailscale host.
function substitute(command, server, sshOptions, viaTailscale) {
    const values = placeholderValues(server, sshOptions, viaTailscale);
    return String(command || "").replace(/\{(\w+)\}/g, function (match, key) {
        return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : match;
    });
}

// The executable engine has no timeout of its own. `-k 2` sends SIGKILL
// if the command ignores the initial SIGTERM.
function withTimeout(command, timeoutSeconds) {
    const t = Math.max(1, Math.round(Number(timeoutSeconds) || 10));
    return "timeout -k 2 " + t + " sh -c " + shellQuote(command);
}

// Exit codes from `timeout`: 124 after SIGTERM, 137 after SIGKILL.
function isTimeoutExit(exitCode) {
    return exitCode === 124 || exitCode === 137;
}

// The line of stderr worth showing inline: the last non-empty one. Tools
// like ssh print warnings first and the actual error last. "" if none.
function errorLine(stderr) {
    const lines = String(stderr || "").split("\n").map(l => l.trim()).filter(l => l !== "");
    return lines.length > 0 ? lines[lines.length - 1] : "";
}

// The placeholders substitute() knows.
const PLACEHOLDERS = ["host", "mac", "user", "name", "ssh"];

// Placeholder names used in `command`, each once, in order.
function placeholdersIn(command) {
    const names = [];
    const re = /\{(\w+)\}/g;
    let m;
    while ((m = re.exec(String(command || ""))) !== null) {
        if (names.indexOf(m[1]) < 0) {
            names.push(m[1]);
        }
    }
    return names;
}

// Placeholders in `command` that substitute() leaves as they are.
function unknownPlaceholders(command) {
    return placeholdersIn(command).filter(name => PLACEHOLDERS.indexOf(name) < 0);
}

// Known placeholders in `command` whose server field is empty, e.g. {mac}
// without a MAC address. {ssh} counts as using {host}.
function emptyPlaceholders(command, server) {
    const used = placeholdersIn(command);
    if (used.indexOf("ssh") >= 0 && used.indexOf("host") < 0) {
        used.push("host");
    }
    return used.filter(name => name !== "ssh" && PLACEHOLDERS.indexOf(name) >= 0
                       && String(server[name] || "") === "");
}
