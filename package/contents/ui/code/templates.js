.pragma library
.import "model.js" as Model
.import "commands.js" as Commands

// Preconfigured functions for "Add Function" in the settings. Each holds the
// fields of the new function except id and name: the name comes from the
// settings page, because i18n() isn't available in a library script.
// normalizeFunction() fills in everything not listed here with its default,
// e.g. no `interval`, so a ping uses the default check interval.
const TEMPLATES = {
    ping: {
        type: "status",
        icon: "network-connect",
        command: "ping -c 1 -W 1 {host}"
    },
    wake: {
        type: "action",
        icon: "system-run",
        command: "wakeonlan {mac}",
        availableWhen: "offline"
    },
    poweroff: {
        type: "action",
        icon: "system-shutdown",
        command: "{ssh} sudo systemctl poweroff",
        availableWhen: "online",
        confirm: true
    },
    reboot: {
        type: "action",
        icon: "system-reboot",
        command: "{ssh} sudo systemctl reboot",
        availableWhen: "online",
        confirm: true
    },
    // Empty; the type can be changed in the editor.
    custom: {
        type: "action"
    }
};

function create(fields, servers) {
    return Model.normalizeFunction(fields, Model.newId("fn", servers), {}, [], "new function");
}

// A new function from the template `templateId` (a key of TEMPLATES), with
// an id not used in `servers` yet.
function fromTemplate(templateId, name, servers) {
    return create(Object.assign({}, TEMPLATES[templateId], { name: name }), servers);
}

// A toggle for a flag file on the server: on while the file exists.
// The path is quoted twice, because two shells parse it: the local one
// removes the outer quotes, ssh joins the words into one string, and the
// server's shell splits that again. A plain path like /var/lib/x/flag needs
// no quotes, so the commands stay readable.
function flagToggle(path, name, servers) {
    const file = Commands.shellQuote(Commands.shellQuote(path));
    return create({
        type: "toggle",
        name: name,
        icon: "flag",
        stateCommand: "{ssh} test -f " + file,
        onCommand: "{ssh} touch " + file,
        offCommand: "{ssh} rm -f " + file,
        availableWhen: "online"
    }, servers);
}

// The last part of a path, e.g. "skip-alarm" for "/var/lib/x/skip-alarm".
// The default name of a flag toggle. "" for an empty path.
function flagName(path) {
    const parts = String(path || "").split("/").filter(part => part.trim() !== "");
    return parts.length > 0 ? parts[parts.length - 1].trim() : "";
}
