import Combine
import Foundation
import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct ExampleSettingsView: View {
    var body: some View {
        TabView {
            StyledSettingsTab(style: .regular)
                .tabItem { Label("Regular", systemImage: "rectangle") }
            StyledSettingsTab(style: .dense)
                .tabItem { Label("Dense", systemImage: "rectangle.compress.vertical") }
            ShortcutPreferencesView(registry: ContextWiring.shared)
                .tabItem { Label("Drop-in", systemImage: "slider.horizontal.3") }
            LegendStylesView()
                .tabItem { Label("Legend", systemImage: "list.bullet.rectangle") }
            QuickSetupView()
                .tabItem { Label("Quick Setup", systemImage: "wand.and.stars") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 720, height: 560)
    }
}

// MARK: - Settings table (Native / Dense) with layout + search controls

@MainActor
private struct StyledSettingsTab: View {
    let style: KeyBindingsStyle
    @ObservedObject private var registry = ContextWiring.shared
    @State private var layout: ContextLayout = .stacked
    @State private var search = true

    var body: some View {
        KeyBindingsView(
            registry: ContextWiring.shared,
            style: style,
            presentation: .standalone(search: search, layout: layout)
        )
        .safeAreaInset(edge: .top, spacing: 0) { displaySection }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display")
                .font(.system(size: 14, weight: .semibold))
            HStack {
                Text("Show shortcut hints")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { registry.hintsEnabled },
                    set: { registry.setHintsEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
            )
            HStack {
                Picker("Layout", selection: $layout) {
                    Text("Stacked").tag(ContextLayout.stacked)
                    Text("Picker").tag(ContextLayout.picker)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Spacer()
                Toggle("Search field", isOn: $search)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Legend styles

@MainActor
private struct LegendStylesView: View {
    @State private var style: LegendStyle = .panel
    @State private var columns: ColumnChoice = .auto
    @State private var entryLayout: LegendEntryLayout = .shortcutLeading
    @State private var size: LegendSize = .small
    @State private var compact = false

    private enum ColumnChoice: String, CaseIterable, Identifiable {
        case auto, two, single
        var id: String { rawValue }
        var columns: LegendColumns {
            switch self {
            case .auto: .auto(minWidth: 150)
            case .two: .fixed(2)
            case .single: .single
            }
        }
    }

    private var options: LegendOptions {
        LegendOptions(columns: columns.columns, entryLayout: entryLayout, size: size, compact: compact)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legend").font(.headline)
            HStack {
                Picker("Style", selection: $style) {
                    Text("Panel").tag(LegendStyle.panel)
                    Text("Sheet").tag(LegendStyle.sheet)
                }
                .pickerStyle(.segmented)
                Toggle("Compact", isOn: $compact)
            }
            Picker("Columns", selection: $columns) {
                Text("Auto").tag(ColumnChoice.auto)
                Text("2 columns").tag(ColumnChoice.two)
                Text("Single").tag(ColumnChoice.single)
            }
            .pickerStyle(.segmented)
            Picker("Cell", selection: $entryLayout) {
                Text("Shortcut first").tag(LegendEntryLayout.shortcutLeading)
                Text("Label first").tag(LegendEntryLayout.labelLeading)
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: $size) {
                Text("S").tag(LegendSize.small)
                Text("M").tag(LegendSize.medium)
                Text("L").tag(LegendSize.large)
                Text("XL").tag(LegendSize.extraLarge)
            }
            .pickerStyle(.segmented)
            Divider()
            KeyBindingsLegendView(registry: ContextWiring.shared, style: style, options: options)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - HUD playground

struct HUDPlaygroundConfiguration {
    enum RendererChoice: String, CaseIterable, Identifiable {
        case builtIn, custom
        var id: String { rawValue }
        var label: String { self == .builtIn ? "Built-in style" : "Custom view" }
    }

    enum TransitionChoice: String, CaseIterable, Identifiable {
        case automatic, fade, scale, move, none
        var id: String { rawValue }

        func transition(edge: Edge) -> HintHUDTransition {
            switch self {
            case .automatic: .automatic
            case .fade: .fade
            case .scale: .scale
            case .move: .move(edge: edge)
            case .none: .none
            }
        }
    }

    enum FontChoice: String, CaseIterable, Identifiable {
        case automatic, caption, body, headline, monospaced
        var id: String { rawValue }

        var font: Font? {
            switch self {
            case .automatic: nil
            case .caption: .caption
            case .body: .body
            case .headline: .headline
            case .monospaced: .system(.body, design: .monospaced)
            }
        }
    }

    var placement: HintHUDPlacement = .topTrailing
    var presentation: HintHUDPresentation = .view
    var durationSeconds: Double = 2
    var renderer: RendererChoice = .builtIn
    var transitionChoice: TransitionChoice = .automatic
    var moveEdge: Edge = .top
    var size: ShortcutHintSize = .automatic
    var container: ShortcutHintContainerStyle = .roundedRectangle
    var fontChoice: FontChoice = .automatic
    var overridesTextColor = false
    var textColor = Color.white
    var overridesBackgroundColor = false
    var backgroundColor = Color.indigo

    var options: HintHUDOptions {
        HintHUDOptions(
            placement: placement,
            presentation: presentation,
            duration: .seconds(durationSeconds),
            transition: transitionChoice.transition(edge: moveEdge)
        )
    }

    var toastStyle: ShortcutHintToastStyle {
        ShortcutHintToastStyle(
            size: size,
            font: fontChoice.font,
            textColor: overridesTextColor ? textColor : nil,
            backgroundColor: overridesBackgroundColor ? backgroundColor : nil,
            container: container
        )
    }
}

@MainActor
final class HUDPlaygroundModel: ObservableObject {
    @Published var configuration = HUDPlaygroundConfiguration()
}

@MainActor
struct HUDPlaygroundView: View {
    @ObservedObject var model: HUDPlaygroundModel
    let registry: ShortcutRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Show Hint", action: fireHint)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                renderingControls
                presentationControls
                appearanceControls
                Button("Reset Defaults", action: resetDefaults)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var renderingControls: some View {
        GroupBox("Rendering") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Mode", selection: $model.configuration.renderer) {
                    ForEach(HUDPlaygroundConfiguration.RendererChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(model.configuration.renderer == .builtIn
                    ? "Uses ShortcutHintToastStyle with selective overrides."
                    : "Uses the full custom-view closure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var presentationControls: some View {
        GroupBox("Presentation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Host", selection: $model.configuration.presentation) {
                    Text("View").tag(HintHUDPresentation.view)
                    Text("Window").tag(HintHUDPresentation.window)
                    Text("Screen").tag(HintHUDPresentation.screen)
                }
                .pickerStyle(.segmented)
                Picker("Placement", selection: $model.configuration.placement) {
                    Text("Top Leading").tag(HintHUDPlacement.topLeading)
                    Text("Top").tag(HintHUDPlacement.top)
                    Text("Top Trailing").tag(HintHUDPlacement.topTrailing)
                    Text("Leading").tag(HintHUDPlacement.leading)
                    Text("Center").tag(HintHUDPlacement.center)
                    Text("Trailing").tag(HintHUDPlacement.trailing)
                    Text("Bottom Leading").tag(HintHUDPlacement.bottomLeading)
                    Text("Bottom").tag(HintHUDPlacement.bottom)
                    Text("Bottom Trailing").tag(HintHUDPlacement.bottomTrailing)
                    Text("Cursor").tag(HintHUDPlacement.cursor)
                }
                Picker("Transition", selection: $model.configuration.transitionChoice) {
                    ForEach(HUDPlaygroundConfiguration.TransitionChoice.allCases) { choice in
                        Text(choice.rawValue.capitalized).tag(choice)
                    }
                }
                if model.configuration.transitionChoice == .move {
                    Picker("Move edge", selection: $model.configuration.moveEdge) {
                        Text("Top").tag(Edge.top)
                        Text("Bottom").tag(Edge.bottom)
                        Text("Leading").tag(Edge.leading)
                        Text("Trailing").tag(Edge.trailing)
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("Duration: \(model.configuration.durationSeconds, specifier: "%.1f")s")
                    Slider(value: $model.configuration.durationSeconds, in: 1 ... 5, step: 0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceControls: some View {
        GroupBox("Built-in Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Size", selection: $model.configuration.size) {
                    Text("Auto").tag(ShortcutHintSize.automatic)
                    Text("S").tag(ShortcutHintSize.small)
                    Text("M").tag(ShortcutHintSize.medium)
                    Text("L").tag(ShortcutHintSize.large)
                    Text("XL").tag(ShortcutHintSize.extraLarge)
                }
                .pickerStyle(.segmented)
                Picker("Container", selection: $model.configuration.container) {
                    Text("Rounded").tag(ShortcutHintContainerStyle.roundedRectangle)
                    Text("Capsule").tag(ShortcutHintContainerStyle.capsule)
                    Text("Rectangle").tag(ShortcutHintContainerStyle.rectangle)
                    Text("None").tag(ShortcutHintContainerStyle.none)
                }
                Picker("Font", selection: $model.configuration.fontChoice) {
                    ForEach(HUDPlaygroundConfiguration.FontChoice.allCases) { choice in
                        Text(choice.rawValue.capitalized).tag(choice)
                    }
                }
                Toggle("Override text color", isOn: $model.configuration.overridesTextColor)
                if model.configuration.overridesTextColor {
                    ColorPicker("Text color", selection: $model.configuration.textColor, supportsOpacity: true)
                }
                Toggle("Override background", isOn: $model.configuration.overridesBackgroundColor)
                if model.configuration.overridesBackgroundColor {
                    ColorPicker(
                        "Background color",
                        selection: $model.configuration.backgroundColor,
                        supportsOpacity: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.configuration.renderer == .custom)
    }

    private func fireHint() {
        registry.setHintsEnabled(true)
        registry.setHintFrequency(.always)
        registry.notify(contextID: ContextWiring.app.context.id, actionID: AppAction.fireConfetti.rawValue)
    }

    private func resetDefaults() {
        model.configuration = HUDPlaygroundConfiguration()
        registry.setHintsEnabled(true)
        registry.setHintFrequency(.always)
    }
}

@MainActor
struct PlaygroundHUD: ViewModifier {
    let presenter: ShortcutHintPresenter
    @ObservedObject var model: HUDPlaygroundModel

    func body(content: Content) -> some View {
        let configuration = model.configuration
        content.shortcutHintHUD(presenter: presenter, options: configuration.options) { hint in
            if configuration.renderer == .custom {
                Label(hint.text, systemImage: "keyboard")
                    .padding(8)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            } else {
                configuration.toastStyle.makeBody(configuration: hint)
            }
        }
    }
}

// MARK: - Quick setup (single-action editors)

@MainActor
private struct QuickSetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Setup").font(.headline)
            Text("`ShortcutBindingEditor` edits one action, anywhere — onboarding, a popover, a custom pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            ShortcutBindingEditor(.newProject, in: ContextWiring.app.context, showsDescription: true)
            ShortcutBindingEditor(.openInspector, in: ContextWiring.app.context, showsDescription: true)
            ShortcutBindingEditor(.fireConfetti, in: ContextWiring.app.context)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Diagnostics (developer utilities)

@MainActor
private struct DiagnosticsView: View {
    @ObservedObject private var registry = ContextWiring.shared
    @State private var dump = ""
    @State private var toml = ""
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics").font(.headline)

                GroupBox("Persistence") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Reload from store") {
                                status = registry.reload() ? "reloaded ✓" : "reload failed"
                            }
                            Button("Clear stored overrides") {
                                try? UserDefaultsStore().clear()
                                _ = registry.reload()
                                status = "cleared"
                            }
                            if !status.isEmpty {
                                Text(status).foregroundStyle(.secondary)
                            }
                        }
                        Button("Dump RawState (debugDescription)") {
                            dump = (try? UserDefaultsStore().load().debugDescription) ?? "(load failed)"
                        }
                        if !dump.isEmpty { monospaced(dump) }
                        Button("Export overrides to a TOML FileStore") {
                            let state = (try? UserDefaultsStore().load()) ?? RawState()
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("shortcutkit-export.toml")
                            try? FileStore(url: url, format: .toml, key: "shortcuts").save(state)
                            toml = (try? String(contentsOf: url, encoding: .utf8)) ?? "(export failed)"
                        }
                        if !toml.isEmpty { monospaced(toml) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Conflicts (\(registry.conflicts.count))") {
                    if registry.conflicts.isEmpty {
                        Text("No conflicts detected.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(registry.conflicts.enumerated()), id: \.offset) { _, conflict in
                                Text(String(describing: conflict))
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func monospaced(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}
