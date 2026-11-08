# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

A **KDE Plasma 6 panel widget (plasmoid)** for controlling home servers: show online/offline
status, wake them via Wake-on-LAN, toggle skip flags, and power them off over SSH.

The widget is **generic**: servers and their functions are defined in the widget settings,
not hardcoded. Each function is a configurable shell command.

- Working name: **Server Control**
- Plugin ID: `com.github.TisiNen.servercontrol` (placeholder — confirm before publishing)
- Stack: **pure QML/JavaScript**, no C++ backend
- License: TBD

### Environment note

Development happens on a Linux machine with Plasma 6.

- Write code carefully against the Plasma 6 APIs listed below; don't guess at Plasma 5 APIs.
- Load tests (does the widget start without QML errors?) run automatically in a Podman
  sandbox. See "Self-testing" below.
- Everything interactive (clicks, popup, settings, real servers) is tested manually by the user.
  When a change needs that, say so and give the exact test steps.

## Background: the user's server setup

The first use case. Keep it in mind, but the widget must not depend on it.

- Each server runs a script by systemd timer every evening that sets an RTC wake alarm for the
  next day and then shuts the server down.
- The script checks two flag files before acting:
  - `skip-shutdown`: don't shut down tonight
  - `skip-alarm`: don't set the wake alarm, so the server doesn't start tomorrow
- The flags are created over SSH (`touch`). Paths are set per function in the widget config.
- Wake-on-LAN is configured on every server (local network only).

## Data model

Plasma's config (KConfigXT) only stores simple types, so the whole server list is stored as
**one JSON string** in the config key `servers`. Parse it once, validate it, and fall back
to `[]` on error. Never crash on bad config.

Parsing and validation live in `code/model.js` (`parseServers()`), with these rules:

- Not JSON, or not a list: no servers, one warning.
- An entry that isn't an object, or a function with an unknown `type`, is skipped with a warning.
- A missing or duplicate `id` (servers globally, functions per server) is replaced by a
  position-based id (`server-2`, `<serverId>-fn-1`), so ids stay stable across re-parses.
- Missing or invalid fields get defaults: `timeout` 10, `availableWhen` `always`,
  `confirm` false, commands `""`, an icon per type. A server without a name shows its host.
  Numbers must be positive; numeric strings are accepted.
- A status function's `interval` is optional. A missing or invalid one is left out, and the
  default check interval from the General settings applies (config key `defaultInterval`,
  default 30; `statusInterval()` in `model.js`).
- Warnings are English developer messages, logged with `console.warn`. The popup only shows that
  there were some.

Servers also have an optional `tailscaleHost` field (Tailscale IP or MagicDNS name). It is
reserved for the later Tailscale feature (see Roadmap phase 4). Until then, validation must keep
it and other unknown fields instead of dropping them.

```json
[
  {
    "id": "uuid",
    "name": "NAS",
    "host": "192.168.1.10",
    "mac": "aa:bb:cc:dd:ee:ff",
    "user": "admin",
    "functions": [
      {
        "id": "uuid",
        "type": "status",
        "name": "Online",
        "icon": "network-connect",
        "command": "ping -c 1 -W 1 {host}",
        "interval": 30
      },
      {
        "id": "uuid",
        "type": "action",
        "name": "Wake",
        "icon": "system-run",
        "command": "wakeonlan {mac}",
        "verifyCommand": "",
        "availableWhen": "offline",
        "confirm": false,
        "timeout": 10
      },
      {
        "id": "uuid",
        "type": "toggle",
        "name": "Skip alarm",
        "icon": "alarm-symbolic",
        "stateCommand": "{ssh} test -f /path/skip-alarm",
        "onCommand": "{ssh} touch /path/skip-alarm",
        "offCommand": "{ssh} rm -f /path/skip-alarm",
        "availableWhen": "online",
        "confirm": false,
        "timeout": 10
      }
    ]
  }
]
```

### Function types

| Type     | Commands                                  | Semantics                                                                                                                    |
| -------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `status` | `command`                                 | Runs every `interval` seconds (or the General default). Exit code 0 means online. A server's online state comes from its **first** `status` function. |
| `action` | `command`, optional `verifyCommand`       | Runs on click. Success is the exit code of `verifyCommand` if set, otherwise of `command`.                                   |
| `toggle` | `stateCommand`, `onCommand`, `offCommand` | `stateCommand` exit 0 means on. A click runs `onCommand` or `offCommand`, then re-reads the state.                           |

