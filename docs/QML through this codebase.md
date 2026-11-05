# QML through this codebase

Nov 4, 2026 · @Tilo

## How to read this guide

This guide teaches QML using only the Server Control widget as it stands partway through phase 2 (the JSON config model, all three function types and the confirmation dialog are in; inline feedback and faster polling after Wake are not yet): 9 source files, about 1050 lines. Read Part 1 first, then follow a status check and a click through the code in Part 3; the per-file notes in Part 4 are for looking things up.

| File | Lines | Language | What it is |
| --- | --- | --- | --- |
| `package/metadata.json` | 18 | JSON | Tells Plasma this folder is a widget: name, icon, plugin ID |
| `package/contents/config/main.xml` | 15 | XML | The config schema: one `servers` key holding JSON |
| `package/contents/ui/main.qml` | 296 | QML | The root of the widget: config, state, timer, running all commands |
| `package/contents/ui/CommandRunner.qml` | 52 | QML | Runs shell commands in the background and calls you back |
| `package/contents/ui/CompactRepresentation.qml` | 55 | QML | The panel icon with its coloured dot and spinner |
| `package/contents/ui/FullRepresentation.qml` | 124 | QML | The popup: heading, refresh button, config warning, server list, confirmation dialog |
| `package/contents/ui/ServerDelegate.qml` | 101 | QML | One server in the popup list: dot, name, state and its functions |
| `package/contents/ui/FunctionControl.qml` | 141 | QML | One function: status indicator, action button or toggle switch |
| `package/contents/ui/code/model.js` | 215 | JavaScript | Parses and validates the `servers` config JSON; availability rules |
| `package/contents/ui/code/commands.js` | 52 | JavaScript | Placeholder substitution, shell quoting, timeout wrapping |

If you know JavaScript, you already know half of QML: everything inside `function`, `{ … }` property expressions and `on…` handlers is ordinary JavaScript. The new part is the declarative layer around it, which Part 1 covers.

## Part 1: QML basics

A QML file describes a tree of objects and how their properties depend on each other; the engine keeps those dependencies up to date for you. The nineteen ideas below explain almost every line in this repo.

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

A binding can be a whole block of JS, as long as it returns a value. `onlineCount` in `main.qml` is one: it loops over `serverList` and `serverStates`, so it recalculates when either changes.

**Binding vs. assignment.** `color: x ? a : b` in the object declaration is a binding and stays live. `color = a` inside a function is an assignment: it sets the value once and removes any binding the property had.

**The object-property trap.** QML notices when a `var` property is given a new value, not when something inside the object changes. `serverStates[id] = "online"` would change the data, but no binding would re-run. That's why `setServerState()` in `main.qml` copies the object, changes the copy and assigns it back:

```qml
const next = Object.assign({}, serverStates);   // shallow copy
next[server.id] = state;
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
    model: full.plasmoidItem.serverList  // a JS array of server objects
    delegate: ServerDelegate { … }     // one row per server
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

### 13. Reacting to another object's signals: Connections, Component.onCompleted

A handler like `onExpandedChanged` only works on the object it is written in. To react to a signal of *another* object, use `Connections`: set `target` to that object and write the handler as a function named `on<Signal>`. `main.qml` uses it to notice config changes:

```qml
Connections {
    target: Plasmoid.configuration

    function onServersChanged() {
        root.applyConfig();
    }
}
```

`Component.onCompleted` is an attached signal \[11\] every object has. It runs once, after the object and all its properties are set up: `Component.onCompleted: applyConfig()` in `main.qml` reads the config at startup, because `serversChanged` doesn't fire for the initial value.

### 14. Components declared inline

`Component { id: … ; SomeType { … } }` inside a file declares a template without creating anything \[8\]. It can be handed to a property that expects a component, and QML creates the object only when needed. `FullRepresentation.qml` uses this for the list's `header`, so the warning exists only when there is something to warn about:

```qml
header: full.plasmoidItem.configWarnings.length > 0 ? configWarning : null

