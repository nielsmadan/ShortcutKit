import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct MainWindowView: View {
    private enum PlaygroundTab: String, CaseIterable, Identifiable {
        case legend, hints
        var id: String { rawValue }
    }

    @ObservedObject var canvasModel = ContextWiring.canvas
    @ObservedObject var appModel = ContextWiring.app
    @ObservedObject var wizardModel = ContextWiring.wizard
    @State private var legendCompact = false
    @State private var legendSize: LegendSize = .small
    @State private var legendColumns = 1
    @State private var legendLabelWidth: LegendLabelWidth = .size
    @State private var showingLegendSheet = false
    @State private var playgroundTab: PlaygroundTab = .legend

    private var legendColumnMode: LegendColumns {
        legendColumns <= 1 ? .single : .fixed(legendColumns)
    }

    private var railColumnWidth: CGFloat {
        LegendOptions(columns: legendColumnMode, size: legendSize, labelWidth: legendLabelWidth).cellWidth + 16
    }

    private var idealRailWidth: CGFloat {
        switch playgroundTab {
        case .legend: max(200, railColumnWidth * CGFloat(legendColumns) + 16)
        case .hints: 210
        }
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
                playgroundRail
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
        .modifier(PlaygroundHUD(
            presenter: ContextWiring.hintPresenter,
            model: ContextWiring.hudPlayground
        ))
    }

    private var playgroundRail: some View {
        VStack(spacing: 0) {
            Picker("Playground", selection: $playgroundTab) {
                Text("Legend").tag(PlaygroundTab.legend)
                Text("Hints").tag(PlaygroundTab.hints)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()
            switch playgroundTab {
            case .legend:
                legendPlayground
            case .hints:
                HUDPlaygroundView(
                    model: ContextWiring.hudPlayground,
                    registry: ContextWiring.shared
                )
            }
        }
        .frame(minWidth: 190, idealWidth: idealRailWidth)
    }

    private var legendPlayground: some View {
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
    }

    @ViewBuilder
    private var canvasArea: some View {
        let selectionID = canvasModel.selectionContext?.id ?? "none"

        // The activation modifier requires a concrete context type.
        modeActivated(CanvasView()
            .environmentObject(canvasModel)
            .environmentObject(appModel)
            .modifier(SelectionContextModifier(canvasModel: canvasModel)))
            .id("\(canvasModel.activeMode.rawValue)|\(selectionID)")
    }

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
