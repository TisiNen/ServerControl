# QML through this codebase

Nov 4, 2026 · @Tilo

## How to read this guide

This guide teaches QML using only the Server Control widget as it stands after phase 1: 7 source files, about 440 lines. Read Part 1 first, then follow one status check through the code in Part 3; the per-file notes in Part 4 are for looking things up.

| File | Lines | Language | What it is |
| --- | --- | --- | --- |
| `package/metadata.json` | 18 | JSON | Tells Plasma this folder is a widget: name, icon, plugin ID |
| `package/contents/ui/main.qml` | 117 | QML | The root of the widget: state, timer, status checks |
| `package/contents/ui/CommandRunner.qml` | 52 | QML | Runs shell commands in the background and calls you back |
| `package/contents/ui/CompactRepresentation.qml` | 50 | QML | The panel icon with its coloured dot |
| `package/contents/ui/FullRepresentation.qml` | 66 | QML | The popup: heading, refresh button, server list |
| `package/contents/ui/ServerDelegate.qml` | 63 | QML | One row in the popup list, one per server |
| `package/contents/ui/code/model.js` | 38 | JavaScript | The hardcoded demo server and a lookup helper |
| `package/contents/ui/code/commands.js` | 52 | JavaScript | Placeholder substitution, shell quoting, timeout wrapping |

If you know JavaScript, you already know half of QML: everything inside `function`, `{ … }` property expressions and `on…` handlers is ordinary JavaScript. The new part is the declarative layer around it, which Part 1 covers.

## Part 1: QML basics

A QML file describes a tree of objects and how their properties depend on each other; the engine keeps those dependencies up to date for you. The twelve ideas below explain almost every line in this repo.

### 1. A file is a tree of objects

A QML file has `import` lines, then exactly one root object. An object is written `TypeName { … }`. Objects written inside another become its children.

```qml
MouseArea {              // root object of CompactRepresentation.qml
    Kirigami.Icon { … }  // child 1: the server icon
    Rectangle { … }      // child 2: the status dot
    PlasmaComponents3.BusyIndicator { … }  // child 3: the spinner
}
```

Visual children are drawn on top of their parent, later children on top of earlier ones. That is why the dot appears over the icon.

### 2. Imports

```qml
import QtQuick                                   // basic types: Item, Rectangle, Timer, MouseArea
import org.kde.kirigami as Kirigami              // KDE types, used as Kirigami.Icon, Kirigami.Theme
import "code/commands.js" as Commands            // a JS file, used as Commands.substitute(…)
```

`as Name` puts everything from that module under a prefix, so `Kirigami.Icon` and `PlasmaComponents3.Label` can't clash. A quoted path imports a local file or folder.

### 3. Properties: setting and declaring

Inside an object, `name: value` sets an existing property of that type, such as `width`, `color` or `interval`. To add a new one, declare it:

```qml
property int actionsRunning: 0             // new int, starts at 0
property var serverStates: ({})            // var = any JS value; ({}) is an empty object
readonly property bool busy: actionsRunning > 0   // can't be assigned from outside
required property PlasmoidItem plasmoidItem      // whoever creates this object must set it
```

The parentheses in `({})` are needed because a bare `{` would start a code block. A name starting with `_`, like `_counter`, is only a convention for "private"; QML doesn't enforce it.

### 4. Bindings: the core idea

When a property's value is an expression, QML records which properties the expression reads. When any of them changes, it re-evaluates the expression automatically. This is a **binding**.

```qml
readonly property bool busy: actionsRunning > 0
```

Nobody ever writes `busy = true`. When `actionsRunning` changes, `busy` updates, then everything that reads `busy` updates, such as the spinner's `running: compact.plasmoidItem.busy`. A chain of bindings carries a change from the data to the screen.

A binding can be a whole block of JS, as long as it returns a value. `onlineCount` in `main.qml` is one: it loops over `servers` and `serverStates`, so it recalculates when either changes.

**Binding vs. assignment.** `color: x ? a : b` in the object declaration is a binding and stays live. `color = a` inside a function is an assignment: it sets the value once and removes any binding the property had.

**The object-property trap.** QML notices when a `var` property is given a new value, not when something inside the object changes. `serverStates[id] = "online"` would change the data, but no binding would re-run. That's why `setState()` in `main.qml` copies the object, changes the copy and assigns it back:

```qml
const next = Object.assign({}, serverStates);   // shallow copy
next[id] = state;
serverStates = next;                            // new object -> bindings re-run
```

`_nextCheck` and `_checking` are mutated in place on purpose: nothing binds to them, so nothing needs to be told.

### 5. id: naming an object

`id: runner` gives an object a name that any code in the same file can use, like `runner.run(…)` in `main.qml`. An id is not a property and isn't visible from other files. To reach an object from another file, pass it in through a property, which is what `plasmoidItem: root` does (see 8).

`parent` is a built-in reference to the visual parent, as in `anchors.fill: parent`.

### 6. Signals and handlers

Objects announce events with **signals**. You react by writing a handler named `on` + the signal name with a capital letter:

```
Timer {
    onTriggered: { … }            // the Timer's triggered() signal
}
MouseArea {
    onPressed: wasExpanded = plasmoidItem.expanded
    onClicked: plasmoidItem.expanded = !wasExpanded
}
```

Every property also gets a free `…Changed` signal. `onExpandedChanged` in `main.qml` runs whenever the `expanded` property changes, which is how the widget refreshes when the popup opens.

If a signal passes arguments, you can name them with an arrow function: `onNewData: (sourceName, data) => { … }` in `CommandRunner.qml`.

### 7. Functions

`function name(args) { … }` inside an object adds a method to it. Others call it through the object's id or a property, like `full.plasmoidItem.refreshAll()`. The body is plain JavaScript and can read and assign the object's properties directly.

### 8. Each file is a reusable type

A file named `CommandRunner.qml` defines a new type `CommandRunner`, usable from any QML file in the same folder without an import. Its root object's properties and functions become the type's public interface.

```qml
// main.qml uses three of the repo's own files as types
compactRepresentation: CompactRepresentation { plasmoidItem: root }
fullRepresentation: FullRepresentation { plasmoidItem: root }
CommandRunner { id: runner }
```

The file name must start with a capital letter.

### 9. Lists: model, view, delegate

To show a list, you give a view a **model** (the data) and a **delegate** (a template for one item). The view creates one delegate instance per entry.

```qml
ListView {
    model: full.plasmoidItem.servers     // a JS array of server objects
    delegate: ServerDelegate { … }        // one row per server
}
```

With a JS array as model, each delegate gets its entry as `modelData`. `ServerDelegate.qml` declares `required property var modelData` to receive it, then reads `modelData.name` and `modelData.host`.

### 10. Positioning: anchors and layouts

Two ways to place items:

- **Anchors** tie an item's edges to another item's: `anchors.fill: parent`, `anchors.right: parent.right`, `anchors.centerIn: parent`.
- **Layouts** (`RowLayout`, `ColumnLayout` from `QtQuick.Layouts`) arrange their children in a row or column. Children tune their place with attached properties like `Layout.fillWidth: true` or `Layout.alignment: Qt.AlignVCenter`.

`implicitWidth`/`implicitHeight` is the size an item would like to have; layouts use it when nothing else is set.

### 11. Attached properties

A property written `TypeName.property` belongs to another type but is set on this object: `Layout.fillWidth`, `PlasmaComponents3.ToolTip.text`, `ListView.view.width`. Read it as "the Layout settings for this object" or "the tooltip of this button".

### 12. JavaScript files

`.pragma library` at the top of a JS file means it is loaded once and shared by every QML file that imports it. Such a file has no access to QML objects, only to what you pass into its functions. That keeps `model.js` and `commands.js` as pure helpers.

## Part 2: The Plasma-specific parts

Plasma adds a root type for widgets, two ways to show them, and a way to run shell commands; everything else is standard QML.

### PlasmoidItem: the widget's root

Every Plasma 6 widget's `main.qml` has a `PlasmoidItem` as its root (`import org.kde.plasma.plasmoid`). Plasma creates it once, when the widget is added to a panel or desktop, and keeps it alive for as long as the widget exists. That makes it the right place for state that must survive the popup closing: `serverStates`, the timer, the command runner.

Properties the repo uses:

| Property | Set or read by | Meaning |
| --- | --- | --- |
| `compactRepresentation` | `main.qml` sets | What to show in the panel |
| `fullRepresentation` | `main.qml` sets | What to show in the popup |
| `expanded` | read and set | `true` while the popup is open |
| `toolTipMainText`, `toolTipSubText` | `main.qml` sets | The tooltip on the panel icon |

