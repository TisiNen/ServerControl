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

function sshCommand(server) {
    const host = server.host || "";
    const target = server.user ? server.user + "@" + host : host;
    return "ssh -o BatchMode=yes -o ConnectTimeout=5 " + shellQuote(target);
}

function placeholderValues(server) {
    return {
        host: shellQuote(server.host),
        mac: shellQuote(server.mac),
        user: shellQuote(server.user),
        name: shellQuote(server.name),
        ssh: sshCommand(server)
    };
}

// Replaces known {placeholders} with shell-quoted values from the server.
// Unknown placeholders are left as they are.
function substitute(command, server) {
    const values = placeholderValues(server);
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
