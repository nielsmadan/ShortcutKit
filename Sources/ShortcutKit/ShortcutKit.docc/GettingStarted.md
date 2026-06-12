# Getting Started

Declare actions, group them into a context, drive them from SwiftUI, and read the
effective bindings.

## Declare your actions

An action set is any `String`-backed enum conforming to ``ShortcutAction``. Each
case returns a ``ShortcutActionDefinition`` with its display name and default
shortcut. Shortcut literals like `"cmd+s"` come from the re-exported `Shortcut`
type.

```swift
import ShortcutKit

enum EditorAction: String, ShortcutAction {
    case save, undo, redo

    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .undo: .init("Undo", "cmd+z")
        case .redo: .init("Redo", "cmd+shift+z")
        }
    }
}
```

> Important: The raw value (`"save"`) is the **stable persistence id** — it's what
> a user's customization is stored against. Never rename a case's raw value to
> change persisted data; use a ``ShortcutMigration`` instead.

## Build a registry

Group the actions into a ``ShortcutContext``, then hand the contexts to a
``ShortcutRegistry``. The registry is an `ObservableObject`, so hold it where your
views can observe it.

```swift
@MainActor
final class AppModel: ObservableObject {
    let editor = ShortcutContext<EditorAction>("editor")
    lazy var registry = ShortcutRegistry(contexts: [editor])
}
```

By default the registry persists user overrides to `UserDefaults`. To use a
human-editable file instead, pass a ``FileStore`` (see <doc:GettingStarted#Persist-customization>).

## Activate a context

A `.local` context only fires while a view has activated it — attach
`activeShortcutContext(_:dispatch:)` and switch on the action:

```swift
struct EditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EditorCanvas()
            .activeShortcutContext(model.editor) { action, _ in
                switch action {
                case .save: model.save()
                case .undo: model.undo()
                case .redo: model.redo()
                }
            }
    }
}
```

The second closure parameter is a ``ShortcutDispatch`` — `.discrete` for a key
press, or `.continuous(magnitude:)` for gesture-driven actions.

## Fire an action yourself

When the user triggers an action another way — a toolbar button, a menu item —
tell the registry so the same handler runs (and the discoverability HUD can teach
the shortcut). Use the typed context, or the registry's id-based entry point:

```swift
Button("Save") { model.editor.dispatch(.save) }
// or, when you only have the ids (a command palette, a URL scheme):
model.registry.dispatch(contextID: "editor", actionID: "save")
```

Use `notify(_:)` instead of `dispatch(_:)` to record that an action fired
*without* running its handler (the side effect already happened another way).

## Read the effective binding

Show the current shortcut next to a button or menu item. Lookups reflect the
user's customization automatically:

```swift
let label = model.editor.displayStrings(for: .save).first   // e.g. "⌘S"
```

## Persist customization

To store overrides in a portable, hand-editable file rather than `UserDefaults`,
pass a ``FileStore``. The `key:` namespaces ShortcutKit's data so it can share a
config file with your own settings:

```swift
let store = FileStore(url: configURL, format: .toml, key: "shortcuts")
let registry = ShortcutRegistry(contexts: [editor], store: store)
```

Only values the user changes are written; everything else falls back to the
declared defaults.

## Next steps

- Render a settings screen, a legend, and a discoverability HUD with
  **ShortcutKitUI**.
- Register system-wide hotkeys with **ShortcutKitGlobal**.
- Detect duplicate, shadowed, and system-reserved bindings with ``Conflict``.
