import Foundation
import ShortcutKit
import ShortcutKitUI
import SwiftUI

/// The example app's Settings scene. Beyond the Native/Dense comparison of
/// `KeyBindingsView`, the tabs double as an in-app showcase of every
/// ShortcutKitUI surface: the drop-in preferences pane, the legend styles, the
/// discoverability HUD options, the single-action editor, and a developer
/// Diagnostics panel.
@MainActor
struct ExampleSettingsView: View {
    var body: some View {
        TabView {
            StyledSettingsTab(style: .native)
                .tabItem { Label("Native", systemImage: "rectangle") }
            StyledSettingsTab(style: .dense)
                .tabItem { Label("Dense", systemImage: "rectangle.compress.vertical") }
            ShortcutPreferencesView(registry: ContextWiring.shared)
                .tabItem { Label("Drop-in", systemImage: "slider.horizontal.3") }
            LegendStylesView()
                .tabItem { Label("Legend", systemImage: "list.bullet.rectangle") }
            HUDPlaygroundView()
                .tabItem { Label("HUD", systemImage: "bubble.left.and.bubble.right") }
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
            searchEnabled: search,
            contextLayout: layout
        )
        .safeAreaInset(edge: .top, spacing: 0) { displaySection }
    }

    /// Juggler-style "Display" group plus the layout/search controls, pinned
    /// above the scrolling bindings list.
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
    }
}

// MARK: - Legend styles

@MainActor
private struct LegendStylesView: View {
    @State private var style: LegendStyle = .sidebar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legend Style").font(.headline)
            Picker("Style", selection: $style) {
                Text("Sidebar").tag(LegendStyle.sidebar)
                Text("Modal").tag(LegendStyle.modal)
                Text("Compact Strip").tag(LegendStyle.compactStrip)
            }
            .pickerStyle(.segmented)
            Divider()
            KeyBindingsLegendView(registry: ContextWiring.shared, style: style)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - HUD playground

@MainActor
private struct HUDPlaygroundView: View {
    @ObservedObject private var registry = ContextWiring.shared
    @State private var placement: HintHUDPlacement = .topTrailing
    @State private var durationSeconds: Double = 2
    @State private var policyChoice: PolicyChoice = .always
    @State private var customToast = false

    private enum PolicyChoice: String, CaseIterable, Identifiable {
        case always, oncePerSession, timeout
        var id: String { rawValue }
        var policy: HintPolicy {
            switch self {
            case .always: .always
            case .oncePerSession: .oncePerSession
            case .timeout: .timeout(2)
            }
        }

        var label: String {
            switch self {
            case .always: "Always"
            case .oncePerSession: "Once / session"
            case .timeout: "Timeout 2s"
            }
        }
    }

    private var options: HintHUDOptions {
        HintHUDOptions(placement: placement, duration: .seconds(durationSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HUD Playground").font(.headline)
            Picker("Placement", selection: $placement) {
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
            HStack {
                Text("Duration: \(durationSeconds, specifier: "%.1f")s")
                Slider(value: $durationSeconds, in: 1 ... 5, step: 0.5)
            }
            Picker("Policy", selection: $policyChoice) {
                ForEach(PolicyChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Custom toast", isOn: $customToast)
            Button("Fire test hint") {
                registry.setHintsEnabled(true)
                registry.dispatch(contextID: "app", actionID: "toggleLegend")
            }
            Spacer()
            Text("Fires the “Toggle Legend” action programmatically; the discoverability "
                + "toast appears with the chosen options. (For .cursor, move the pointer "
                + "over this pane first.)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(PlaygroundHUD(custom: customToast, policy: policyChoice.policy, options: options))
    }
}

/// Applies the discoverability HUD with the playground's chosen options, picking
/// the built-in or custom toast. A conditional modifier needs distinct branches
/// because the two `shortcutHintHUD` overloads return different view types.
@MainActor
private struct PlaygroundHUD: ViewModifier {
    let custom: Bool
    let policy: HintPolicy
    let options: HintHUDOptions

    func body(content: Content) -> some View {
        if custom {
            content.shortcutHintHUD(registry: ContextWiring.shared, policy: policy, options: options) { hint in
                Label(hint.text, systemImage: "keyboard")
                    .padding(8)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
        } else {
            content.shortcutHintHUD(registry: ContextWiring.shared, policy: policy, options: options)
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