Component {
    id: configWarning

    Kirigami.InlineMessage { … }
}
```

### 15. Repeating items: Repeater and Flow

A `Repeater` creates one item per model entry, like a ListView, but without scrolling and without a view of its own: the items become children of the Repeater's parent. `ServerDelegate.qml` puts it inside a `Flow`, which places its children left to right and wraps to a new line when the row is full:

```qml
Flow {
    Repeater {
        model: Model.controlFunctions(serverRow.modelData)

        delegate: FunctionControl {
            required property var modelData

            server: serverRow.modelData
            fn: modelData
            …
        }
    }
}
```

`Flow` is a positioner, not a layout: its children use their own size, not `Layout.*` properties \[10\]. If a child grows, everything after it moves, which is why `FunctionControl.qml` keeps its width constant while a spinner shows.

### 16. Declaring your own signals

A file can announce its own events with `signal name(type arg)`. Whoever creates the object handles it with `on<Name>`, as with built-in signals \[6\]. `FunctionControl.qml` declares:

```qml
signal activated(bool turnOn)
```

and emits it like a function call: `control.activated(true)`. `ServerDelegate.qml` handles it and emits its own `functionActivated(fn, turnOn)`, which `FullRepresentation.qml` handles. The click travels up through signals; the state comes down through properties. A child never needs to know who handles its signal.

### 17. Restoring a binding: Qt.binding

Clicking a `Switch` sets its `checked` property directly. That is an assignment, so it removes the binding `checked: control.fnState === "on"` \[4\]. To get it back, assign a binding object:

```qml
checked = Qt.binding(() => control.fnState === "on");
```

`FunctionControl.qml` does this in `onToggled`, so the switch shows the real state, read from the server, rather than where the user clicked it.

### 18. Pointer handlers: HoverHandler

`HoverHandler`, `TapHandler` and friends add input handling to any item without changing how it looks. `HoverHandler { id: hover }` makes `hover.hovered` true while the mouse is over its parent item. `FunctionControl.qml` needs this because a disabled button receives no hover events, so its own tooltip could never explain why it is disabled. The handler sits on the enabled wrapper `Item` instead.

### 19. Dialogs: Kirigami.PromptDialog

A dialog is a popup object declared like any other item, hidden until you call `open()`. `Kirigami.PromptDialog` is a ready-made "question with buttons": set `title`, `subtitle` and `standardButtons`, and handle `onAccepted`. `FullRepresentation.qml` declares one and fills its properties just before opening it:

```qml
function ask(server, fn, turnOn) {
    this.server = server;
    this.fn = fn;
    this.turnOn = turnOn;
    open();
}
```

`this.server` is needed because the function's parameters have the same names as the dialog's properties. `QQC2.Dialog.Ok | QQC2.Dialog.Cancel` comes from `import QtQuick.Controls as QQC2`, the standard controls that Kirigami builds on.

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

There is also an attached object `Plasmoid` (capital P) that gives access to the applet itself: `Plasmoid.icon` (from `metadata.json`) and `Plasmoid.configuration.servers` for the saved settings (see "Configuration" below).

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
| `org.kde.kirigami` | `Kirigami.` | `Icon`, `Heading`, `Theme` (colours), `Units` (sizes and spacing), `InlineMessage`, `PromptDialog` |
| `org.kde.plasma.components` | `PlasmaComponents3.` | `Label`, `ToolButton`, `Switch`, `ScrollView`, `BusyIndicator`, `ToolTip`, styled to match the panel |
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

### Configuration: main.xml and Plasmoid.configuration

`contents/config/main.xml` declares the widget's settings (KConfigXT). Each `<entry>` becomes a property of `Plasmoid.configuration`, with a matching `…Changed` signal. Plasma saves the values per widget instance in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`.

```xml
<entry name="servers" type="String">
  <default>[]</default>
</entry>
```