Shared fields:

- `availableWhen`: `online` \| `offline` \| `always`. The button is disabled otherwise.
- `confirm`: show an "Are you sure?" dialog before running.
- `timeout`: seconds.

Toggle states are **not** polled continuously, to avoid constant SSH connections. They refresh
when the popup opens, after any action on that server, and when the server comes online.

Details of the implementation:

- Further `status` functions after the first run on their own interval too and show as a small
  indicator (ok / failed) in the popup. They don't affect the online state.
- An action's `verifyCommand` runs after `command` has finished, whatever its exit code.
- A toggle whose `stateCommand` times out shows as "unknown": a warning sign replaces the switch's
  handle, and the tooltip explains. A click reads the state again instead of switching.
  A toggle that isn't available in the current server state is not read at all.
- `availableWhen` `online`/`offline` disables the control while the server's state is not known
  yet. A server without a `status` function has no online state, so all its functions are
  available.
- After an action or toggle command, all status checks and toggle states of that server are read
  again.
- An action whose `availableWhen` is `online` or `offline` (Wake, Power off, Reboot) is expected to
  change the online state, so it starts faster polling of that server. Actions available `always`
  don't.

### Placeholders

Substituted in every command before it runs:

| Placeholder                           | Value                                                    |
| ------------------------------------- | -------------------------------------------------------- |
| `{host}`, `{mac}`, `{user}`, `{name}` | From the server entry                                    |
| `{ssh}`                               | `ssh <SSH options> {user}@{host}`                        |

The SSH options come from the General settings (config key `sshOptions`, default
`-o BatchMode=yes -o ConnectTimeout=5`). They are inserted as typed, not quoted; empty options
give plain `ssh {user}@{host}`.

Shell-quote substituted values where needed. Unknown placeholders are left as is and flagged
in the settings UI. The settings also flag known placeholders whose server field is empty
(e.g. `{mac}` without a MAC address; `{ssh}` counts as using `{host}`).

### Templates (preconfigured functions)

"Add function" offers these, each filled with editable defaults:

- **Status (ping)**: `ping -c 1 -W 1 {host}`, default interval
- **Wake-on-LAN**: `wakeonlan {mac}`, available offline
- **Power off**: `{ssh} sudo systemctl poweroff`, available online, confirm on
- **Reboot**: `{ssh} sudo systemctl reboot`, available online, confirm on
- **Flag toggle**: asks for a path, generates `test -f` / `touch` / `rm -f`
- **Custom**: empty

## UI

### Compact representation (panel)

- One icon with a status dot overlay:
  - green: all servers online
  - orange: some servers online
  - grey: none online
- While an action runs, the icon dims and a spinner turns over it. The dot stays visible.
- Tooltip: a one-line summary per server.

### Full representation (popup)

- A list of servers, each with a name, a status dot, and buttons/switches for its functions.
- The popup stays open while commands run and results show. It closes only when the user clicks
  outside it or on the panel icon.
- Disabled controls (wrong online state) are greyed out and their tooltip says why.
- Confirmation uses a Kirigami dialog that names the server and the function.

### Feedback

- Primary feedback is visual: the status dot, plus a short inline result per function:
  - ✓ / ✗ replaces the button's icon, or the switch's handle, so the row doesn't reflow. Toggles
    show only ✗: on success, the switch moving to the new state is the feedback.
  - On failure, a line under the server's controls shows "<function>: <last line of stderr>"
    (or the exit code if stderr is empty). The control's tooltip shows the full stderr.
  - ✓ shows for 3 s, ✗ and the error line for 10 s, then they disappear (no fade: a fading ✓
    overlapped the returning icon).
  - While its result shows, a control stays enabled even if the function has just become
    unavailable (Wake brings the server online during its ✓). Clicks are ignored then.
- After Wake or Power off (see "Function types"), poll the server's status functions every 5 s
  for 2 min (a shorter configured interval is kept), so the state change shows up quickly.

### Settings dialog