There is also an attached object `Plasmoid` (capital P) that gives access to the applet itself: `Plasmoid.icon` (from `metadata.json`) and, from phase 2 on, `Plasmoid.configuration.servers` for the saved settings.

### Compact and full representation

A widget has two faces. The **compact representation** is the small thing in the panel; the **full representation** is the popup that opens when you click it. Plasma decides when to create and show each one.

```qml
compactRepresentation: CompactRepresentation { plasmoidItem: root }
fullRepresentation: FullRepresentation { plasmoidItem: root }
```

These lines don't create the objects right away. A property of type `Component` takes a *template*, and Plasma instantiates it when needed. That's why the representations can't simply use the id `root`: they live in other files, so `main.qml` hands itself over through the `plasmoidItem` property.

On the desktop (not in a panel) and when there is enough room, Plasma may show the full representation directly. The code doesn't need to care.

### The KDE UI libraries

| Import | Prefix in this repo | Used for |
| --- | --- | --- |
| `org.kde.kirigami` | `Kirigami.` | `Icon`, `Heading`, `Theme` (colours), `Units` (sizes and spacing) |
| `org.kde.plasma.components` | `PlasmaComponents3.` | `Label`, `ToolButton`, `ScrollView`, `BusyIndicator`, `ToolTip`, styled to match the panel |
| `org.kde.plasma.extras` | `PlasmaExtras.` | `Representation`, `PlasmoidHeading`, `PlaceholderMessage`: popup building blocks |

Two Kirigami helpers show up everywhere:

- `Kirigami.Theme.positiveTextColor`, `neutralTextColor`, `disabledTextColor`, `backgroundColor`: colours from the user's colour scheme, so green, orange and grey adapt to light and dark themes.
- `Kirigami.Units.gridUnit`, `smallSpacing`, `largeSpacing`: sizes that scale with the user's font size. Use these instead of fixed pixel values.

### Running shell commands: P5Support.DataSource

QML has no built-in way to run a program. Plasma offers the old "data engine" system, kept in Plasma 6 under `org.kde.plasma.plasma5support`. The `executable` engine treats each **source name** as a shell command:

1. `connectSource("ping -c 1 …")` starts the command in the background.
2. When it finishes, the DataSource emits `newData(sourceName, data)`. `data` holds `"exit code"`, `"stdout"` and `"stderr"`.
3. You call `disconnectSource(sourceName)` so it doesn't run again.

Two quirks shape `CommandRunner.qml`. Two identical command strings would be one source, so the second wouldn't run; a `  # 7 ` comment makes each one unique. And the engine has no timeout, so every command is wrapped in `timeout`.

### metadata.json

The file Plasma reads to find the widget at all. `KPackageStructure: "Plasma/Applet"` says it's a widget, `Id` must be unique and matches the install folder, and `Icon` becomes `Plasmoid.icon`. Plasma looks for `contents/ui/main.qml` by convention.

## Part 3: One status check, start to finish

A timer starts the ping, `CommandRunner` runs it in the background, and one assignment to `serverStates` makes the dot turn green through bindings alone. Here is every step, with the file and line where it happens.

&#91;embedded content: one status check · 7 steps, then bindings\]

The top two rows are code that runs; the bottom row updates by itself because each part binds to `serverStates`.

1. **The widget starts.** Plasma creates the `PlasmoidItem` in `main.qml`. Its `servers` property is evaluated once: `Model.defaultServers()` returns an array with the demo server "NAS" at `192.168.1.10`. `serverStates` starts as `{}`, so every server counts as "not checked yet".
2. **The timer fires.** `Timer` has `triggeredOnStart: true`, so `onTriggered` runs right away, then every 1000 ms (`main.qml:103-116`). For each server it compares `Date.now()` with `_nextCheck[s.id]`. Nothing is stored yet, so `|| 0` makes the check due and it calls `checkStatus(s)`.
3. **checkStatus prepares the command** (`main.qml:60-71`).
   1. `Model.statusFunction(server)` finds the server's first function with `type: "status"`.
   2. If a check for this server is already running (`_checking[server.id]`), it stops here. This prevents two pings piling up when a host is slow.
   3. It marks the check as running and schedules the next one: now + 30 s.
   4. `Commands.substitute("ping -c 1 -W 1 {host}", server)` turns the template into `ping -c 1 -W 1 192.168.1.10`.
   5. It calls `runner.run(command, 10, callback)`. The callback is an arrow function that will run later.