KConfigXT only stores simple types, so the whole server list is one JSON string. `model.js` turns it into objects; `main.qml` calls it whenever the string changes. The settings pages that write this key come in phase 3.

### metadata.json

The file Plasma reads to find the widget at all. `KPackageStructure: "Plasma/Applet"` says it's a widget, `Id` must be unique and matches the install folder, and `Icon` becomes `Plasmoid.icon`. Plasma looks for `contents/ui/main.qml` by convention.

## Part 3: One status check, start to finish

A timer starts the ping, `CommandRunner` runs it in the background, and one assignment to `serverStates` makes the dot turn green through bindings alone. Here is every step, with the file and line where it happens.

&#91;embedded content: one status check · 7 steps, then bindings\]

The top two rows are code that runs; the bottom row updates by itself because each part binds to `serverStates`.

1. **The widget starts.** Plasma creates the `PlasmoidItem` in `main.qml`. `Component.onCompleted` (`main.qml:249`) calls `applyConfig()` (`main.qml:213-247`), which reads `Plasmoid.configuration.servers` and passes it to `Model.parseServers()`. Say the config holds one server "NAS" at `192.168.1.10` with id `nas` and a ping status function; then `serverList` becomes an array with that one server. `serverStates` starts as `{}`, so every server counts as "not checked yet".
2. **The timer fires.** `Timer` has `triggeredOnStart: true`, so `onTriggered` runs right away, then every 1000 ms (`main.qml:280-295`). For each status function of each server it compares `Date.now()` with `_nextCheck[key]`, where `key` is `Model.functionKey(s, fn)`, e.g. `"nas/ping"`. Nothing is stored yet, so `|| 0` makes the check due and it calls `checkStatus(s, fn)`.
3. **checkStatus prepares the command** (`main.qml:114-134`).
   1. `primary` is true if `fn` is the server's first status function (`Model.statusFunction(server)`). Only that one decides online or offline.
   2. If a check for this function is already running (`_checking[key]`), it stops here. This prevents two pings piling up when a host is slow.
   3. It remembers the current `_configGeneration`, marks the check as running and schedules the next one: now + `interval` (30 s).
   4. `Commands.substitute("ping -c 1 -W 1 {host}", server)` turns the template into `ping -c 1 -W 1 192.168.1.10`.
   5. It calls `runner.run(command, 10, callback)`. The callback is an arrow function that will run later.
4. **CommandRunner starts it** (`CommandRunner.qml:21-29`). `Commands.withTimeout` wraps the command as `timeout -k 2 10 sh -c 'ping -c 1 -W 1 192.168.1.10'`, and `  # 1 ` is appended to make the source name unique. The callback is stored under that exact string in `_callbacks`, and `connectSource(source)` hands the command to Plasma.
5. **Nothing blocks.** `run()` returns immediately and the UI keeps responding. Plasma runs the shell command in a separate process.
6. **The result arrives** (`CommandRunner.qml:31-51`). Plasma emits `newData(sourceName, data)`. The handler looks up the callback by `sourceName`, removes it, disconnects the source and checks whether the exit code is a timeout (124 or 137). Then it calls the callback with `{ exitCode: 0, stdout, stderr, timedOut: false }`.
7. **The state changes** (`main.qml:123-133`). If the config changed while the ping ran, the generation no longer matches and the result is dropped. Otherwise the callback clears `_checking` and calls `setServerState(server, "online")`. `setServerState` copies `serverStates`, sets the entry and assigns the copy back. Because the server just came online, it also calls `refreshToggles(server)`. A further status function would call `setFunctionState(key, "ok")` instead.
8. **Bindings take over.** That single assignment is the only thing the code "does"; everything below happens because properties read `serverStates`:
   - `onlineCount` recalculates to 1, so `overallState` becomes `"all"`.
   - In the panel, `dotColor` becomes `Kirigami.Theme.positiveTextColor`, so the dot `Rectangle` turns green (`CompactRepresentation.qml:15-17, 51`).
   - In the popup, if it is open, `ServerDelegate`'s `serverState` becomes `"online"`: its dot turns green and its label shows "Online" (`ServerDelegate.qml:20, 44, 71`). Every `FunctionControl` recomputes `unavailableReason`, so a Power off button with `availableWhen: "online"` becomes enabled.
   - The tooltip's `toolTipSubText` calls `stateText(s)` and now reads "NAS: Online".
