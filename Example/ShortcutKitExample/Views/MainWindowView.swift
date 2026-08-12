import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct MainWindowView: View {
    @ObservedObject var canvasModel = ContextWiring.canvas
    @ObservedObject var appModel = ContextWiring.app
    @ObservedObject var wizardModel = ContextWiring.wizard
    @State private var legendCompact = false
    @State private var legendSize: LegendSize = .small
    @State private var legendColumns = 1
    @State private var legendLabelWidth: LegendLabelWidth = .size
    @State private var showingLegendSheet = false

    /// `.single` for one column, `.fixed(n)` beyond — matches the rail's Columns stepper.
    private var legendColumnMode: LegendColumns {
        legendColumns <= 1 ? .single : .fixed(legendColumns)
    }

    /// Width of one entry cell for the current options, read from the library's
    /// public `cellWidth` (so it tracks the size / label-width choices instead of
    /// duplicating the internal metrics), plus a little padding.
    private var railColumnWidth: CGFloat {
        LegendOptions(columns: legendColumnMode, size: legendSize, labelWidth: legendLabelWidth).cellWidth + 16
    }

    /// Ideal rail width: wide enough for the controls and chosen column count.
    private var idealRailWidth: CGFloat {
        max(300, railColumnWidth * CGFloat(legendColumns) + 16)
    }

    var body: some View {
        HSplitView {
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
                // The right rail is the `.panel` legend (a docked, resizable
                // card). The Compact toggle flips `LegendOptions.compact`; the
                // button shows the same data in a `.sheet` style sheet, where its
                // scrolling, chrome-free container belongs.
                VStack(spacing: 0) {
                    KeyBindingsLegendView(
                        registry: ContextWiring.shared,
                        style: .panel,
                        contextIDs: visibleContextIDs,
                        options: LegendOptions(
                            columns: legendColumnMode,
                            size: legendSize,
                            compact: legendCompact,
                            labelWidth: legendLabelWidth
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Divider()
                    VStack(spacing: 6) {
                        HStack {
                            Picker("Size", selection: $legendSize) {
                                Text("S").tag(LegendSize.small)
                                Text("M").tag(LegendSize.medium)
                                Text("L").tag(LegendSize.large)
                                Text("XL").tag(LegendSize.extraLarge)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Toggle("Compact", isOn: $legendCompact)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        Picker("Label", selection: $legendLabelWidth) {
                            Text("Size").tag(LegendLabelWidth.size)
                            Text("Flex").tag(LegendLabelWidth.flexible)
                            Text("Fixed 240").tag(LegendLabelWidth.fixed(240))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(legendCompact)
                        Stepper("Columns: \(legendColumns)", value: $legendColumns, in: 1 ... 4)
                            .controlSize(.small)
                            .disabled(legendCompact)
                        Button("Show as sheet…") { showingLegendSheet = true }
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(8)
                }
                .frame(minWidth: 220, idealWidth: idealRailWidth)
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
                    contextIDs: visibleContextIDs,
                    options: LegendOptions(size: legendSize)
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