- **Servers** page: add, edit, remove and reorder servers. Each server has a function list
  with add-from-template, edit, remove and reorder.
  - Every edit is written to `cfg_servers` right away (as JSON, via `serializeServers()`), so
    Apply enables; Cancel discards. The page parses the saved config with `parseServers()`. If
    that produced warnings, an inline message says that invalid entries are fixed or left out
    when applied.
  - Until the templates exist, "Add function" offers the three types with default values.
  - The function editor shows the fields of the function's type. Changing the type keeps name,
    icon, timeout, unknown fields and the fields both types share; fields only the old type
    used are dropped (`changeFunctionType()` in `model.js`).
  - Under each command field: the command as it will run on this server (placeholders
    substituted), and a warning for unknown or empty placeholders.
  - The first status function is labelled "Online/Server state" in the function list.
  - A status function's check interval has a "Default" check box. Checked, the function has no
    `interval` and uses the General default, which the disabled spin box shows.
  - The command previews use the saved SSH options. Changes on the General page show here only
    after Apply, because the dialog shows one page at a time.
- **General** page: default status interval and SSH options.
  - The controls write `cfg_defaultInterval` and `cfg_sshOptions` directly.
  - Below the SSH options: what `{ssh}` becomes, and a warning if the options lack
    `BatchMode=yes` (ssh would wait for a password until the timeout).
  - When either setting changes, the widget runs all status checks on the next tick.
  - Plasma passes every config key (and its `…Default`) to every page as `cfg_<key>`. Each page
    declares all of them, or Plasma logs a warning for each missing one.
- The **General** page also has JSON import/export of the whole setup, for backups and copying
  setups between machines. The format is `{ "version": 1, "general": {…}, "servers": [ … ] }`.
  Import also accepts a bare server list.

## Technical reference (Plasma 6)

### Package layout

```
package/
├── metadata.json             # KPackageStructure: "Plasma/Applet", X-Plasma-API-Minimum-Version: "6.0"
└── contents/
    ├── config/
    │   ├── main.xml          # KConfigXT schema: servers (JSON string), defaultInterval, sshOptions
    │   └── config.qml        # ConfigModel with ConfigCategory pages
    └── ui/
        ├── main.qml          # PlasmoidItem root
        ├── CompactRepresentation.qml
        ├── FullRepresentation.qml
        ├── ServerDelegate.qml
        ├── FunctionControl.qml # one function: status indicator, action button or toggle switch
        ├── ResultIcon.qml    # ✓ / ✗ after a command
        ├── CommandRunner.qml # wraps the executable data engine
        ├── ConfigServers.qml # settings page (KCM.SimpleKCM): server list, server form, function list
        ├── FunctionEditor.qml # settings form for one function
        ├── CommandField.qml  # settings field for one command, with preview and placeholder warnings
        ├── ConfigGeneral.qml # settings page: default check interval, SSH options
        └── code/
            ├── model.js      # parse/validate/serialize config JSON
            ├── templates.js  # preconfigured functions (planned)
            └── commands.js   # placeholder substitution and quoting

tools/
├── set-config.sh             # writes a server list JSON file into the running widget(s)
└── sandbox/
    ├── Containerfile         # Podman image with Plasma 6, plasmoidviewer, Xvfb
    ├── entrypoint.sh         # runs inside the container: Xvfb, plasmoidviewer, log check
    ├── page-harness.qml      # test widget that loads a settings page (load-test.sh --page)
    └── load-test.sh          # builds the image if needed, runs the load test

examples/
├── demo-local.example.json           # every function type, harmless local commands only (/tmp)
└── home-server.example.json          # a realistic server; edit host, mac, user and paths first
```

### APIs to use

- Root item: `PlasmoidItem` (`import org.kde.plasma.plasmoid`). Config is read via
  `Plasmoid.configuration.<key>`.
- UI: `org.kde.plasma.components` (PlasmaComponents3), `org.kde.kirigami` (Kirigami),
  `org.kde.plasma.extras` (PlasmaExtras).
- Config pages: root `KCM.SimpleKCM` (`import org.kde.kcmutils as KCM`), with `cfg_<key>`
  properties bound to the config keys.
- Running commands: `P5Support.DataSource` with `engine: "executable"`
  (`import org.kde.plasma.plasma5support as P5Support`).
  - `connectSource(cmd)` runs `cmd`. `onNewData(source, data)` gives `data["exit code"]`,
    `data["stdout"]` and `data["stderr"]`. Then call `disconnectSource(source)`.
  - Identical command strings share one source. Make each invocation unique, e.g. by
    appending a ` # <counter>` comment, and map sources to callbacks.
  - The engine has no timeout. Wrap commands as `timeout <s> sh -c '<cmd>'`.
