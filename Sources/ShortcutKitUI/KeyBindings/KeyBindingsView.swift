import ShortcutField
import ShortcutKit
import SwiftUI

/// The top-level settings page for shortcut customisation.
///
/// Full mode (`init(registry:searchEnabled:)`) renders a search field, a
/// "Reset All to Defaults" button, a `ContextPickerView` over registry
/// contexts (filtered to `includeInSettings == true`), and a scrolling list
/// of `ShortcutRowView`s for the rows of the currently-selected context.
///
/// Inline mode (`init(context:searchEnabled:)`) renders only the rows for
/// the given context — no picker, no "Reset All" toolbar, search optional
/// (default OFF). Designed to embed inside a `Form { Section { ... } }`
/// which provides its own scrolling. Side effects route to the context's
/// attached registry.
@MainActor
public struct KeyBindingsView: View {
    enum Mode {
        case full(registry: ShortcutRegistry, searchEnabled: Bool)
        case inline(context: any AnyShortcutContext, registry: ShortcutRegistry, searchEnabled: Bool)
    }

    let mode: Mode

    @State private var selectedContextID: String = ""
    @State private var query: String = ""
    @State private var resetAlertShown: Bool = false

    public init(registry: ShortcutRegistry, searchEnabled: Bool = true) {
        mode = .full(registry: registry, searchEnabled: searchEnabled)
    }

    /// Inline single-context init. The context must already be attached to a
    /// `ShortcutRegistry` (i.e. constructed and passed via
    /// `ShortcutRegistry(contexts:)`) before instantiating this view, so the
    /// view can route writes through that registry.
    public init(
        context: ShortcutContext<some ShortcutAction>,
        searchEnabled: Bool = false
    ) {
        let registry = context.__attachedRegistry ?? ShortcutRegistry(contexts: [])
        mode = .inline(context: context, registry: registry, searchEnabled: searchEnabled)
    }

    public var body: some View {
        switch mode {
        case let .full(registry, searchEnabled):
            fullBody(registry: registry, searchEnabled: searchEnabled)
        case let .inline(context, registry, searchEnabled):
            inlineBody(context: context, registry: registry, searchEnabled: searchEnabled)
        }
    }

    // MARK: - Testability hooks (internal)

    // swiftlint:disable identifier_name
    var __modeIsFull: Bool {
        if case .full = mode { true } else { false }
    }

    var __searchEnabledForTest: Bool {
        switch mode {
        case let .full(_, enabled): enabled
        case let .inline(_, _, enabled): enabled
        }
    }

    // swiftlint:enable identifier_name

    // MARK: - Full mode body

    @ViewBuilder
    private func fullBody(registry: ShortcutRegistry, searchEnabled: Bool) -> some View {
        VStack(alignment: .leading) {
            HStack {
                if searchEnabled { SearchField(query: $query) }
                Spacer()
                Button("Reset All to Defaults") { resetAlertShown = true }
            }
            ContextPickerView(
                contexts: registry.allContexts,
                selection: $selectedContextID,
                conflictedIDs: registry.contextIDsWithConflicts()
            )
            rowList(registry: registry)
        }
        .onAppear {
            if selectedContextID.isEmpty {
                selectedContextID = registry.allContexts
                    .first(where: \.includeInSettings)?.id ?? ""
            }
        }
        .alert("Reset all shortcuts to defaults?", isPresented: $resetAlertShown) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { registry.resetAll() }
        } message: {
            Text("This will discard all customisations across every context.")
        }
    }

    @ViewBuilder
    private func rowList(registry: ShortcutRegistry) -> some View {
        let scoped = registry.keyBindingsTable.sections
            .first(where: { $0.contextID == selectedContextID })?
            .rows ?? []
        let filtered = SearchField.filter(scoped, query: query)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered, id: \.actionID) { row in
                    ShortcutRowView(
                        row: row,
                        policy: ScopePolicy(registry.scope(forContextID: row.contextID)),
                        bindingsPerAction: registry.bindingsPerAction,
                        onSet: { shortcuts in
                            registry.setShortcuts(
                                shortcuts,
                                contextID: row.contextID,
                                actionID: row.actionID
                            )
                        },
                        onClear: { idx in
                            registry.removeShortcut(
                                at: idx,
                                contextID: row.contextID,
                                actionID: row.actionID
                            )
                        },
                        onReset: {
                            registry.resetAction(
                                contextID: row.contextID,
                                actionID: row.actionID
                            )
                        }
                    )
                    Divider()
                }
            }
        }
    }

    // MARK: - Inline mode body

    @ViewBuilder
    private func inlineBody(
        context: any AnyShortcutContext,
        registry: ShortcutRegistry,
        searchEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading) {
            if searchEnabled { SearchField(query: $query) }
            let scoped = registry.keyBindingsTable.sections
                .first(where: { $0.contextID == context.id })?
                .rows ?? []
            let filtered = SearchField.filter(scoped, query: query)
            ForEach(filtered, id: \.actionID) { row in
                ShortcutRowView(
                    row: row,
                    policy: ScopePolicy(context.scope),
                    bindingsPerAction: registry.bindingsPerAction,
                    onSet: { shortcuts in
                        registry.setShortcuts(
                            shortcuts,
                            contextID: row.contextID,
                            actionID: row.actionID
                        )
                    },
                    onClear: { idx in
                        registry.removeShortcut(
                            at: idx,
                            contextID: row.contextID,
                            actionID: row.actionID
                        )
                    },
                    onReset: {
                        registry.resetAction(
                            contextID: row.contextID,
                            actionID: row.actionID
                        )
                    }
                )
                Divider()
            }
        }
    }
}