4. **CommandRunner starts it** (`CommandRunner.qml:21-29`). `Commands.withTimeout` wraps the command as `timeout -k 2 10 sh -c 'ping -c 1 -W 1 192.168.1.10'`, and `  # 1 ` is appended to make the source name unique. The callback is stored under that exact string in `_callbacks`, and `connectSource(source)` hands the command to Plasma.
5. **Nothing blocks.** `run()` returns immediately and the UI keeps responding. Plasma runs the shell command in a separate process.
6. **The result arrives** (`CommandRunner.qml:31-51`). Plasma emits `newData(sourceName, data)`. The handler looks up the callback by `sourceName`, removes it, disconnects the source and checks whether the exit code is a timeout (124 or 137). Then it calls the callback with `{ exitCode: 0, stdout, stderr, timedOut: false }`.
7. **The state changes** (`main.qml:67-70`). The callback clears `_checking` and calls `setState("demo-server", "online")`. `setState` copies `serverStates`, sets the entry and assigns the copy back.
8. **Bindings take over.** That single assignment is the only thing the code "does"; everything below happens because properties read `serverStates`:
   - `onlineCount` recalculates to 1, so `overallState` becomes `"all"`.
   - In the panel, `dotColor` becomes `Kirigami.Theme.positiveTextColor`, so the dot `Rectangle` turns green (`CompactRepresentation.qml:15-17, 39`).
   - In the popup, if it is open, `ServerDelegate`'s `serverState` becomes `"online"`: its dot turns green and its label shows "Online" (`ServerDelegate.qml:14, 31, 58`).
   - The tooltip's `toolTipSubText` calls `stateText(s)` and now reads "NAS: Online".
9. **30 seconds later** the timer finds the check due again, and the cycle repeats. If ping fails, the same chain runs with `"offline"` and the dots turn grey.

Two other ways into `checkStatus`: opening the popup (`onExpandedChanged` calls `refreshAll()`), and the refresh button in the popup header, which calls the same function.

A note on step 8: `toolTipSubText` and the delegate's label call a *function*, `stateText()`. QML still tracks this, because a binding records every property read while it runs, including reads inside functions it calls.

## Part 4: Per-file notes

Each note covers what the file is for and the lines that are hard to read the first time. The numbers in brackets point to the ideas in Part 1.

### main.qml

The root of the widget and the only place that holds state. Everything else reads from it.

- **Lines 4-5:** imports the two JS helpers as `Model` and `Commands` \[12\].
- **Line 10, `servers`:** `readonly` and bound to a function call with no inputs, so it is evaluated once. In phase 2 this will read `Plasmoid.configuration.servers` instead, and become a live binding.
- **Line 13, `serverStates`:** the central state, a map from server id to `"online"`/`"offline"`. Always replaced, never mutated \[4\].
- **Lines 17-18, `actionsRunning` and `busy`:** nothing changes `actionsRunning` yet; it is ready for phase 2, when Wake and Power off will count up and down. Status checks deliberately don't count, or the spinner would flash every 30 s.
- **Lines 20-31, `onlineCount` and `overallState`:** two derived bindings \[4\]. `overallState` uses chained `? :` to pick `"all"`, `"some"` or `"none"`; the `servers.length > 0` guard stops an empty list from counting as "all online".
- **Lines 34-35, `_nextCheck` and `_checking`:** bookkeeping. Mutated in place because no binding reads them.
- **Lines 37-49, `stateText()`:** turns a state into a translated label. `i18n()` is Plasma's translation function; every user-visible string goes through it.
- **Lines 51-58, `setState()`:** returns early if nothing changed, so bindings don't re-run for nothing. Then the copy-and-assign pattern.
- **Lines 60-77, `checkStatus()` and `refreshAll()`:** see Part 3, step 3.
- **Lines 79-81, tooltip:** `i18nc("context", "%1: %2", a, b)` is `i18n` with a hint for translators; `%1` and `%2` are filled from the arguments.
- **Lines 83-87, `onExpandedChanged`:** a property-change handler \[6\] that refreshes when the popup opens.
- **Lines 89-95:** the two representations, each handed a reference to `root` (Part 2).
- **Lines 97-99:** one `CommandRunner` instance, named `runner` \[8\]. It isn't visual; a `PlasmoidItem` can hold non-visual children.
- **Lines 103-116, `Timer`:** one timer ticking every second, instead of one timer per server. Each server's next check time is stored in `_nextCheck`, so servers can have different intervals and phase 2 can speed one up after Wake. Inside the handler, the code writes `root.servers` and `root.checkStatus` with the id: inside a child object, being explicit avoids confusion with the Timer's own properties.