9. **30 seconds later** the timer finds the check due again, and the cycle repeats. If ping fails, the same chain runs with `"offline"` and the dots turn grey.

Two other ways into `checkStatus`: opening the popup (`onExpandedChanged` calls `refreshAll()`), and the refresh button in the popup header, which calls the same function.

A note on step 8: `toolTipSubText` and the delegate's label call a *function*, `stateText()`. QML still tracks this, because a binding records every property read while it runs, including reads inside functions it calls.

### A click, start to finish

Say "Skip alarm" is a toggle with `confirm: true`, the server is online and the switch shows on. The user clicks it.

1. **The switch reacts** (`FunctionControl.qml:110-117`). `onToggled` reads the new `checked` (false), restores the binding \[17\] and emits `activated(false)` \[16\].
2. **The signal travels up.** `ServerDelegate.qml:96` turns it into `functionActivated(fn, false)`; `FullRepresentation.qml:83` calls `full.activate(modelData, fn, false)`.
3. **Confirm first** (`FullRepresentation.qml:25-31`). `fn.confirm` is true, so `confirmDialog.ask()` fills the dialog and opens it \[19\]. Its title reads "Turn off “Skip alarm” on NAS?". If the user cancels, nothing else happens; the switch still shows the real state because of step 1.
4. **The command runs** (`main.qml:179-205`). `onAccepted` calls `runFunction(server, fn, false)`. It checks once more that the function isn't running and is available, picks `offCommand`, marks the function as running and counts up `actionsRunning`. In the popup, the switch is disabled and a spinner takes the place of its handle; in the panel, the icon dims and a spinner turns over it.
5. **The result arrives.** For an action with a `verifyCommand`, that command runs next and its result counts instead. Then `finish` clears the running mark, counts down and calls `refreshServer(server)`.
6. **Everything is read again.** `refreshServer` runs the server's status checks and `refreshToggles`, which runs every available toggle's `stateCommand` through `readToggle()`. When "Skip alarm"'s state command exits non-zero, `setFunctionState(key, "off")` updates `functionStates`, and the switch's binding shows it off.

## Part 4: Per-file notes

Each note covers what the file is for and the lines that are hard to read the first time. The numbers in brackets point to the ideas in Part 1.

### main.qml

The root of the widget and the only place that holds state. Everything else reads from it.