- Do **not** use Plasma 5 APIs: `Plasmoid.compactRepresentation` set on a plain `Item`,
  `PlasmaCore.Theme`, `QtQuick.Controls 1`, or `metadata.desktop`.

### Testing on Linux

```sh
plasmoidviewer -a package/                                 # quick preview (needs plasma-sdk)
plasmoidviewer -a package/ -l bottomedge -f horizontal     # preview as panel
kpackagetool6 -t Plasma/Applet -i package/                 # install
kpackagetool6 -t Plasma/Applet -u package/                 # update after changes
systemctl --user restart plasma-plasmashell                # reload the panel if needed
journalctl --user -f | grep -i -E "qml|plasmashell"        # QML errors
tools/set-config.sh examples/demo-local.example.json               # load a test config into the running widget
```

### Self-testing (for Claude): load test in a Podman sandbox

After every change to files in `package/`, run the load test yourself instead of asking the
user to copy errors back:

```sh
tools/sandbox/load-test.sh
```

How the sandbox works:

- **Container engine: Podman** (rootless). Docker is installed too, but use it only if Podman
  fails, and tell the user if you do.
- **Image** (`tools/sandbox/Containerfile`): a distribution with current Plasma 6 packages
  (Fedora is a good default) plus `plasma-sdk` (for `plasmoidviewer`), Xvfb and dbus. Check the
  package names when building; don't guess.
- **Run:**
  `podman run --rm --network none -v "$PWD/package:/package:ro,Z" servercontrol-sandbox`
  - `--network none`: the widget can't reach any network, so commands can never affect real
    servers.
  - `:ro,Z`: the package is mounted read-only. `Z` sets the SELinux label so the container
    can read it.
  - The image is built once (`podman build -t servercontrol-sandbox tools/sandbox`).
    Rebuild only when the Containerfile changes. Code changes need no rebuild because
    `package/` is mounted.
- **Inside the container:** start Xvfb (virtual screen), then
  `dbus-run-session timeout 15 plasmoidviewer -a /package`, capturing all output.
- **Result:** the script prints the QML errors and warnings that refer to files in `/package`
  and exits non-zero if there are any. Errors are usually explicit ("Type X unavailable",
  "Cannot assign to non-existent property") and can be fixed directly.

Workflow:

1. Change code, run `load-test.sh`, fix errors, repeat until it passes.
2. Report that the load test passed and list what the user still has to test manually, with
   concrete steps (e.g. "open the popup, click Wake on a server that is offline, check …").

Rules:

- The load test proves only that the widget starts without errors. Don't claim that a feature
  works because the load test passed.
- If you need a test config in the sandbox, use only harmless commands (`true`, `false`,
  `sleep 3`, `echo`). Pass it with `tools/sandbox/load-test.sh -v --servers FILE`.
  `plasmoidviewer` discards a preset applet config (`~/.config/plasmoidviewer-appletsrc`), so the
  script copies the package and makes the file the default of the `servers` key in `main.xml`.
  Invalid JSON is passed through as is, to test the fallback.
- Settings pages never open in `plasmoidviewer`, so the plain load test doesn't cover them.
  After changing a settings page (or a file it uses), also run
  `tools/sandbox/load-test.sh --page ConfigServers --servers examples/demo-local.example.json`
  and `tools/sandbox/load-test.sh --page ConfigGeneral`.
  `tools/sandbox/page-harness.qml` replaces `main.qml` in a copy of the package, loads the page
  with a `cfg_` property for every config key (as Plasma does), and calls its edit functions
  step by step (select each function, add, set and clear an interval, change type, move,
  remove; on the General page, set the SSH options and the interval). Add `--screenshots DIR` to save a PNG per step and look at them.
  When a page's edit functions change, update the steps in the harness.
- `console.log` output is filtered in the sandbox; use `console.warn` for temporary debug output,
  and remove it afterwards.
- The first run after an image rebuild takes a few minutes: `--userns=keep-id` makes Podman
  copy the image once. Later runs take about 20 s. Run long ones in the background.