### CommandRunner.qml

A reusable type that turns Plasma's data engine into a simple `run(command, timeout, callback)` call (Part 2).

- **Line 9:** the root is the `DataSource` itself, so `CommandRunner` *is* a DataSource with an extra function \[8\].
- **Line 12, `runningCount`:** a read-only public view of the private `_running`. Not used yet.
- **Line 16, `_callbacks`:** a JS object used as a map from source name to callback. Mutated in place; nothing binds to it.
- **Lines 18-19:** `engine: "executable"` selects the shell-command engine; `connectedSources: []` starts with nothing running.
- **Lines 21-29, `run()`:** builds the unique source string, stores the callback under it, counts up, starts it.
- **Lines 31-51, `onNewData`:** the signal handler with named arguments \[6\]. It removes the callback *before* calling it, so a callback that throws can't leave a stale entry behind. `String(data["stderr"] || "")` guards against a missing field. A timeout with empty stderr gets the message "Timed out" so the UI has something to show.

### CompactRepresentation.qml

The panel icon. The root is a `MouseArea`, an invisible item that receives clicks and hovers, with the icon, dot and spinner as children \[1\].

- **Line 9, `required property PlasmoidItem plasmoidItem`:** the link back to `main.qml` \[3\]. `required` makes it an error to create this without one.
- **Lines 13, 22-23, `wasExpanded`:** a fix for a classic problem. When the popup is open and you press the icon, Plasma closes the popup because focus left it. By the time `clicked` arrives, `expanded` is already `false`, so a naive toggle would reopen it. Remembering the value at *press* time gives the right result.
- **Lines 15-17, `dotColor`:** maps `overallState` to a theme colour \[4\].
- **Lines 25-29, `Kirigami.Icon`:** fills the area \[10\] and shows `Plasmoid.icon`. `active` gives the hover highlight; `containsMouse` works because of `hoverEnabled: true`.
- **Lines 31-43, the dot:** a `Rectangle` with `radius` equal to half its width is a circle. Its size is 40% of the icon, at least 6 px. Anchored to the bottom-right corner. Its border uses the background colour, which gives it a thin outline against the icon. Hidden while busy.
- **Lines 45-49, `BusyIndicator`:** sits exactly where the dot is (`anchors.fill: dot`) and runs while `busy` is true. So the spinner replaces the dot.

### FullRepresentation.qml

The popup.

- **Line 8, `PlasmaExtras.Representation`:** a popup container with `header` and `contentItem` slots, so the heading and list get the standard Plasma look.
- **Lines 13-16, `Layout.*` sizes:** tell Plasma how big the popup may be, in grid units (multiples of the font size).
- **Line 18, `collapseMarginsHint`:** lets the list run to the popup's edges instead of sitting inside a margin.
- **Lines 20-42, header:** a `RowLayout` with a heading that takes all spare width (`Layout.fillWidth`) and a refresh button. The button has `text` even though it shows only an icon (`display: IconOnly`); the text is used by screen readers and by its own tooltip (`ToolTip.text: text`). `ToolTip.*` are attached properties \[11\].
- **Lines 44-65, list:** a `ScrollView` around a `ListView` \[9\]. `width: ListView.view.width` is an attached property that makes each row as wide as the list. `clip: true` stops rows from drawing outside the list while scrolling.
- **Lines 57-63, `PlaceholderMessage`:** a child of the ListView, centred on it, shown only when `list.count === 0`. Phase 1 always has one server, so you won't see it until phase 2.

### ServerDelegate.qml

One row of the list, created once per server by the `ListView`.

- **Line 7:** the root is a plain `Item`, a blank invisible container.
- **Line 10, `modelData`:** filled in by the ListView with this row's server object \[9\].
- **Line 14, `serverState`:** looks up this server's state, or `""` if there is none yet.
- **Line 16, `implicitHeight`:** the row is as tall as its content plus a small margin. A ListView needs each delegate to have a height.
- **Lines 26-36, dot:** a circle in a `RowLayout`, so it uses `implicitWidth` instead of `width` \[10\]. Not checked yet means transparent fill with a 1 px border: an empty ring.
- **Lines 38-55:** name above host, the host smaller and at 70% opacity. `elide: Text.ElideRight` cuts long text with … instead of overflowing.
- **Lines 57-61:** the state label, coloured green when online.

