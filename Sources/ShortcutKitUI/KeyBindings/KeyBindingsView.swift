import ShortcutField
import ShortcutKit
import SwiftUI

/// The top-level settings page for shortcut customisation.
///
/// Full mode (`init(registry:searchEnabled:)`) renders one bold-header section
/// per registry context (filtered to `includeInSettings == true`), each with
/// its rows inside a rounded grouped container — the standard macOS settings
/// layout pattern. A top toolbar holds an optional search field and a small
/// "Reset All…" trailing button.
///
/// Inline mode (`init(context:searchEnabled:)`) renders only the rows for the
/// given context — no section header, no toolbar, search optional (default
/// OFF). Designed to embed inside a custom Settings tab. Side effects route
/// to the context's attached registry.
@MainActor
public struct KeyBindingsView: View {
    enum Mode {
        case full(searchEnabled: Bool)
        case inline(context: any AnyShortcutContext, searchEnabled: Bool)
    }

    /// Observed so `@Published` changes (`keyBindingsTable`, `conflicts`, …)
    /// re-render the rows when overrides change at runtime.
    @ObservedObject var registry: ShortcutRegistry
    let mode: Mode

    @Environment(\.shortcutStyle) private var style
    @State private var query: String = ""
    @State private var resetAlertShown: Bool = false

    /// Full mode — renders every `includeInSettings` context in the registry.
    /// `searchEnabled` defaults to `true` because the standalone settings
    /// pattern almost always wants the toolbar search field.
    public init(registry: ShortcutRegistry, searchEnabled: Bool = true) {
        self.registry = registry
        mode = .full(searchEnabled: searchEnabled)
    }

    /// Inline single-context init. The context must already be attached to a
    /// `ShortcutRegistry` (i.e. constructed and passed via
    /// `ShortcutRegistry(contexts:)`) before instantiating this view, so the
    /// view can route writes through that registry.
    ///
    /// `searchEnabled` defaults to `false` here — opposite of the full-mode
    /// initializer — because inline views embed inside an adopter tab whose
    /// chrome typically already handles its own search/filtering.
    public init(
        context: ShortcutContext<some ShortcutAction>,
        searchEnabled: Bool = false
    ) {
        let registry = context.__attachedRegistry ?? ShortcutRegistry(contexts: [])
        self.registry = registry
        mode = .inline(context: context, searchEnabled: searchEnabled)
    }

    public var body: some View {
        switch mode {
        case let .full(searchEnabled):
            fullBody(registry: registry, searchEnabled: searchEnabled)
        case let .inline(context, searchEnabled):
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
        case let .full(enabled): enabled
        case let .inline(_, enabled): enabled
        }
    }

    // swiftlint:enable identifier_name

    // MARK: - Full mode body

    @ViewBuilder
    private func fullBody(registry: ShortcutRegistry, searchEnabled: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: style == .dense ? 12 : 22) {
                if searchEnabled {
                    HStack(spacing: 10) {
                        searchBar
                        Button("Reset All…") { resetAlertShown = true }
                            .controlSize(.small)
                    }
                }
                ForEach(visibleGroups(registry), id: \.id) { group in
                    contextSection(group, registry: registry)
                }
            }
            .padding(.horizontal, style == .dense ? 14 : 24)
            .padding(.vertical, style == .dense ? 10 : 20)
        }
        .alert("Reset all shortcuts to defaults?", isPresented: $resetAlertShown) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { registry.resetAll() }
        } message: {
            Text("This will discard all customisations across every context.")
        }
    }

    /// Column header for the dense layout: aligns the labels above the two
    /// recorder slots (Primary / Alternative) and leaves a placeholder over
    /// the trailing reset-button column so the headers don't drift right.
    private var denseColumnHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("Primary")
                .frame(width: ScopedShortcutRecorder.discreteWidth.dense,
                       alignment: .center)
            Text("Alternative")
                .frame(width: ScopedShortcutRecorder.discreteWidth.dense,
                       alignment: .center)
            // Reserve room for the reset icon column to keep header centred
            // above the recorders rather than spreading.
            Color.clear.frame(width: 16, height: 1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search shortcuts", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    /// Groups to render in full mode, filtered to `includeInSettings`.
    private func visibleGroups(_ registry: ShortcutRegistry) -> [KeyBindings.Group] {
        let allowed = Set(registry.allContexts.filter(\.includeInSettings).map(\.id))
        return registry.keyBindings.groups.filter { allowed.contains($0.contextID) }
    }

    @ViewBuilder
    private func contextSection(
        _ group: KeyBindings.Group,
        registry: ShortcutRegistry
    ) -> some View {
        let filtered = SearchField.filter(group.entries, query: query)
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: style == .dense ? 4 : 8) {
                Text(group.displayName)
                    .font(.system(size: style == .dense ? 12 : 14, weight: .semibold))
                rowsCard(entries: filtered, registry: registry)
            }
        }
    }

    private func rowsCard(
        entries: [KeyBindings.Entry],
        registry: ShortcutRegistry
    ) -> some View {
        VStack(spacing: 0) {
            if style == .dense {
                denseColumnHeader
                Divider().padding(.leading, 10)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, row in
                ShortcutRowView(
                    row: row,
                    policy: ScopePolicy(registry.scope(forContextID: row.contextID)),
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
                .padding(.horizontal, style == .dense ? 10 : 14)
                if idx < entries.count - 1 {
                    Divider().padding(.leading, style == .dense ? 10 : 14)
                }
            }
        }
        .background(Color.gray.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
        )
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
            let scoped = registry.keyBindings.groups
                .first(where: { $0.contextID == context.id })?
                .entries ?? []
            let filtered = SearchField.filter(scoped, query: query)
            ForEach(filtered, id: \.id) { row in
                ShortcutRowView(
                    row: row,
                    policy: ScopePolicy(context.scope),
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