- Don't install into the user's live panel or restart `plasmashell` without asking, because
  that affects the running desktop.

### Server-side prerequisites (document in README)

- Key-based SSH from the desktop to each server, with no password prompt (ssh-agent or a
  dedicated key).
- A sudoers rule for passwordless poweroff and reboot, e.g.
  `user ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot`
- A Wake-on-LAN tool on the desktop (`wakeonlan` or `wol`).

## Roadmap

Work in phases. Each phase should be usable and testable on its own.

0. **Sandbox** (done): `Containerfile` and `load-test.sh`. Done when a minimal widget (a single
   label) loads in the container without errors, and a deliberately broken QML file makes
   the test fail.
1. **Skeleton** (done): package layout, metadata, compact and full representations, `CommandRunner`
   with timeout. One server hardcoded in JS, with ping status shown as a dot.
2. **Generic model** (done): JSON config model, all three function types, placeholders,
   confirmation dialog, inline feedback, faster polling after wake/poweroff.
3. **Settings UI** (in progress): server and function editor (done), General page with default
   interval and SSH options (done), templates, JSON import/export.
4. **Later options**:
   - Panel mode: one icon for all servers vs. one dot per server in the compact view, plus a
     per-instance "show only these servers" filter.
   - Optional Plasma notifications for action results (`org.kde.notification` or
     `notify-send`), configurable per widget and/or per function.
   - Showing the next RTC wake time (`cat /sys/class/rtc/rtc0/wakealarm`) via a custom function.
   - **Tailscale support.** The user enables Tailscale on the laptop only when away from home.
     - Detection: a configurable command in the General settings (exit code 0 = active), default
       `tailscale status --json | grep -q '"BackendState": *"Running"'`. Run it together with
       the status checks, not more often.
     - Servers without a `tailscaleHost` show as "Not reachable" while Tailscale is active.
     - The settings' command preview shows both the LAN and the Tailscale version of a command.
     - When Tailscale is active and a server has a `tailscaleHost`, `{host}` (and with it
       `{ssh}`) resolves to that address. Add explicit `{lanhost}` and `{tshost}` placeholders.
     - The popup shows a small "via Tailscale" badge on affected servers.
     - Wake-on-LAN can't work over Tailscale (broadcast, and an off server isn't in the
       tailnet). While Tailscale is active, functions that use `{mac}` are disabled, with the
       tooltip "Wake-on-LAN needs the local network". No relay host is planned.

## Conventions

- Keep logic in `code/*.js` (pure functions, easy to reason about) and keep QML files focused on UI.
- All user-visible strings go through `i18n()` / `i18nc()`.
- Never block the UI. Every command is asynchronous and has a timeout.
- Commands run with the user's privileges, exactly as configured. Don't add hidden commands.
- Never commit by yourself. The user commits.

## Documentation

Docs are part of the change. Update them in the same step as the code that affects them.
Never leave a doc describing behaviour that no longer exists.

| Doc                                 | Audience               | Update when …                                                                                                               |
| ----------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md`                         | Claude, developer      | The data model, function types, placeholders, templates, conventions or package layout change; a roadmap phase is finished |
| `docs/QML through this codebase.md` | The user, learning QML | Any file in `package/contents/ui/` is added, removed, renamed or changes in a way that affects a quoted excerpt             |

### Rules

- **CLAUDE.md is the spec.** If the implementation deliberately differs from it, update CLAUDE.md
  and mention the change in your report. Don't silently drift from it.
- **Code excerpts must match the code.** After editing a file, grep `docs/` for its name and check
  every excerpt and explanation that refers to it.
- **QML guide specifics:**
  - Keep the file table (files, line counts, descriptions) and the "as it stands after phase N"
    line up to date.
  - If the code uses a QML concept the guide doesn't cover yet (e.g. `Repeater`, `Loader`,
    `Connections`, Kirigami dialogs, `KCM.SimpleKCM`), add a short entry to Part 1 using
    the real code as the example.
  - Edit only the affected sections; don't rewrite the guide.
  - Keep its style: short sentences, real excerpts from this repo, no generic examples.
- **Roadmap:** when a phase is done, mark it done in CLAUDE.md.

### Reporting

End every task that changes code with a "Docs" line: either which docs you updated, or
"no doc changes needed" and why.