### code/model.js

Pure data helpers, no QML \[12\]. In phase 2 this file will parse and validate the JSON config.

- **`defaultServers()`:** returns the one hardcoded server. To test against a real machine, change `name` and `host` here.
- **`statusFunction(server)`:** returns the first function whose `type` is `"status"`, or `null`. The `(server && server.functions) || []` guard means a malformed server can't crash it.

### code/commands.js

Turns a command template into a safe shell string.

- **`shellQuote(value)`:** values like hosts or names are inserted into a shell command, so a name containing a space or `;` must not break it or run something extra. Values made only of safe characters (letters, digits, `.`, `-`, `@`, …) are left as is. Anything else is wrapped in single quotes; a single quote inside is written `'\''` (end the quote, an escaped quote, start a new quote), the standard POSIX trick.
- **`sshCommand(server)`:** builds `ssh -o BatchMode=yes -o ConnectTimeout=5 user@host`. `BatchMode=yes` makes ssh fail instead of asking for a password, which would hang forever with no terminal.
- **`placeholderValues(server)`:** the map of `{name}` → value. `ssh` is not quoted again, because it is already a complete, quoted command.
- **`substitute(command, server)`:** the regex `\{(\w+)\}` finds every `{word}`. For each, the replace callback returns the value if the key is known, else the original text, so unknown placeholders stay visible. `hasOwnProperty.call` avoids matching built-in object keys like `{constructor}`.
- **`withTimeout(command, seconds)`:** `timeout -k 2 10 sh -c '<command>'`. `sh -c` runs the whole command, pipes and all, as one unit that `timeout` can stop. `-k 2` sends a hard kill 2 s later if the command ignores the polite stop.
- **`isTimeoutExit(code)`:** `timeout` exits with 124 after a normal stop and 137 after a kill.

### metadata.json

See Part 2. `Version` and `Authors` are shown in the widget's About page.

### tools/sandbox (not part of the widget)

The automatic load test, written in Bash, not QML.

- **`Containerfile`:** a Fedora 44 image with the Plasma 6 packages, `plasmoidviewer`, a virtual X screen (`Xvfb`) and dbus.
- **`entrypoint.sh`:** runs inside the container. Starts Xvfb, runs `plasmoidviewer` on the mounted package for 15 s, then searches the log for lines that mention `/package/` or applet load errors. Fails if it finds any, or if `plasmoidviewer` quit early.
- **`load-test.sh`:** runs on your machine. Builds the image if needed and starts the container with `--network none` and the package mounted read-only. `--self-test` swaps in a broken `main.qml` to prove the test catches errors.

## Glossary and further reading

| Term | Meaning in this repo |
| --- | --- |
| Attached property | `Type.prop` set on another object, e.g. `Layout.fillWidth` |
| Binding | A property expression that re-evaluates when what it reads changes |
| Compact representation | The panel icon (`CompactRepresentation.qml`) |
| Component | A template QML creates objects from later, e.g. a representation or delegate |
| Data engine / DataSource | Plasma's old plugin system; the `executable` engine runs shell commands |
| Delegate | The template for one list item (`ServerDelegate.qml`) |
| Full representation | The popup (`FullRepresentation.qml`) |
| Handler | Code that runs on a signal, named `on<Signal>` |
| id | A name for an object, usable only within its own file |
| Model | The data a view shows; here the `servers` array |
| Plasmoid | A Plasma widget; the package in `package/` |
| PlasmoidItem | The root type of a Plasma 6 widget (`main.qml`) |
| Signal | An event an object announces, e.g. `triggered`, `clicked`, `newData` |
| Source | In a DataSource, one connection; for `executable`, one command string |

Good next reads, in this order:

- [Qt: First steps with QML](https://doc.qt.io/qt-6/qmlfirststeps.html): the official introduction.
- [Qt: Property binding](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html): bindings in depth, including how assignments break them.
- [KDE: Plasma widget tutorial](https://develop.kde.org/docs/plasma/widget/): writing widgets for Plasma 6, including config pages, which phase 3 will need.
- [KDE: Kirigami tutorial](https://develop.kde.org/docs/getting-started/kirigami/): the UI library behind `Kirigami.Theme`, `Units` and dialogs.