- **Lines 4-5:** imports the two JS helpers as `Model` and `Commands` \[12\].
- **Lines 10-15, `parsedConfig`, `serverList`, `configWarnings`:** `parsedConfig` holds the result of `Model.parseServers()`: `{ servers, warnings }`. It is assigned in `applyConfig()`, not bound to the config: Plasma re-evaluated such a binding at startup even though the config hadn't changed, which reset all state and logged every warning twice. `serverList` and `configWarnings` are plain bindings on top of it \[4\]. The name differs from the config key `servers` on purpose: one is the parsed list, the other the raw JSON string.
- **Lines 17-24, `serverStates`, `functionStates`, `runningFunctions`:** the central state, three maps that bindings read. `serverStates` is keyed by server id; the other two by `Model.functionKey()`, `"<serverId>/<functionId>"`. Always replaced, never mutated \[4\].
- **Lines 28-29, `actionsRunning` and `busy`:** counts action and toggle commands in flight; `busy` drives the panel spinner. Status checks and toggle reads deliberately don't count, or the spinner would flash every 30 s.
- **Lines 31-42, `onlineCount` and `overallState`:** two derived bindings \[4\]. `overallState` uses chained `? :` to pick `"all"`, `"some"` or `"none"`; the `serverList.length > 0` guard stops an empty list from counting as "all online".
- **Lines 44-53, bookkeeping:** mutated in place because no binding reads them. `_nextCheck` and `_checking` are per status function. `_readSeq` numbers each toggle read, so an older read that finishes late can't overwrite a newer one. `_configGeneration` counts config changes, so a command started with the old config can't overwrite state after a change. `_appliedConfig` is the last config string parsed.
- **Lines 55-72, `stateText()` and `functionName()`:** translated labels. `i18n()` is Plasma's translation function; every user-visible string goes through it.
- **Lines 74-110, setters:** `setServerState()`, `setFunctionState()` and `setRunning()` use the copy-and-assign pattern. `setServerState()` also reads the toggles when a server comes online.
- **Lines 112-134, `checkStatus()`:** see Part 3, step 3.
- **Lines 136-147, `readToggle()`:** runs `stateCommand`. Exit 0 means on, other codes off, a timeout `"unknown"`.
- **Lines 149-175, `refreshToggles()`, `refreshServer()`, `refreshAll()`:** toggles are never polled, only read on these occasions. `refreshToggles()` skips toggles that are running or unavailable, e.g. an SSH check while the server is off.
- **Lines 177-205, `runFunction()`:** see "A click, start to finish". `finish` is an arrow function stored in a `const` and passed as a callback to one of two `runner.run()` calls. It always counts down, even after a config change, so `actionsRunning` can't get stuck.
- **Lines 207-209, tooltip:** `i18nc("context", "%1: %2", a, b)` is `i18n` with a hint for translators; `%1` and `%2` are filled from the arguments.
- **Lines 211-247, `applyConfig()`:** returns early if the config string is the one already parsed. Otherwise it parses, logs each warning with `console.warn` (visible in `journalctl`), keeps only the states of servers and functions that still exist, clears the bookkeeping so every status function is checked on the next timer tick, and reads the toggles that are available.
- **Lines 249-257:** `Component.onCompleted` and `Connections` \[13\] call `applyConfig()` at startup and on every change of the `servers` key.
- **Lines 259-263, `onExpandedChanged`:** a property-change handler \[6\] that refreshes everything, toggles included, when the popup opens.
- **Lines 265-271:** the two representations, each handed a reference to `root` (Part 2).
- **Lines 273-275:** one `CommandRunner` instance, named `runner` \[8\]. It isn't visual; a `PlasmoidItem` can hold non-visual children.
- **Lines 280-295, `Timer`:** one timer ticking every second, instead of one per status function. Each function's next check time is stored in `_nextCheck`, so functions can have different intervals and a later step of phase 2 can speed one up after Wake. Inside the handler, the code writes `root.serverList` and `root.checkStatus` with the id: inside a child object, being explicit avoids confusion with the Timer's own properties.

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
- **Lines 27-32, `Kirigami.Icon`:** fills the area \[10\] and shows `Plasmoid.icon`. `active` gives the hover highlight; `containsMouse` works because of `hoverEnabled: true`. While `busy`, it fades to 40% so the spinner stands out.
- **Lines 34-40, `BusyIndicator`:** centred over the icon at 70% of its size, running while `busy` is true.
- **Lines 43-54, the dot:** a `Rectangle` with `radius` equal to half its width is a circle. Its size is 40% of the icon, at least 6 px. Anchored to the bottom-right corner. Its border uses the background colour, which gives it a thin outline against the icon. Declared last, so it is drawn on top of the spinner \[1\] and stays visible while an action runs.

### FullRepresentation.qml

The popup.

