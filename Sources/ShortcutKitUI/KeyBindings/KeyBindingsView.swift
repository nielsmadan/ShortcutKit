import ShortcutField
import ShortcutKit
import SwiftUI

/// How `KeyBindingsView` full mode lays out multiple contexts.
public enum ContextLayout: Sendable, Hashable {
    /// Every context stacked as its own section — one long scroll.
    case stacked
    /// A context selector (segmented for a few contexts, a dropdown for many)
    /// with only the chosen context's rows shown below. Suited to apps with
    /// many contexts where stacking would scroll endlessly.
    case picker
}

/// How full-mode `KeyBindingsView` is contained. The self-contained pane's
/// options (`search`, `layout`) live on the `.standalone` case so they can't be
/// set on an `.embedded` view, where they don't apply.
public enum KeyBindingsPresentation: Sendable, Hashable {
    /// A self-contained pane that owns its scroll, a grouped card, an optional
    /// search field, and the "Reset All…" button. Use it as the whole content of
    /// a Settings tab. `search` toggles the search field; `layout` stacks every
    /// context (`.stacked`) or shows a context selector (`.picker`).
    case standalone(search: Bool = true, layout: ContextLayout = .stacked)
    /// Form/List section content: one SwiftUI `Section` per context — no scroll,
    /// card, search, or Reset-All. Place it inside your own `Form`/`List` so it
    /// inherits native grouped styling and the host's single scroll. Search and
    /// Reset-All are the host's to provide.
    case embedded
}

/// The top-level settings view for shortcut customisation.
///
/// Full mode (`init(registry:style:presentation:)`) renders one section per
/// registry context (filtered to `includeInSettings == true`). ``KeyBindingsPresentation``
/// decides containment: `.standalone` (default) is a self-contained pane for a
/// whole Settings tab; `.embedded` emits bare `Section`s to drop into your own
/// `Form`/`List` — prefer it whenever the view is one part of a larger pane.
///
/// Inline mode (`init(context:style:searchEnabled:)`) renders only the rows for
/// the given context — no section header, no toolbar, search optional (default
/// OFF). For a *single action* rather than a whole context, use
/// `ShortcutBindingEditor`. Side effects route to the context's attached registry.
@MainActor
public struct KeyBindingsView: View {
    enum Mode {
        case full(presentation: KeyBindingsPresentation)
        case inline(context: any AnyShortcutContext, searchEnabled: Bool)
    }

    /// Observed so `@Published` changes (`keyBindings`, `conflicts`, …)
    /// re-render the rows when overrides change at runtime.
    @ObservedObject var registry: ShortcutRegistry
    let mode: Mode
    let style: KeyBindingsStyle

    @State private var query: String = ""
    @State private var resetAlertShown: Bool = false
    @State private var selectedContextID: String = ""

    /// Full mode — renders every `includeInSettings` context in the registry.
    /// `presentation` picks `.standalone` (a self-contained pane; the default) or
    /// `.embedded` (bare `Section`s for your own `Form`/`List`). `style` controls
    /// visual density (`.regular` / `.dense`).
    public init(
        registry: ShortcutRegistry,
        style: KeyBindingsStyle = .regular,
        presentation: KeyBindingsPresentation = .standalone()
    ) {
        self.registry = registry
        self.style = style
        mode = .full(presentation: presentation)
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
        style: KeyBindingsStyle = .regular,
        searchEnabled: Bool = false
    ) {
        let registry = attachedRegistry(for: context)
        self.registry = registry
        self.style = style
        mode = .inline(context: context, searchEnabled: searchEnabled)
    }

    public var body: some View {
        switch mode {
        case let .full(presentation):
            switch presentation {
            case let .standalone(search, layout):
                fullBody(registry: registry, searchEnabled: search, layout: layout)
            case .embedded:
                embeddedBody(registry: registry)
            }
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
        case let .full(presentation):
            if case let .standalone(search, _) = presentation { search } else { false }
        case let .inline(_, enabled): enabled
        }
    }

    var __contextLayoutForTest: ContextLayout? {
        if case let .full(presentation) = mode, case let .standalone(_, layout) = presentation {
            layout
        } else {
            nil
        }
    }

