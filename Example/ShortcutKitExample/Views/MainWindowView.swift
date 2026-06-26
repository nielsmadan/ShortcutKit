import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct MainWindowView: View {
    @ObservedObject var canvasModel = ContextWiring.canvas
    @ObservedObject var appModel = ContextWiring.app
    @ObservedObject var wizardModel = ContextWiring.wizard
    @State private var legendCompact = false
    @State private var showingLegendSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            NavigationSplitView {
                SidebarView()
                    .environmentObject(ContextWiring.sidebar)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                VStack(spacing: 0) {
                    ModeToolbarView()
                        .environmentObject(canvasModel)
                    canvasArea
                }
            }

            if appModel.legendVisible {
                Divider()
                // The right rail is the `.panel` legend (a docked, fixed-width
                // card). The Compact toggle flips `LegendOptions.compact`; the
                // button shows the same data in a `.sheet` style sheet, where its
                // scrolling, chrome-free container belongs.
                VStack(spacing: 0) {
                    KeyBindingsLegendView(
                        registry: ContextWiring.shared,
                        style: .panel,
                        contextIDs: visibleContextIDs,
                        options: LegendOptions(compact: legendCompact)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Divider()
                    HStack {
                        Toggle("Compact", isOn: $legendCompact)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer()
                        Button("Show as sheet…") { showingLegendSheet = true }
                            .controlSize(.small)
                    }
                    .padding(8)
                }
                .frame(width: 320)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .activeShortcutContext(appModel.context, dispatch: appModel.handle)
        .activeShortcutContext(canvasModel.sharedContext, dispatch: canvasModel.handleShared)
        .sheet(isPresented: $wizardModel.visible) {
            NewProjectWizard()
                .environmentObject(wizardModel)
        }
        .sheet(isPresented: $showingLegendSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keyboard Shortcuts").font(.headline)
                KeyBindingsLegendView(
                    registry: ContextWiring.shared,
                    style: .sheet,
                    contextIDs: visibleContextIDs
                )
                Button("Done") { showingLegendSheet = false }
                    .keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .frame(width: 420, height: 480)
        }
        .onChange(of: appModel.newProjectSignal) { _, _ in
            wizardModel.start()
        }
    }

    /// Canvas + its activation stack. The shared canvas context is activated
    /// at the MainWindowView root (since the canvas is always present); this
    /// area layers the per-mode context (swaps on mode change) and the
    /// selection-driven context (swaps based on selected object type).
    @ViewBuilder
    private var canvasArea: some View {
        let selectionID = canvasModel.selectionContext?.id ?? "none"

        // The mode activation is dispatched through a typed switch so the
        // modifier sees a concrete context (`some AnyShortcutContext`, not an
        // existential) — `.activeShortcutContext(_:)` is generic and cannot
        // accept `any AnyShortcutContext`.
        modeActivated(CanvasView()
            .environmentObject(canvasModel)
            .environmentObject(appModel)
            .modifier(SelectionContextModifier(canvasModel: canvasModel)))
            .id("\(canvasModel.activeMode.rawValue)|\(selectionID)")
    }

    /// Apply the active per-mode context by switching on `activeMode`. Each
    /// branch yields a different concrete `ShortcutContext<Action>` so the
    /// generic activation modifier can specialise.
    @ViewBuilder
    private func modeActivated(_ content: some View) -> some View {
        switch canvasModel.activeMode {
        case .select: content.activeShortcutContext(canvasModel.selectContext, dispatch: canvasModel.handleSelect)
        case .fill: content.activeShortcutContext(canvasModel.fillContext, dispatch: canvasModel.handleFill)
        case .stroke: content.activeShortcutContext(canvasModel.strokeContext, dispatch: canvasModel.handleStroke)
        case .text: content.activeShortcutContext(canvasModel.textContext, dispatch: canvasModel.handleText)
        case .shape: content.activeShortcutContext(canvasModel.shapeContext, dispatch: canvasModel.handleShape)
        }
    }

    /// Right-rail legend reflects everything currently active on the canvas
    /// detail pane: app shortcuts, shared canvas, the per-mode context, and
    /// (when present) the selection-driven context.
    private var visibleContextIDs: Set<String> {
        var ids: Set<String> = [
            ContextWiring.app.context.id,
            canvasModel.sharedContext.id,
            canvasModel.modeContext(for: canvasModel.activeMode).id,
        ]
        if let sel = canvasModel.selectionContext {
            ids.insert(sel.id)
        }
        return ids
    }
}

// MARK: - Selection context activation

/// Wraps the canvas with a selection-driven context activation. Branches on
/// which (if any) typed selection context the model currently exposes so the
/// generic `.activeShortcutContext` modifier always sees a concrete type.
private struct SelectionContextModifier: ViewModifier {
    @ObservedObject var canvasModel: CanvasModeContextModel

    func body(content: Content) -> some View {
        if let selected = canvasModel.selectedObject {
            if selected.isShape {
                content.activeShortcutContext(
                    canvasModel.shapeSelectedContext,
                    dispatch: canvasModel.handleShapeSelected
                )
            } else {
                content.activeShortcutContext(canvasModel.textSelectedContext, dispatch: canvasModel.handleTextSelected)
            }
        } else {
            content
        }
    }
}