- **Line 11, `PlasmaExtras.Representation`:** a popup container with `header` and `contentItem` slots, so the heading and list get the standard Plasma look.
- **Lines 16-19, `Layout.*` sizes:** tell Plasma how big the popup may be, in grid units (multiples of the font size).
- **Line 21, `collapseMarginsHint`:**
- **Lines 23-31, `activate()`:** where every click on a function ends up. It opens the confirmation dialog if the function has `confirm` set, otherwise runs it right away. lets the list run to the popup's edges instead of sitting inside a margin.
- **Lines 33-55, header:** a `RowLayout` with a heading that takes all spare width (`Layout.fillWidth`) and a refresh button. The button has `text` even though it shows only an icon (`display: IconOnly`); the text is used by screen readers and by its own tooltip (`ToolTip.text: text`). `ToolTip.*` are attached properties \[11\].
- **Lines 57-94, list:** a `ScrollView` around a `ListView` \[9\]. `width: ListView.view.width` is an attached property that makes each row as wide as the list. `clip: true` stops rows from drawing outside the list while scrolling. `onFunctionActivated` (line 83) receives the signal from a server row \[16\]; `modelData` there is the row's server.
- **Lines 65-78, config warning:** the list's `header` is an inline `Component` \[14\], set only when `configWarnings` isn't empty. `Kirigami.InlineMessage` is hidden by default, hence `visible: true`. It doesn't list the problems, which are English developer messages; it points to the log.
- **Lines 86-92, `PlaceholderMessage`:** a child of the ListView, centred on it, shown only when `list.count === 0`, which is the case with the default config `[]`.
- **Lines 96-123, `confirmDialog`:** a `Kirigami.PromptDialog` \[19\]. `server`, `fn` and `turnOn` are set by `ask()`; `title` and `subtitle` are bindings on them, so the text is right the moment the dialog opens. The subtitle shows the exact command after placeholder substitution. `preferredWidth` keeps the dialog narrower than the popup.

### ServerDelegate.qml

One server in the list, created once per server by the `ListView`. The root id is `serverRow`, not `delegate`: inside the `Repeater` below, `delegate` is also a property name, and the id would be easy to confuse with it.

- **Line 9:** the root is a plain `Item`, a blank invisible container.
- **Line 12, `modelData`:** filled in by the ListView with this server object \[9\].
- **Lines 15-17, `functionActivated`:** a signal of its own \[16\], forwarding a click from one of its `FunctionControl`s together with the function.
- **Line 20, `serverState`:** looks up this server's state, or `""` if there is none yet.
- **Line 23, `implicitHeight`:** the row is as tall as its content plus a small margin. A ListView needs each delegate to have a height.
- **Lines 39-49, dot:** a circle in a `RowLayout`, so it uses `implicitWidth` instead of `width` \[10\]. Not checked yet means transparent fill with a 1 px border: an empty ring.
- **Lines 51-68:** name above host, the host smaller and at 70% opacity. `elide: Text.ElideRight` cuts long text with … instead of overflowing.
- **Lines 70-74:** the state label, coloured green when online.
- **Lines 79-99, functions:** a `Flow` with a `Repeater` \[15\], one `FunctionControl` per function except the first status function, which is already the dot. `Layout.leftMargin` indents the controls to line up with the name. `visible: functions.count > 0` hides the empty Flow for a server with only a status check.

### FunctionControl.qml

One function in the popup. A single file handles all three types: each child has `visible` set by `fn.type`, and an invisible child takes no space in a layout.

- **Lines 14-16, required properties:** the server, the function and the root item. `ServerDelegate.qml` sets them \[3\].
- **Line 21, `signal activated(bool turnOn)`:** the click goes out as a signal \[16\]; this file never runs anything itself.
- **Lines 23-43, derived state:** `fnState`, `running` and `unavailableReason` read the maps in `main.qml`, so the control updates when they are replaced \[4\]. `toolTipText` turns the reason into a translated sentence.
- **Lines 55-72, extra status function:** a small dot and the name, like the server's own dot. Status functions never show a spinner: they don't count as running.
- **Lines 77-98, action:** a `ToolButton` with the function's icon, disabled while unavailable or running. While running, `icon.name` becomes empty, so the button falls back to `icon.source`, a blank image (`contents/images/blank.svg`). The icon's space stays, and a `BusyIndicator` declared inside the button sits exactly there. An empty icon with no fallback would remove the space and make the button narrower, and the `Flow` would reflow \[15\].
- **Lines 100-126, toggle:** a `Switch` whose `checked` is bound to the state read from the server. `onToggled` restores that binding \[17\] before emitting the wanted state. While running, `indicator.opacity` fades the handle out and a `BusyIndicator` is centred on it. `indicator.opacity: …` sets a property of an object that belongs to the Switch, like `anchors.fill`. `visible: false` would not do here: the Switch moves its text when the indicator is invisible.
- **Lines 129-140, tooltip:** a `HoverHandler` \[18\] on the wrapper, because the disabled button itself gets no hover events. The `ToolTip` only shows when there is something to say.