    /// The full-mode presentation, or `nil` in inline mode.
    var __presentationForTest: KeyBindingsPresentation? {
        if case let .full(presentation) = mode { presentation } else { nil }
    }

    // swiftlint:enable identifier_name

    // MARK: - Full mode body

    @ViewBuilder
    private func fullBody(
        registry: ShortcutRegistry, searchEnabled: Bool, layout: ContextLayout
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: style == .dense ? 12 : 22) {
                if searchEnabled {
                    HStack(spacing: 10) {
                        searchBar
                        Button(uiString("Reset All…")) { resetAlertShown = true }
                            .controlSize(.small)
                    }
                }
                switch layout {
                case .stacked:
                    ForEach(visibleGroups(registry), id: \.id) { group in
                        contextSection(group, registry: registry)
                    }
                case .picker:
                    pickerContent(registry: registry)
                }
            }
            .padding(.horizontal, style == .dense ? 14 : 24)
            .padding(.vertical, style == .dense ? 10 : 20)
        }
        .alert(uiString("Reset all shortcuts to defaults?"), isPresented: $resetAlertShown) {
            Button(uiString("Cancel"), role: .cancel) {}
            Button(uiString("Reset"), role: .destructive) { registry.resetAll() }
        } message: {
            Text(uiString("This will discard all customisations across every context."))
        }
    }

    // MARK: - Embedded mode body

    /// Form/List section content: one `Section` per non-empty `includeInSettings`
    /// context, with no scroll view, no card, no search / Reset-All. The enclosing
    /// `Form`/`List` supplies the grouped styling and the single scroll.
    @ViewBuilder
    private func embeddedBody(registry: ShortcutRegistry) -> some View {
        ForEach(visibleGroups(registry).filter { !$0.entries.isEmpty }, id: \.id) { group in
            Section {
                if style == .dense { denseColumnHeader }
                ForEach(group.entries, id: \.id) { row in
                    shortcutRow(row, registry: registry)
                }
            } header: {
                Text(group.displayName)
            }
        }
    }

    /// One binding row wired to the registry.
    private func shortcutRow(
        _ row: KeyBindings.Entry, registry: ShortcutRegistry
    ) -> some View {
        ShortcutRowView(
            row: row,
            policy: ScopePolicy(registry.scope(forContextID: row.contextID)),
            style: style,
            onSet: { registry.setShortcuts($0, contextID: row.contextID, actionID: row.actionID) },
            onClear: { registry.removeShortcut(at: $0, contextID: row.contextID, actionID: row.actionID) },
            onReset: { registry.reset(contextID: row.contextID, actionID: row.actionID) }
        )
    }

    /// Context selector + the selected context's rows. The picker itself
    /// (segmented vs. dropdown) and its conflict dots come from
    /// `ContextPickerView`.
    @ViewBuilder
    private func pickerContent(registry: ShortcutRegistry) -> some View {
        let groups = visibleGroups(registry)
        let visibleIDs = groups.map(\.contextID)
        let selection = Binding(
            get: { visibleIDs.contains(selectedContextID) ? selectedContextID : (visibleIDs.first ?? "") },
            set: { selectedContextID = $0 }
        )
        ContextPickerView(
            contexts: registry.allContexts,
            selection: selection,
            conflictedIDs: registry.contextIDsWithConflicts()
        )
        if let group = groups.first(where: { $0.contextID == selection.wrappedValue }) {
            // No section header — the picker already names the context.
            rowsCard(entries: SearchField.filter(group.entries, query: query), registry: registry)
        }
    }

    /// Column header for the dense layout: aligns the labels above the two
    /// recorder slots (Primary / Alternative) and leaves a placeholder over
    /// the trailing reset-button column so the headers don't drift right.
    private var denseColumnHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Text(uiString("Primary"))
                .frame(width: ScopedShortcutRecorder.discreteWidth.dense,
                       alignment: .center)
            Text(uiString("Alternative"))
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
            TextField(uiString("Search shortcuts"), text: $query)
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
                shortcutRow(row, registry: registry)
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
                shortcutRow(row, registry: registry)
                Divider()
            }
        }
    }
}
