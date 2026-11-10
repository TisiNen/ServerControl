# QML through this codebase

Nov 4, 2026 · @Tilo

## How to read this guide

This guide teaches QML using only the Server Control widget as it stands after phase 3 (on top of phase 2's config model, function types, confirmation dialog and inline feedback: the settings pages "Servers" and "General", with function templates and import and export of the whole setup), plus the Tailscale support from phase 4: 17 source files, about 3055 lines. Read Part 1 first, then follow a status check and a click through the code in Part 3; the per-file notes in Part 4 are for looking things up.

| File | Lines | Language | What it is |
| --- | --- | --- | --- |
| `package/metadata.json` | 18 | JSON | Tells Plasma this folder is a widget: name, icon, plugin ID |
| `package/contents/config/main.xml` | 40 | XML | The config schema: the `servers` JSON, the default check interval, the SSH options, the Tailscale settings |
| `package/contents/config/config.qml` | 16 | QML | The list of pages in the settings dialog |
| `package/contents/ui/main.qml` | 495 | QML | The root of the widget: config, state, timer, running all commands |
| `package/contents/ui/CommandRunner.qml` | 52 | QML | Runs shell commands in the background and calls you back |
| `package/contents/ui/CompactRepresentation.qml` | 55 | QML | The panel icon with its coloured dot and spinner |
| `package/contents/ui/FullRepresentation.qml` | 129 | QML | The popup: heading, refresh button, config warning, server list, confirmation dialog |
| `package/contents/ui/ServerDelegate.qml` | 175 | QML | One server in the popup list: dot, name, host with "via Tailscale" badge, state, its functions and their errors |
| `package/contents/ui/FunctionControl.qml` | 213 | QML | One function: status indicator, action button or toggle switch |
| `package/contents/ui/ResultIcon.qml` | 14 | QML | The ✓ or ✗ shown after a command |
| `package/contents/ui/ConfigServers.qml` | 578 | QML | Settings page "Servers": server list, server fields, function list |
| `package/contents/ui/FunctionEditor.qml` | 255 | QML | Settings form for one function, with fields per type |
| `package/contents/ui/ConfigGeneral.qml` | 270 | QML | Settings page "General": default check interval, SSH options, Tailscale settings, import and export |
| `package/contents/ui/CommandField.qml` | 128 | QML | Settings field for one command, with LAN and Tailscale preview and placeholder warnings |
| `package/contents/ui/code/model.js` | 447 | JavaScript | Parses and validates the `servers` config JSON; availability, Tailscale and polling rules; editing helpers; import and export |
| `package/contents/ui/code/templates.js` | 75 | JavaScript | The preconfigured functions for "Add Function" |
| `package/contents/ui/code/commands.js` | 110 | JavaScript | Placeholder substitution, shell quoting, timeout wrapping, error lines, placeholder checks |

If you know JavaScript, you already know half of QML: everything inside `function`, `{ … }` property expressions and `on…` handlers is ordinary JavaScript. The new part is the declarative layer around it, which Part 1 covers.

## Part 1: QML basics

A QML file describes a tree of objects and how their properties depend on each other; the engine keeps those dependencies up to date for you. The twenty-two ideas below explain almost every line in this repo.

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
- **`GridLayout`** places its children in rows and columns, filling `columns` cells per row in order. `CommandField.qml` uses one with two columns for its preview, so "LAN:" and "Tailscale:" form one column and the commands start at the same x. An invisible child takes no cell: when the prefixes are hidden, the command label is the only child left and takes the first cell.

`implicitWidth`/`implicitHeight` is the size an item would like to have; layouts use it when nothing else is set.

### 11. Attached properties

A property written `TypeName.property` belongs to another type but is set on this object: `Layout.fillWidth`, `PlasmaComponents3.ToolTip.text`, `ListView.view.width`. Read it as "the Layout settings for this object" or "the tooltip of this button".

### 12. JavaScript files

`.pragma library` at the top of a JS file means it is loaded once and shared by every QML file that imports it. Such a file has no access to QML objects, only to what you pass into its functions. That keeps `model.js` and `commands.js` as pure helpers.

A JS file can use another one with `.import`, the JS version of a QML `import`. `templates.js` starts with:

```js
.pragma library
.import "model.js" as Model
.import "commands.js" as Commands
```

and then calls `Model.normalizeFunction()` and `Commands.shellQuote()` like a QML file would.

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

`Flow` is a positioner, not a layout: its children use their own size, not `Layout.*` properties \[10\]. If a child grows, everything after it moves, which is why `FunctionControl.qml` keeps its width constant while a spinner shows. A `Flow` also aligns its children at the top, so a button, a switch and a label, each with a different height, would sit at different heights. The `Flow` therefore computes `rowHeight`, the largest `contentHeight` of its controls, and every control takes that height and centres its content in it.

### 16. Declaring your own signals

A file can announce its own events with `signal name(type arg)`. Whoever creates the object handles it with `on<Name>`, as with built-in signals \[6\]. `FunctionControl.qml` declares:

```qml
signal activated(bool turnOn)
```

and emits it like a function call: `control.activated(true)`. `ServerDelegate.qml` handles it and emits its own `functionActivated(fn, turnOn)`, which `FullRepresentation.qml` handles. The click travels up through signals; the state comes down through properties. A child never needs to know who handles its signal.

### 17. Restoring a binding: Qt.binding

Clicking a `Switch` sets its `checked` property from inside the control. The binding `checked: control.fnState === "on"` \[4\] survives that: only an assignment in JavaScript removes a binding. But a binding only re-evaluates when something it reads changes, and the click doesn't change `fnState`. So the switch would stay where the user clicked it, not where the real state is. Assigning a binding object re-evaluates it right away:

```qml
checked = Qt.binding(() => control.fnState === "on");
```

`FunctionControl.qml` does this in `onToggled`, so the switch shows the real state, read from the server, rather than where the user clicked it. The settings controls don't need it: every click there changes the data they are bound to, so their bindings re-evaluate on their own (see the "Default" check box next to the check interval in `FunctionEditor.qml`).

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

### 20. Forms: Kirigami.FormLayout

`Kirigami.FormLayout` lays out a settings form the KDE way: labels right-aligned in a left column, fields in a right column. A field doesn't get a separate `Label`; it names its own label with the attached property `Kirigami.FormData.label` \[11\]. A `Kirigami.Separator` with `FormData.isSection: true` starts a titled section. From `ConfigServers.qml`:

```qml
Kirigami.FormLayout {
    QQC2.TextField {
        Kirigami.FormData.label: i18nc("@label:textbox", "Host:")
        text: page.currentServer ? page.currentServer.host : ""
        onTextEdited: page.setServerField("host", text.trim())
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18nc("@title:group", "Functions")
    }
    …
}
```

When the window is too narrow (`wideMode` false), the labels move above the fields. Two forms on one page line up when one lists the other in `twinFormLayouts`, as the function editor does with the server form. One trap: a `Label` with `wrapMode` reports its *unwrapped* text width as `implicitWidth`, which can push the whole form out of wide mode. The settings files give such labels a small `Layout.preferredWidth` together with `Layout.fillWidth: true`.

A second trap is the height of a `ScrollView`. Its implicit height is the height of everything inside it, and the form sizes it by that, even with `Layout.preferredHeight` set. The import text area in `ConfigGeneral.qml` then grew over the buttons below it. Setting the height itself fixes it:

```qml
QQC2.ScrollView {
    implicitHeight: Kirigami.Units.gridUnit * 14
    clip: true

    QQC2.TextArea { id: jsonArea; … }
}
```

`clip: true` cuts off whatever is scrolled out of view; without it, the text would still draw outside the box.

`onTextEdited` fires only when the user types, not when `text` changes through its binding. That keeps the binding \[4\] in place: the page writes the new value into its data, and the binding reads the same value back.

### 21. Small types inside a file: `component`

`component Name: BaseType { … }` declares a reusable type inside a file, without a file of its own \[8\]. It must sit directly in the root object, and can be used anywhere in that file. `ConfigServers.qml` declares the small icon-only buttons of its lists once:

```qml
component ListToolButton: QQC2.ToolButton {
    display: QQC2.AbstractButton.IconOnly
    QQC2.ToolTip.text: text
    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
}
```

and then writes `ListToolButton { icon.name: "go-up"; … }` six times. Compare `Component { … }` \[14\], which declares a template *object*, not a type.

### 22. Dialogs with your own content: Kirigami.Dialog

`Kirigami.PromptDialog` \[19\] shows a text. When a dialog needs input fields, `Kirigami.Dialog` takes any content as its child. The flag toggle dialog in `ConfigServers.qml` holds a label and a small form:

```qml
Kirigami.Dialog {
    id: flagDialog

    readonly property bool valid: flagPath.text.trim() !== ""

    title: i18nc("@title:window", "Add Flag Toggle")
    standardButtons: QQC2.Dialog.Cancel
    customFooterActions: [
        Kirigami.Action {
            text: i18nc("@action:button", "Add")
            enabled: flagDialog.valid
            onTriggered: flagDialog.add()
        }
    ]

    ColumnLayout {
        QQC2.Label { … }
        Kirigami.FormLayout { QQC2.TextField { id: flagPath; … } … }
    }
}
```

A standard OK button can't be disabled with a binding. A `Kirigami.Action` in `customFooterActions` can, so "Add" stays disabled while the path is empty. Pressing Enter in a field (`onAccepted`) calls the same `add()`.

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

KConfigXT only stores simple types, so the whole server list is one JSON string. `model.js` turns it into objects; `main.qml` calls it whenever the string changes. The settings page writes it (next section).

Two more entries hold the General settings: `defaultInterval` (an `Int` with `<min>1</min>`) and `sshOptions` (a `String`). `main.qml` reads them where they are used, as `Plasmoid.configuration.defaultInterval` and `Plasmoid.configuration.sshOptions`, and its `Connections` handlers `onDefaultIntervalChanged` and `onSshOptionsChanged` reschedule all status checks when they change.

Two more entries belong to Tailscale: `tailscaleEnabled` (a `Bool`, default `false`) turns the support on, and `tailscaleCommand` (a `String`) is the command that tells whether Tailscale is active. The command's default contains quotes and a `|`; inside an XML element that needs no escaping, only `<` and `&` would. `onTailscaleEnabledChanged` and `onTailscaleCommandChanged` both call `restartTailscaleCheck()`, which drops a check still running with the old settings and reschedules everything.

### Settings pages: config.qml, KCM.SimpleKCM and cfg_ properties

`contents/config/config.qml` lists the pages of the settings dialog that "Configure Server Control…" opens:

```qml
ConfigModel {
    ConfigCategory {
        name: i18n("Servers")
        icon: "network-server-symbolic"
        source: "ConfigServers.qml"
    }
}
```

`icon` is a name from the icon theme. The dialog's sidebar draws it large, and in Breeze, `network-server` is a "places" icon, which from 32 px up is drawn as a folder. The `-symbolic` variant exists only up to 24 px, so the dialog scales that one up instead: the same plain server rack the server list shows, drawn in the text colour.

`source` is a file in `contents/ui/`. Its root is a `KCM.SimpleKCM` (`import org.kde.kcmutils as KCM`), a scrollable page. The page doesn't touch `Plasmoid.configuration`. Instead it declares a property `cfg_<key>` for each config key, and Plasma does the rest:

```qml
property string cfg_servers
property string cfg_serversDefault
```

1. When the page opens, Plasma sets `cfg_servers` to the saved value and `cfg_serversDefault` to the default from `main.xml`. It does this for *every* key on *every* page, so `ConfigGeneral.qml` also declares `cfg_servers`, even though it doesn't edit it: an undeclared key logs a warning.
2. When the page assigns `cfg_servers`, Plasma notices the change and enables Apply.
3. On Apply or OK, Plasma writes `cfg_servers` to the config. `main.qml` gets `serversChanged` and re-parses.
4. The Defaults button sets `cfg_servers` back to `cfg_serversDefault`. Declaring `cfg_serversDefault` also avoids a warning in the log.

Cancel throws the page away without saving, so the page can change `cfg_servers` freely while the user edits. The dialog shows one page at a time and saves only that page's `cfg_` values; switching pages with unsaved changes asks to apply or discard them first. So two pages that both declare `cfg_servers` can't overwrite each other's edits.

A page that only edits simple values can bind its controls straight to the `cfg_` properties, as `ConfigGeneral.qml` does:

```qml
QQC2.SpinBox {
    value: page.cfg_defaultInterval
    onValueModified: page.cfg_defaultInterval = value
}
```

### metadata.json

The file Plasma reads to find the widget at all. `KPackageStructure: "Plasma/Applet"` says it's a widget, `Id` must be unique and matches the install folder, and `Icon` becomes `Plasmoid.icon`. Plasma looks for `contents/ui/main.qml` by convention.

## Part 3: One status check, start to finish

A timer starts the ping, `CommandRunner` runs it in the background, and one assignment to `serverStates` makes the dot turn green through bindings alone. Here is every step, with the file and line where it happens.

&#91;embedded content: one status check · 7 steps, then bindings\]

The top two rows are code that runs; the bottom row updates by itself because each part binds to `serverStates`.

1. **The widget starts.** Plasma creates the `PlasmoidItem` in `main.qml`. `Component.onCompleted` (`main.qml:429`) calls `applyConfig()` (`main.qml:389-427`), which reads `Plasmoid.configuration.servers` and passes it to `Model.parseServers()`. Say the config holds one server "NAS" at `192.168.1.10` with id `nas` and a ping status function; then `serverList` becomes an array with that one server. `serverStates` starts as `{}`, so every server counts as "not checked yet".
2. **The timer fires.** `Timer` has `triggeredOnStart: true`, so `onTriggered` runs right away, then every 1000 ms (`main.qml:475-494`). For each status function of each server it compares `Date.now()` with `_nextCheck[key]`, where `key` is `Model.functionKey(s, fn)`, e.g. `"nas/ping"`. Nothing is stored yet, so `|| 0` makes the check due and it calls `checkStatus(s, fn)`.
3. **checkStatus prepares the command** (`main.qml:200-230`).
   1. If a check for this function is already running (`_checking[key]`), it stops here. This prevents two pings piling up when a host is slow.
   2. It calls `checkTailscale()`, which runs the Tailscale check at most once every 5 s (see the notes on `main.qml` in Part 4).
   3. It schedules the next check: now + the function's `interval`, or the default check interval from the General settings (30 s) if it has none, or 5 s while the server is polled faster after Wake (`Model.checkInterval()`). If the server can't be reached right now (Tailscale is active and it has no Tailscale host), it stops here.
   4. `primary` is true if `fn` is the server's first status function (`Model.statusFunction(server)`). Only that one decides online or offline. It remembers the current `_configGeneration` and `_networkGeneration` and marks the check as running.
   5. `commandFor("ping -c 1 -W 1 {host}", server)` turns the template into `ping -c 1 -W 1 192.168.1.10`. It calls `Commands.substitute()` with the SSH options from the General settings, which `{ssh}` would need, and whether the server is reached over Tailscale; then `{host}` would be its Tailscale host.
   6. It calls `runner.run(command, 10, callback)`. The callback is an arrow function that will run later.
4. **CommandRunner starts it** (`CommandRunner.qml:21-29`). `Commands.withTimeout` wraps the command as `timeout -k 2 10 sh -c 'ping -c 1 -W 1 192.168.1.10'`, and `  # 1 ` is appended to make the source name unique. The callback is stored under that exact string in `_callbacks`, and `connectSource(source)` hands the command to Plasma.
5. **Nothing blocks.** `run()` returns immediately and the UI keeps responding. Plasma runs the shell command in a separate process.
6. **The result arrives** (`CommandRunner.qml:31-51`). Plasma emits `newData(sourceName, data)`. The handler looks up the callback by `sourceName`, removes it, disconnects the source and checks whether the exit code is a timeout (124 or 137). Then it calls the callback with `{ exitCode: 0, stdout, stderr, timedOut: false }`.
7. **The state changes** (`main.qml:219-229`). If the config changed while the ping ran, or Tailscale went on or off, a generation no longer matches and the result is dropped. Otherwise the callback clears `_checking` and calls `setServerState(server, "online")`. `setServerState` copies `serverStates`, sets the entry and assigns the copy back. Because the server just came online, it also calls `refreshToggles(server)`. A further status function would call `setFunctionState(key, "ok")` instead.
8. **Bindings take over.** That single assignment is the only thing the code "does"; everything below happens because properties read `serverStates`:
   - `onlineCount` recalculates to 1, so `overallState` becomes `"all"`.
   - In the panel, `dotColor` becomes `Kirigami.Theme.positiveTextColor`, so the dot `Rectangle` turns green (`CompactRepresentation.qml:15-17, 51`).
   - In the popup, if it is open, `ServerDelegate`'s `serverState` becomes `"online"`: its dot turns green and its label shows "Online" (`ServerDelegate.qml:20, 47, 105`). Every `FunctionControl` recomputes `unavailableReason`, so a Power off button with `availableWhen: "online"` becomes enabled.
   - The tooltip's `toolTipSubText` calls `stateText(s)` and now reads "NAS: Online".
9. **30 seconds later** the timer finds the check due again, and the cycle repeats. If ping fails, the same chain runs with `"offline"` and the dots turn grey.

Two other ways into `checkStatus`: opening the popup (`onExpandedChanged` calls `refreshAll()`), and the refresh button in the popup header, which calls the same function.

A note on step 8: `toolTipSubText` and the delegate's label call a *function*, `stateText()`. QML still tracks this, because a binding records every property read while it runs, including reads inside functions it calls.

### A click, start to finish

Say "Skip alarm" is a toggle with `confirm: true`, the server is online and the switch shows on. The user clicks it.

1. **The switch reacts** (`FunctionControl.qml:157-172`). `onToggled` reads the new `checked` (false), restores the binding \[17\] and emits `activated(false)` \[16\].
2. **The signal travels up.** `ServerDelegate.qml:144` turns it into `functionActivated(fn, false)`; `FullRepresentation.qml:81` calls `full.activate(modelData, fn, false)`.
3. **Confirm first** (`FullRepresentation.qml:23-29`). `fn.confirm` is true, so `confirmDialog.ask()` fills the dialog and opens it \[19\]. Its title reads "Turn off “Skip alarm” on NAS?". If the user cancels, nothing else happens; the switch still shows the real state because of step 1.
4. **The command runs** (`main.qml:294-328`). `onAccepted` calls `runFunction(server, fn, false)`. It checks once more that the function isn't running and is available, picks `offCommand`, marks the function as running and counts up `actionsRunning`. In the popup, the switch is disabled and a spinner takes the place of its handle; in the panel, the icon dims and a spinner turns over it.
5. **The result arrives.** For an action with a `verifyCommand`, that command runs next and its result counts instead. Then `finish` clears the running mark and counts down. It stores the result with `setResult()`, which shows a ✗ where the handle was and the error under the server's controls, if the command failed. For an action that only runs online or only offline, such as Wake, it also starts faster polling with `startFastPoll()`. Finally it calls `refreshServer(server)`.
6. **The result goes away.** The timer calls `expireResults()` every second. After 3 s (✓) or 10 s (✗) it removes the result, and the icon and the error line disappear. Until then the control stays enabled, even if the function has just become unavailable (see `looksEnabled` in `FunctionControl.qml`).
7. **Everything is read again.** `refreshServer` runs the server's status checks and `refreshToggles`, which runs every available toggle's `stateCommand` through `readToggle()`. When "Skip alarm"'s state command exits non-zero, `setFunctionState(key, "off")` updates `functionStates`, and the switch's binding shows it off.

## Part 4: Per-file notes

Each note covers what the file is for and the lines that are hard to read the first time. The numbers in brackets point to the ideas in Part 1.

### main.qml

The root of the widget and the only place that holds state. Everything else reads from it.

- **Lines 4-5:** imports the two JS helpers as `Model` and `Commands` \[12\].
- **Lines 10-15, `parsedConfig`, `serverList`, `configWarnings`:** `parsedConfig` holds the result of `Model.parseServers()`: `{ servers, warnings }`. It is assigned in `applyConfig()`, not bound to the config: Plasma re-evaluated such a binding at startup even though the config hadn't changed, which reset all state and logged every warning twice. `serverList` and `configWarnings` are plain bindings on top of it \[4\]. The name differs from the config key `servers` on purpose: one is the parsed list, the other the raw JSON string.
- **Lines 17-28, `serverStates`, `functionStates`, `runningFunctions`, `functionResults`:** the central state, four maps that bindings read. `serverStates` is keyed by server id; the others by `Model.functionKey()`, `"<serverId>/<functionId>"`. Always replaced, never mutated \[4\].
- **Lines 30-33, `tailscaleActive`:** whether the last Tailscale check succeeded. Bindings in the popup read it, so the badges, the "Not reachable" states and the disabled Wake buttons update when it changes.
- **Lines 36-38, `actionsRunning` and `busy`:** counts action and toggle commands in flight; `busy` drives the panel spinner. Status checks and toggle reads deliberately don't count, or the spinner would flash every 30 s.
- **Lines 40-51, `onlineCount` and `overallState`:** two derived bindings \[4\]. `overallState` uses chained `? :` to pick `"all"`, `"some"` or `"none"`; the `serverList.length > 0` guard stops an empty list from counting as "all online".
- **Lines 53-72, bookkeeping:** mutated in place because no binding reads them. `_nextCheck` and `_checking` are per status function. `_readSeq` numbers each toggle read, so an older read that finishes late can't overwrite a newer one. `_fastPollUntil` holds, per server, when its faster polling ends. `_configGeneration` counts config changes, so a command started with the old config can't overwrite state after a change. `_appliedConfig` is the last config string parsed. `_networkGeneration` does the same as `_configGeneration` when Tailscale goes on or off. The three `_tailscale…` properties belong to `checkTailscale()`.
- **Lines 74-102, `stateText()`, `commandFor()` and `functionName()`:** `stateText()` and `functionName()` are translated labels; `stateText()` says "Not reachable" for a server `Model.reachable()` rules out. `i18n()` is Plasma's translation function; every user-visible string goes through it. `commandFor()` fills in a command's placeholders with the SSH options from the General settings, and with the Tailscale host when `Model.viaTailscale()` says so; every command the widget runs, and the one the confirmation dialog shows, goes through it.
- **Lines 104-144, setters:** `setServerState()`, `setFunctionState()` and `setRunning()` use the copy-and-assign pattern. `setServerState()` also reads the toggles when a server comes online. `unavailableReason()` is a short form of `Model.unavailableReason()` with this widget's state filled in.
- **Lines 146-198, `checkTailscale()`, `restartTailscaleCheck()` and `setTailscaleActive()`:** the Tailscale check runs the configured command, without placeholders. It has no timer of its own: `checkStatus()` and `refreshAll()` call it, and it returns early while a check is in flight or the last one started less than 5 s ago, because the status checks of all servers usually come in the same tick. `_tailscaleSeq` drops the result of a check started with older settings; `restartTailscaleCheck()` counts it up when a Tailscale setting changes. While `tailscaleEnabled` is off, or the command is empty, nothing runs and Tailscale counts as inactive. When the result differs from `tailscaleActive`, `setTailscaleActive()` forgets every server and function state, since it was read over the other network, and bumps `_networkGeneration`; clearing `_nextCheck` makes the timer check everything on its next tick.
- **Lines 200-230, `checkStatus()`:** see Part 3, step 3.
- **Lines 232-249, `readToggle()`:** runs `stateCommand`. Exit 0 means on, other codes off, a timeout `"unknown"`. The optional `done` callback runs whenever the command finishes, even when the result is dropped, so whoever passed it can always clean up.
- **Lines 251-262, `retryToggle()`:** what a click on a toggle in the `"unknown"` state does: it reads the state again instead of switching, since without the current state the click has no clear meaning. It marks the toggle as running for the read, so the switch shows the spinner, and passes `done` to clear the mark. It doesn't count up `actionsRunning`: a read changes nothing on the server.
- **Lines 264-292, `refreshToggles()`, `refreshServer()`, `refreshAll()`:** toggles are never polled, only read on these occasions. `refreshToggles()` skips toggles that are running or unavailable, e.g. an SSH check while the server is off, or any toggle of a server that isn't reachable. `refreshAll()` also runs the Tailscale check, for setups without any status check.
- **Lines 294-328, `runFunction()`:** see "A click, start to finish". `finish` is an arrow function stored in a `const` and passed as a callback to one of two `runner.run()` calls. The verify call wraps it in another arrow function, `verifyResult => finish(verifyResult, true)`, to pass the extra argument. It always counts down, even after a config change, so `actionsRunning` can't get stuck.
- **Lines 330-345, `setResult()`:** stores `ok`, the error line, the full stderr and the time the result expires (`expiresAt`). It is replaced by the next result of the same function.
- **Lines 347-360, `expireResults()`:** called by the timer. Removes every result whose `expiresAt` has passed. `next` stays `null` until something changes, so most ticks assign nothing and no binding re-evaluates.
- **Lines 362-369, `resultText()`:** the error line, or a translated fallback with the exit code when the command wrote nothing to stderr.
- **Lines 371-383, `startFastPoll()`:** sets the end of the fast period and moves each status check's next run forward. `checkStatus()` then keeps using the short interval until the period ends.
- **Lines 385-387, tooltip:** `i18nc("context", "%1: %2", a, b)` is `i18n` with a hint for translators; `%1` and `%2` are filled from the arguments.
- **Lines 389-427, `applyConfig()`:** returns early if the config string is the one already parsed. Otherwise it parses, logs each warning with `console.warn` (visible in `journalctl`), keeps only the states of servers and functions that still exist, drops all inline results, clears the bookkeeping so every status function is checked on the next timer tick, and reads the toggles that are available.
- **Lines 429-455:** `Component.onCompleted` and `Connections` \[13\] call `applyConfig()` at startup and on every change of the `servers` key. When the default interval, the SSH options or a Tailscale setting change, the handlers clear `_nextCheck`, so the timer runs every status check on its next tick with the new settings instead of waiting for checks scheduled with the old interval.
- **Lines 457-461, `onExpandedChanged`:** a property-change handler \[6\] that refreshes everything, toggles included, when the popup opens.
- **Lines 463-469:** the two representations, each handed a reference to `root` (Part 2).
- **Lines 471-473:** one `CommandRunner` instance, named `runner` \[8\]. It isn't visual; a `PlasmoidItem` can hold non-visual children.
- **Lines 475-494, `Timer`:** one timer ticking every second, instead of one per status function. Each function's next check time is stored in `_nextCheck`, so functions can have different intervals and can run faster after Wake. Each tick also calls `expireResults()`. Inside the handler, the code writes `root.serverList` and `root.checkStatus` with the id: inside a child object, being explicit avoids confusion with the Timer's own properties.

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

- **Line 9, `PlasmaExtras.Representation`:** a popup container with `header` and `contentItem` slots, so the heading and list get the standard Plasma look.
- **Lines 14-17, `Layout.*` sizes:** tell Plasma how big the popup may be, in grid units (multiples of the font size).
- **Line 19, `collapseMarginsHint`:** lets the list run to the popup's edges instead of sitting inside a margin.
- **Lines 21-29, `activate()`:** where every click on a function ends up. It opens the confirmation dialog if the function has `confirm` set, otherwise runs it right away.
- **Lines 31-53, header:** a `RowLayout` with a heading that takes all spare width (`Layout.fillWidth`) and a refresh button. The button has `text` even though it shows only an icon (`display: IconOnly`); the text is used by screen readers and by its own tooltip (`ToolTip.text: text`). `ToolTip.*` are attached properties \[11\].
- **Lines 55-99, list:** a `ScrollView` around a `ListView` \[9\]. `width: ListView.view.width` is an attached property that makes each row as wide as the list. `clip: true` stops rows from drawing outside the list while scrolling. `onFunctionActivated` (line 83) receives the signal from a server row \[16\]; `modelData` there is the row's server.
- **Lines 63-76, config warning:** the list's `header` is an inline `Component` \[14\], set only when `configWarnings` isn't empty. `Kirigami.InlineMessage` is hidden by default, hence `visible: true`. It doesn't list the problems, which are English developer messages; it points to the log.
- **Lines 84-97, `PlaceholderMessage`:** a child of the ListView, centred on it, shown only when `list.count === 0`, which is the case with the default config `[]`. Its `helpfulAction` is a button under the message. It triggers Plasma's own "configure" action (`Plasmoid.internalAction("configure")`), the same one as "Configure…" in the context menu, which opens the settings dialog.
- **Lines 101-128, `confirmDialog`:** a `Kirigami.PromptDialog` \[19\]. `server`, `fn` and `turnOn` are set by `ask()`; `title` and `subtitle` are bindings on them, so the text is right the moment the dialog opens. The subtitle shows the exact command after placeholder substitution. `preferredWidth` keeps the dialog narrower than the popup.

### ServerDelegate.qml

One server in the list, created once per server by the `ListView`. The root id is `serverRow`, not `delegate`: inside the `Repeater` below, `delegate` is also a property name, and the id would be easy to confuse with it.

- **Line 9:** the root is a plain `Item`, a blank invisible container.
- **Line 12, `modelData`:** filled in by the ListView with this server object \[9\].
- **Lines 15-17, `functionActivated`:** a signal of its own \[16\], forwarding a click from one of its `FunctionControl`s together with the function.
- **Lines 19-23, `serverState`, `viaTailscale`, `reachable`:** this server's state, or `""` if there is none yet, and whether it is reached over Tailscale or not at all right now (`Model.viaTailscale()`, `Model.reachable()`).
- **Line 26, `implicitHeight`:** the row is as tall as its content plus a small margin. A ListView needs each delegate to have a height.
- **Lines 42-52, dot:** a circle in a `RowLayout`, so it uses `implicitWidth` instead of `width` \[10\]. Not checked yet means transparent fill with a 1 px border: an empty ring. A server that isn't reachable gets the grey of an offline one.
- **Lines 54-102:** name above host, the host smaller and at 70% opacity. `elide: Text.ElideRight` cuts long text with … instead of overflowing. Over Tailscale, the host line shows the Tailscale host and a badge: a `Rectangle` with `radius: height / 2` (round ends) around a small `Label`, its colour the theme's highlight colour at 25% opacity through `Qt.rgba()`. The badge should sit right after the host, not at the far end, so while it shows, an empty `Item` with `Layout.fillWidth` takes the rest of the row instead of the host label.
- **Lines 104-108:** the state label, coloured green when online.
- **Lines 111-147, functions:** a `Flow` with a `Repeater` \[15\], one `FunctionControl` per function except the first status function, which is already the dot. `Layout.leftMargin` indents the controls to line up with the name. `visible: functions.count > 0` hides the empty Flow for a server with only a status check. `rowHeight` loops over the Repeater's items with `itemAt(i)` and takes the largest `contentHeight`; each control reads it through `parent.rowHeight`, so all controls of a server line up \[15\].
- **Lines 149-173, error lines:** a second `Repeater` over the same functions, this time directly in the `ColumnLayout`, so each `Label` becomes a row of it. A label is visible only while its function's last command failed; an invisible item takes no space in a layout \[10\], so normally the rows add nothing. `maximumLineCount: 2` with `elide` keeps a long error short; the tooltip of the control shows all of it. It disappears together with the ✗. Unlike the ✓/✗, an error line does add height while it shows, so the rows below move down a little.

### FunctionControl.qml

One function in the popup. A single file handles all three types: each child has `visible` set by `fn.type`, and an invisible child takes no space in a layout.

- **Lines 14-16, required properties:** the server, the function and the root item. `ServerDelegate.qml` sets them \[3\].
- **Line 21, `signal activated(bool turnOn)`:** the click goes out as a signal \[16\]; this file never runs anything itself.
- **Lines 23-66, derived state:** `fnState`, `running`, `unavailableReason` and `result` read the maps in `main.qml` (and `unavailableReason` also `tailscaleActive`), so the control updates when they are replaced \[4\]. `showResult` decides whether a ✓ or ✗ shows: actions show both, toggles only ✗, because after a successful toggle the switch moving is feedback enough. `looksEnabled` keeps the control enabled while its result shows, even if the function just became unavailable: Wake brings the server online during its ✓, and a button greying out right then would look as if Wake had failed. Clicks in that moment are ignored, see below. `stateUnknown` is true for a toggle whose state command timed out, but only while it could otherwise be clicked: a disabled toggle looks disabled, whatever its last state. `toolTipText` turns the reason into a translated sentence, or shows the full error output after a failure.
- **Lines 68-82, height:** `contentHeight` is what the content needs; `rowHeight` is set by `ServerDelegate.qml` to the tallest control's. The control takes the larger of the two, and the `RowLayout` is anchored to the vertical centre instead of filling the control, so a short switch or label sits in the middle of a tall button's height \[15\].
- **Lines 84-106, extra status function:** a small dot and the name, like the server's own dot. The name uses the normal font, like the button and switch texts. Buttons and switches have padding of their own; the dot and label don't, so `Layout.leftMargin` on the dot and `Layout.rightMargin` on the label add space around them. A `RowLayout` counts such margins in its `implicitWidth`, so the `Flow` leaves room for them. Status functions never show a spinner: they don't count as running.
- **Lines 108-144, action:** a `ToolButton` with the function's icon, disabled unless `looksEnabled`. `onClicked` emits `activated` only if the function is really available. While running or showing a result, `icon.name` becomes empty, so the button falls back to `icon.source`, a blank image (`contents/images/blank.svg`). The icon's space stays, and a `BusyIndicator` or a `ResultIcon` declared inside the button sits exactly there. An empty icon with no fallback would remove the space and make the button narrower, and the `Flow` would reflow \[15\].
- **Lines 146-198, toggle:** a `Switch` whose `checked` is bound to the state read from the server. `onToggled` restores that binding \[17\], stops if the function only looks enabled, and then emits the wanted state or, if the state is unknown, calls `plasmoidItem.retryToggle()` directly: a read needs no confirmation, so it skips the route through `ServerDelegate` and `FullRepresentation`. While the state is unknown, the handle is faded out like for the spinner and a `Kirigami.Icon` with `dialog-warning` takes its place, so the switch looks neither working nor disabled. While running, `indicator.opacity` fades the handle out and a `BusyIndicator` is centred on it; after a failure, a `ResultIcon` with ✗. `indicator.opacity: …` sets a property of an object that belongs to the Switch, like `anchors.fill`. `visible: false` would not do here: the Switch moves its text when the indicator is invisible.
- **Lines 201-212, tooltip:** a `HoverHandler` \[18\] on the wrapper, because the disabled button itself gets no hover events. The `ToolTip` only shows when there is something to say.

### ResultIcon.qml

The ✓ or ✗ after a command. A file of its own because the button and the switch both use it \[8\].

- **Line 6:** the root is a `Kirigami.Icon`, so `ResultIcon` is an icon with one extra property, `result`. The caller passes `null` when nothing should show.
- **Lines 10-13:** `checkmark` and `dialog-close` are monochrome theme icons. `isMask: true` paints them in `color`, here the theme's positive and negative colours, so they are a green tick and a red cross in any colour scheme.

### config/config.qml

The settings dialog's page list (Part 2, "Settings pages"): "Servers" first, then "General".

### ConfigGeneral.qml

The "General" settings page: settings that apply to all servers, and import and export of the whole setup. Every control is bound to a `cfg_` property and writes it directly (Part 2). There is no copy to manage, unlike `ConfigServers.qml`.

- **Default check interval:** used by status functions without their own `interval`.
- **SSH options:** what `{ssh}` puts between `ssh` and `user@host`. Below the field, `Commands.sshCommand()` shows the result for a made-up server. A warning appears when the options lack `BatchMode=yes` (`Commands.hasBatchMode()`): without it, ssh asks for a password that nobody can type in, and the command just waits for its timeout.
- **Tailscale:** a `CheckBox` bound to `cfg_tailscaleEnabled`, like the other controls. The rows below it have `visible: page.cfg_tailscaleEnabled`, so they appear when it is checked; an invisible row takes no space in the `FormLayout`, label included.
- **Tailscale check:** the command that tells whether Tailscale is active. The field and a `ToolButton` sit in a `RowLayout`, which is one field of the `FormLayout` \[20\] with the label on the row. The button sets `cfg_tailscaleCommand` back to `cfg_tailscaleCommandDefault`, the default from `main.xml` that Plasma passes in, and is disabled while they are equal.
- **`cfg_servers`, `cfg_serversDefault`:** only written by an import. Declaring every key also avoids log warnings (Part 2).
- **Lines 33-42, `showCurrentSetup()`:** fills the text area with `Model.exportSetup()`: the servers as parsed from `cfg_servers`, and the four settings. `Component.onCompleted` (line 87) calls it, so the current setup shows when the page opens. It reads the `cfg_` properties, not the saved config, so after an import it shows what Apply would save.
- **Lines 44-85, `importText()`:** `Model.parseSetup()` does the checking and returns an error code or the result. On an error, only the message changes. Otherwise it assigns `cfg_servers` and each general setting the text contained. The spin box, check box and text fields above are bound to those properties \[4\], so they show the imported values at once, and Apply enables. The message is built from several translated sentences, each added only when it applies.
- **Lines 213-228, text area:** a `TextArea` inside a `ScrollView` with a fixed height (Part 1, idea 20).
- **Lines 230-260, buttons:** "Copy" has no clipboard API to call; QML has none. Instead it selects all text in the text area, calls the text area's own `copy()`, and deselects again. "Copy" and "Import" are disabled while the text area is empty.
- **Lines 262-268, message:** a `Kirigami.InlineMessage`, green after an import and red after an error, bound to `importMessage` and `importFailed`.

### ConfigServers.qml

The "Servers" settings page. It edits a parsed copy of the config and writes it back as JSON to `cfg_servers` on every change (Part 2).

- **Lines 19-30, `cfg_` properties:** set by Plasma; see Part 2. The page edits `cfg_servers` and only reads `cfg_defaultInterval` and `cfg_sshOptions`, to pass them to the function editor. `cfg_tailscaleEnabled` shows or hides the Tailscale host field and is passed on to the function editor; `cfg_tailscaleCommand` is declared only to avoid the warning.
- **Lines 32-40, page state:** `servers` is the list being edited, parsed with the same `Model.parseServers()` as the widget, so the page sees exactly what the popup shows. The selection is two indexes; `currentServer` and `currentFunction` are bindings on them \[4\], `null` when nothing is selected.
- **Lines 44-60, `load()` and `_written`:** `load()` parses `cfg_servers`, at start and whenever `cfg_servers` changes from *outside*, e.g. through the Defaults button. The page's own writes change `cfg_servers` too; `_written` holds the last JSON the page wrote, so `onCfg_serversChanged` can tell the two apart.
- **Lines 62-68, `edit(change)`:** every change goes through here. It copies the list (`Model.copyServers()`), lets the arrow function passed as `change` modify the copy, then assigns the copy to `servers` and its JSON to `cfg_servers`. The same copy-and-assign pattern as in `main.qml` \[4\]: mutating `servers` in place would not update any binding.
- **Lines 70-172, edit functions:** one per button or field: add, remove and move servers and functions, set a field, change a function's type. `addFunction(templateId)` adds a function from `templates.js`, with a translated default name it passes in. `addFlagToggle()` adds a flag toggle, named after the file if no name was given; `askFlagPath()` opens the dialog that asks for the file. After a move or remove, they fix the selection so it stays on the same item (`indexAfterMove()`). They are small on purpose; the rules live in `model.js`.
- **Lines 189-193, `primaryStatusId`:** the id of the current server's first status function. The function list labels that one "Online/Server state" instead of "Status", because it is the server's dot in the popup, not a control. Compared by id, not by object: a JS array used as a Repeater model may hand its delegates copies of the objects.
- **Lines 196-201, `ListToolButton`:** an inline type \[21\].
- **Lines 206-213, `InlineMessage`:** shown when parsing the saved config skipped or fixed something. Applying writes the cleaned-up list, so the message says so.
- **Lines 219-298, server list:** a `Repeater` \[15\] of `ItemDelegate`s, standard clickable list rows; `highlighted` marks the selected one. Below it Add, Move up, Move down and Remove.
- **Lines 300-313, `PlaceholderMessage`:** instead of the form while there are no servers.
- **Lines 315-558, server form:** a `Kirigami.FormLayout` \[20\] with the server fields (the Tailscale host is optional; `|| ""` covers servers without the field, and it shows only while Tailscale support is on), then the "Functions" section. Each function row is an `ItemDelegate` whose `contentItem` is replaced by a `RowLayout` with icon, name, type and three tool buttons. "Add Function" opens a `QQC2.Menu` with the templates; `popup(button, 0, height)` places it under the button. A `MenuSeparator` sets "Custom", an empty action, apart.
- **Lines 499-557, `flagDialog`:** a `Kirigami.Dialog` \[22\] asking for the path of the flag file and an optional name. The name field's placeholder shows the name that will be used if it stays empty (`Templates.flagName()`).
- **Lines 560-574, `FunctionEditor`:** the form for the selected function. While nothing is selected it is hidden and gets a dummy `fn`, so its bindings never read from `null`. Its signals call `setFunctionField()` and `setFunctionType()`.

### FunctionEditor.qml

The form for one function. Like `FunctionControl.qml`, one file for all three types: fields of other types have `visible: false` and take no space.

- **Lines 15-25, interface:** the function, the server and three General settings come in as properties; edits go out as signals \[16\]. The editor never changes `fn`, so all the data handling stays in `ConfigServers.qml`.
- **Lines 34-36, `indexOf()`:** the `ComboBox` models are arrays of `{ value, text }`. `textRole` and `valueRole` tell the ComboBox which field to show and which to report as `currentValue`; `indexOf()` finds the entry to show for a stored value.
- **Lines 46-58, type:** `onActivated` runs only on a user choice, not when `currentIndex` changes through its binding. The page then calls `Model.changeFunctionType()`.
- **Lines 72-108, icon:** a button with the current icon that opens `KIconThemes.IconDialog` (`import org.kde.iconthemes`), KDE's icon picker, and a text field for typing a name. The dialog is a separate window and reports a choice through its read-only `iconName`. `iconName` keeps the last pick, so picking the same icon again, for another function, doesn't change it; the `accepted` signal covers that case. Both handlers call `apply()`, and applying the same icon twice changes nothing. `objectName: "chooseIconButton"` lets the sandbox test find the button and click it.
- **Lines 115-186, commands:** one `CommandField` per command. The labels change with the type, e.g. "Check:" for a status function and "Command:" for an action. `tailscaleEnabled` and `lanOnly` (line 31, `Model.needsLan()`) go to every field; `lanOnly` tells it that the function uses `{mac}`, so its Tailscale preview says it isn't available.
- **Lines 188-254, behavior:** "Available", "Ask for confirmation" (not for status functions), the check interval (only for status functions) and the timeout. `SpinBox` holds integers; `textFromValue` adds the unit, and `valueFromText` reads a typed number back. The check interval has a "Default" check box: checked means the function has no `interval` of its own and uses the General default, which the disabled spin box shows. Checking it sends `fieldEdited("interval", undefined)`, and `setFunctionField()` in `ConfigServers.qml` deletes the field.

### CommandField.qml

One command in the function editor: a monospace text field, the command as it will run on this server (`Commands.substitute()`, the same function the widget uses, with the SSH options from the General page), and a warning line. With Tailscale support on and a server with a Tailscale host, the preview has two lines, a bold "LAN:" and "Tailscale:" each followed by the command, but only when they differ (`showBoth`): a command without `{host}` or `{ssh}` runs the same either way. For a function that uses `{mac}` (`lanOnly`), the Tailscale line says it isn't available. The prefixes are separate labels in a two-column `GridLayout` \[10\], not rich text with `<b>`: rich text would need every `<`, `>` and `&` in a command escaped and could collapse repeated spaces, and the preview has to show exactly what runs. Wrapped command lines also stay indented under the command. All four labels share an inline type, `PreviewLabel` \[21\], for the grey monospace look. It sets `font.family` and `font.pointSize` instead of the whole `font`, so the prefixes can add `font.bold: true` on top. The warning names unknown placeholders, like a typo `{hots}`, and placeholders whose server field is empty, like `{mac}` without a MAC address. The root is a `ColumnLayout`, so the three parts stack and the whole thing is one field in the `FormLayout` \[20\]. By default the form centres a label on the whole field, so with preview lines below it, "Command:" would sit beside the middle of the block instead of beside the text field. `Kirigami.FormData.buddyFor: textField` on the root tells the form which part the label belongs to, and the label lines up with that part:

```qml
Kirigami.FormData.buddyFor: textField

QQC2.TextField {
    id: textField
```

### code/model.js

Pure data helpers, no QML \[12\]. Turns the `servers` config string into objects the UI can trust: every field it reads exists and has the right type.

- **`parseServers(text)`:** the entry point. Never throws; returns `{ servers, warnings }`. Empty text is a valid empty config. Text that isn't JSON, or JSON that isn't a list, gives no servers and one warning. Otherwise each entry goes through `normalizeServer()`, and entries that come back `null` are skipped.
- **`normalizeServer()` and `normalizeFunction()`:** copy the raw object with `Object.assign({}, raw)` first, so unknown fields survive, then overwrite the known fields with checked values. `tailscaleHost` is optional: it is trimmed if present and otherwise left out. A function with an unknown `type` is skipped. Missing fields get defaults: `timeout` 10, `availableWhen` `"always"`, `confirm` `false`, an icon per type. A status function's `interval` is optional: without a valid one, the field is left out and the General default applies (`statusInterval()`). A server without a name shows its host.
- **`uniqueId()`:** a missing or duplicate id is replaced by one built from the position, like `server-2` or `nas-fn-1`. Not random, so the same config gives the same ids every time and `serverStates` survives a re-parse.
- **`asSeconds()`, `asString()`, `oneOf()`:** small type checks with a fallback. `asSeconds("30")` accepts a numeric string; `0`, negatives and `true` fall back.
- **`serializeServers(servers)`:** `JSON.stringify` for writing the config; the settings page uses it.
- **`statusFunction(server)`:** returns the first function whose `type` is `"status"`, or `null`. The `(server && server.functions) || []` guard means a malformed server can't crash it.
- **`controlFunctions(server)`:** all functions except the first status function, for the controls in the popup.
- **`functionKey(server, fn)`:** `"<serverId>/<functionId>"`, the key for `functionStates`, `runningFunctions` and `functionResults`.
- **`viaTailscale(server, tailscaleActive)`, `reachable(server, tailscaleActive)`, `needsLan(fn)`:** the Tailscale rules. A server goes over Tailscale when it is active and the server has a `tailscaleHost`; without one, it isn't reachable then. `needsLan()` is true for a function with `{mac}` in any command: Wake-on-LAN doesn't work over Tailscale.
- **`unavailableReason(fn, server, serverState, tailscaleActive)`:** `""` if the function can run now, otherwise `"unreachable"`, `"needsLan"` (both only while Tailscale is active), `"needsOnline"`, `"needsOffline"` or `"unknown"` (status not checked yet). It returns codes, not sentences, because `.pragma library` files have no `i18n()`; `FunctionControl.qml` translates them.
- **`changesOnlineState(fn)`:** true for an action that runs only online or only offline, like Wake or Power off. Only these start faster polling; an action available `always` is not expected to change the online state.
- **`statusInterval(fn, defaultInterval)`:** the function's own `interval`, or the default check interval from the General settings. A status function has no `interval` field unless one was set: `normalizeFunction()` drops a missing or invalid one.
- **`checkInterval(fn, defaultInterval, fastPollUntil, now)`:** `statusInterval()`, or 5 s (`FAST_POLL_INTERVAL`) while the fast period lasts. A function whose interval is already shorter keeps it.
- **Constants:** `FAST_POLL_DURATION` (120 s), `RESULT_OK_SECONDS` (3), and `RESULT_FAIL_SECONDS` (10). QML reads them like functions, e.g. `Model.RESULT_OK_SECONDS`.
- **`exportSetup(servers, general)` and `parseSetup(text)`** (used by `ConfigGeneral.qml`): the import and export format `{ "version": 1, "general": {…}, "servers": […] }`. `exportSetup()` is `JSON.stringify` with an indent of 2, so the text is readable. `parseSetup()` never throws. It accepts the full format or a bare server list, and returns an error code (`"invalidJson"`, `"unsupportedVersion"`, `"noServerList"`) for the page to translate, like `unavailableReason()`. Server entries go through `parseServers()`, so an import is checked exactly like the config. `parseGeneral()` keeps only the known settings with valid values and warns about the rest.
- **Editing helpers** (used by `ConfigServers.qml`): `copyServers()` makes a deep copy through JSON. `newId()` makes a random id like `fn-k3j9x0ab` that isn't used yet. `newServer()` creates an empty server; its name comes from the caller, because `i18n()` doesn't exist here. New functions come from `templates.js`. `changeFunctionType()` keeps name, icon, timeout, unknown fields and the fields both types share (`command` from status to action; `availableWhen` and `confirm` from action to toggle), drops the fields only the old type used, and fills in the new type's defaults through `normalizeFunction()`. `moveItem()` moves one entry of an array in place.

### code/templates.js

The functions "Add Function" offers \[12\].

- **`TEMPLATES`:** one entry per template, with only the fields that differ from the defaults. `fromTemplate()` adds the name and passes the result through `Model.normalizeFunction()`, which fills in the rest: timeout 10, `availableWhen` `"always"`, empty commands, and no `interval`, so a new ping uses the default check interval. "Custom" is an empty action; its type can be changed in the editor.
- **`flagToggle(path, name, servers)`:** builds the three commands `{ssh} test -f`, `{ssh} touch` and `{ssh} rm -f` for the file. The path is shell-quoted *twice*: two shells read a `{ssh}` command. The local shell removes the outer quotes, ssh joins the words into one string, and the server's shell splits that again. With quotes removed only once, `/tmp/my flags/x` would arrive as two words. A plain path has no characters that need quoting, so it stays readable.
- **`flagName(path)`:** the last part of the path, used as the default name.

### code/commands.js

Turns a command template into a safe shell string.

- **`shellQuote(value)`:** values like hosts or names are inserted into a shell command, so a name containing a space or `;` must not break it or run something extra. Values made only of safe characters (letters, digits, `.`, `-`, `@`, …) are left as is. Anything else is wrapped in single quotes; a single quote inside is written `'\''` (end the quote, an escaped quote, start a new quote), the standard POSIX trick.
- **`sshCommand(server, sshOptions)`:** builds `ssh <sshOptions> user@host`, by default `ssh -o BatchMode=yes -o ConnectTimeout=5 user@host`. The options are the General setting, inserted as typed and not quoted, because they are several shell words. `BatchMode=yes` makes ssh fail instead of asking for a password, which would hang forever with no terminal; `hasBatchMode()` checks for it so the settings can warn.
- **`placeholderValues(server, sshOptions, viaTailscale)`:** the map of `{name}` → value. `ssh` is not quoted again, because it is already a complete, quoted command. With `viaTailscale`, it first replaces the server with a copy whose `host` is the `tailscaleHost`, so `{host}` and `{ssh}` both use it.
- **`substitute(command, server, sshOptions, viaTailscale)`:** the regex `\{(\w+)\}` finds every `{word}`. For each, the replace callback returns the value if the key is known, else the original text, so unknown placeholders stay visible. `hasOwnProperty.call` avoids matching built-in object keys like `{constructor}`.
- **`withTimeout(command, seconds)`:** `timeout -k 2 10 sh -c '<command>'`. `sh -c` runs the whole command, pipes and all, as one unit that `timeout` can stop. `-k 2` sends a hard kill 2 s later if the command ignores the polite stop.
- **`isTimeoutExit(code)`:** `timeout` exits with 124 after a normal stop and 137 after a kill.
- **`errorLine(stderr)`:** the last non-empty line of the error output, for the inline message. Tools like ssh print warnings first and the real error last.
- **`unknownPlaceholders(command)`, `emptyPlaceholders(command, server)`:** for the warnings in the settings. Both start from `placeholdersIn()`, which collects each `{word}` once. `{ssh}` counts as using `{host}`, since the ssh command needs it.

### metadata.json

See Part 2. `Version` and `Authors` are shown in the widget's About page.

### tools/sandbox (not part of the widget)

The automatic load test, written in Bash, not QML.

- **`Containerfile`:** a Fedora 44 image with the Plasma 6 packages, `plasmoidviewer`, a virtual X screen (`Xvfb`) and dbus.
- **`entrypoint.sh`:** runs inside the container. Starts Xvfb, runs `plasmoidviewer` on the mounted package for 15 s, then searches the log for lines that mention `/package/` or applet load errors. Fails if it finds any, or if `plasmoidviewer` quit early.
- **`page-harness.qml`:** used by `load-test.sh --page NAME`. `plasmoidviewer` never opens the settings dialog, so a broken settings page would pass the normal test. The harness replaces `main.qml` in a copy of the package with a widget that loads the page with a `Loader`, sets a `cfg_` property for every config key like Plasma does, and then calls the page's edit functions one per timer tick: select every function, add a server and functions, set a Tailscale host, set and clear an interval, change a type, move and remove. For the General page, it sets the SSH options and the interval, enables Tailscale, clears and resets the Tailscale check, exports, clicks "Copy", and imports a bare list, a full setup and three broken texts. On the Servers page it adds every template and opens the flag dialog; it can't type into the dialog, so it adds a flag toggle directly. Errors on the way show up in the report. With `--screenshots DIR`, `grabToImage()` saves a PNG after each step.
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
| KCM | A settings page ("KDE Control Module"); `KCM.SimpleKCM` is the root of `ConfigServers.qml` |
| id | A name for an object, usable only within its own file |
| Model | The data a view shows; here the `serverList` array |
| Plasmoid | A Plasma widget; the package in `package/` |
| PlasmoidItem | The root type of a Plasma 6 widget (`main.qml`) |
| Signal | An event an object announces, e.g. `triggered`, `clicked`, `newData` |
| Source | In a DataSource, one connection; for `executable`, one command string |

Good next reads, in this order:

- [Qt: First steps with QML](https://doc.qt.io/qt-6/qmlfirststeps.html): the official introduction.
- [Qt: Property binding](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html): bindings in depth, including how assignments break them.
- [KDE: Plasma widget tutorial](https://develop.kde.org/docs/plasma/widget/): writing widgets for Plasma 6, including config pages.
- [KDE: Kirigami tutorial](https://develop.kde.org/docs/getting-started/kirigami/): the UI library behind `Kirigami.Theme`, `Units` and dialogs.