### code/model.js

Pure data helpers, no QML \[12\]. Turns the `servers` config string into objects the UI can trust: every field it reads exists and has the right type.

- **`parseServers(text)`:** the entry point. Never throws; returns `{ servers, warnings }`. Empty text is a valid empty config. Text that isn't JSON, or JSON that isn't a list, gives no servers and one warning. Otherwise each entry goes through `normalizeServer()`, and entries that come back `null` are skipped.
- **`normalizeServer()` and `normalizeFunction()`:** copy the raw object with `Object.assign({}, raw)` first, so unknown fields like `tailscaleHost` survive, then overwrite the known fields with checked values. A function with an unknown `type` is skipped. Missing fields get defaults: `timeout` 10, `interval` 30, `availableWhen` `"always"`, `confirm` `false`, an icon per type. A server without a name shows its host.
- **`uniqueId()`:** a missing or duplicate id is replaced by one built from the position, like `server-2` or `nas-fn-1`. Not random, so the same config gives the same ids every time and `serverStates` survives a re-parse.
- **`asSeconds()`, `asString()`, `oneOf()`:** small type checks with a fallback. `asSeconds("30")` accepts a numeric string; `0`, negatives and `true` fall back.
- **`serializeServers(servers)`:** `JSON.stringify` for writing the config, used from phase 3 on.
- **`statusFunction(server)`:** returns the first function whose `type` is `"status"`, or `null`. The `(server && server.functions) || []` guard means a malformed server can't crash it.
- **`controlFunctions(server)`:** all functions except the first status function, for the controls in the popup.
- **`functionKey(server, fn)`:** `"<serverId>/<functionId>"`, the key for `functionStates` and `runningFunctions`.
- **`unavailableReason(fn, server, serverState)`:** `""` if the function can run now, otherwise `"needsOnline"`, `"needsOffline"` or `"unknown"` (status not checked yet). It returns codes, not sentences, because `.pragma library` files have no `i18n()`; `FunctionControl.qml` translates them.

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
- **`load-test.sh`:** runs on your machine. Builds the image if needed and starts the container with `--network none` and the package mounted read-only. `--self-test` swaps in a broken `main.qml` to prove the test catches errors. `--servers FILE` loads the widget with a test config: `plasmoidviewer` throws away a preset applet config, so the script copies the package and puts the file's content in as the default of the `servers` key in `main.xml`.

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
| Model | The data a view shows; here the `serverList` array |
| Plasmoid | A Plasma widget; the package in `package/` |
| PlasmoidItem | The root type of a Plasma 6 widget (`main.qml`) |
| Signal | An event an object announces, e.g. `triggered`, `clicked`, `newData` |
| Source | In a DataSource, one connection; for `executable`, one command string |

Good next reads, in this order:

- [Qt: First steps with QML](https://doc.qt.io/qt-6/qmlfirststeps.html): the official introduction.
- [Qt: Property binding](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html): bindings in depth, including how assignments break them.
- [KDE: Plasma widget tutorial](https://develop.kde.org/docs/plasma/widget/): writing widgets for Plasma 6, including config pages, which phase 3 will need.
- [KDE: Kirigami tutorial](https://develop.kde.org/docs/getting-started/kirigami/): the UI library behind `Kirigami.Theme`, `Units` and dialogs.
