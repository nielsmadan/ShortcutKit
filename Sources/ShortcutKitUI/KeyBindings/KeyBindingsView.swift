import ShortcutField
import ShortcutKit
import SwiftUI

/// Multi-context layout used by ``KeyBindingsView``.
public enum ContextLayout: Sendable, Hashable {
    /// Stack every context in one scroll view.
    case stacked
    /// Show one context selected by a segmented control or menu.
    case picker
}

/// Container for a multi-context ``KeyBindingsView``.
public enum KeyBindingsPresentation: Sendable, Hashable {
    /// A complete pane with scrolling, optional search, and Reset All.
    case standalone(search: Bool = true, layout: ContextLayout = .stacked)
    /// Sections for a host `Form` or `List`, without scrolling, search, or Reset All.
    case embedded
}

/// The top-level settings view for shortcut customisation.
///
/// Initialize with a registry for every context included in settings, or with one
/// attached context for an inline list. Use ``ShortcutBindingEditor`` for one action.
@MainActor
public struct KeyBindingsView: View {
    enum Mode {
        case full(presentation: KeyBindingsPresentation)
        case inline(context: any AnyShortcutContext, searchEnabled: Bool)
    }

    @ObservedObject var registry: ShortcutRegistry
    let mode: Mode
    let style: KeyBindingsStyle
    let showsDescriptions: Bool

    @State private var query: String = ""
    @State private var resetAlertShown: Bool = false
    @State private var selectedContextID: String = ""

    /// Creates a view for every registry context included in settings.
    /// `showsDescriptions` displays action descriptions below their names.
    public init(
        registry: ShortcutRegistry,
        style: KeyBindingsStyle = .regular,
        presentation: KeyBindingsPresentation = .standalone(),
        showsDescriptions: Bool = false
    ) {
        self.registry = registry
        self.style = style
        self.showsDescriptions = showsDescriptions
        mode = .full(presentation: presentation)
    }

    /// Creates an inline list for one context attached to a ``ShortcutRegistry``.
    /// Search is disabled by default.
    public init(
        context: ShortcutContext<some ShortcutAction>,
        style: KeyBindingsStyle = .regular,
        searchEnabled: Bool = false,
        showsDescriptions: Bool = false
    ) {
        let registry = attachedRegistry(for: context)
        self.registry = registry
        self.style = style
        self.showsDescriptions = showsDescriptions
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

    var __presentationForTest: KeyBindingsPresentation? {
        if case let .full(presentation) = mode { presentation } else { nil }
    }

    var __showsDescriptionsForTest: Bool { showsDescriptions }

    // swiftlint:enable identifier_name

    // MARK: - Full mode body

    @ViewBuilder
    private func fullBody(
        registry: ShortcutRegistry, searchEnabled: Bool, layout: ContextLayout
    ) -> some View {
        ScrollView {
            // Recorder-backed rows are expensive, so realize them lazily.
            LazyVStack(alignment: .leading, spacing: style == .dense ? 12 : 22) {
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

    private func shortcutRow(
        _ row: KeyBindings.Entry, registry: ShortcutRegistry
    ) -> some View {
        ShortcutRowView(
            row: row,
            policy: ScopePolicy(registry.scope(forContextID: row.contextID)),
            style: style,
            showsDescription: showsDescriptions,
            onSet: { registry.setShortcuts($0, contextID: row.contextID, actionID: row.actionID) },
            onClear: { registry.removeShortcut(at: $0, contextID: row.contextID, actionID: row.actionID) },
            onReset: { registry.reset(contextID: row.contextID, actionID: row.actionID) }
        )
    }

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
            rowsCard(entries: SearchField.filter(group.entries, query: query), registry: registry)
        }
    }

    private var denseColumnHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Text(uiString("Primary"))
                .frame(width: ScopedShortcutRecorder.discreteWidth.dense,
                       alignment: .center)
            Text(uiString("Alternative"))
                .frame(width: ScopedShortcutRecorder.discreteWidth.dense,
                       alignment: .center)
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
