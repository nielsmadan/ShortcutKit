import Combine
import CoreGraphics
import Foundation
import ShortcutKit

// MARK: - Per-mode action enums

/// Tools in the select mode. Each per-mode action enum is intentionally
/// distinct so each mode advertises its own bindings in Settings and so
/// keys can overlap between modes without conflicting (e.g. `1`/`2`/`3` in
/// fill vs stroke).
enum SelectModeAction: String, ShortcutAction {
    case lasso, wand, move

    var definition: ShortcutActionDefinition {
        switch self {
        case .lasso: .init("Lasso", Shortcut("l"))
        case .wand: .init("Wand", Shortcut("w"))
        case .move: .init("Move", Shortcut("m"))
        }
    }
}

enum FillModeAction: String, ShortcutAction {
    case applyRed, applyBlue, applyGreen

    var definition: ShortcutActionDefinition {
        switch self {
        case .applyRed: .init("Apply Red", Shortcut("1"))
        case .applyBlue: .init("Apply Blue", Shortcut("2"))
        case .applyGreen: .init("Apply Green", Shortcut("3"))
        }
    }
}

enum StrokeModeAction: String, ShortcutAction {
    case thin, medium, thick

    var definition: ShortcutActionDefinition {
        switch self {
        case .thin: .init("Thin Stroke", Shortcut("1"))
        case .medium: .init("Medium Stroke", Shortcut("2"))
        case .thick: .init("Thick Stroke", Shortcut("3"))
        }
    }
}

enum TextModeAction: String, ShortcutAction {
    case serif, sans, mono

    var definition: ShortcutActionDefinition {
        switch self {
        // Avoid collisions with shared actions on `r`/`t`/`e`.
        case .serif: .init("Serif", Shortcut("s"))
        case .sans: .init("Sans", Shortcut("a"))
        case .mono: .init("Mono", Shortcut("o"))
        }
    }
}

enum ShapeModeAction: String, ShortcutAction {
    case square, circle, triangle

    var definition: ShortcutActionDefinition {
        switch self {
        case .square: .init("Square", Shortcut("q"))
        case .circle: .init("Circle", Shortcut("c"))
        case .triangle: .init("Triangle", Shortcut("g"))
        }
    }
}

// MARK: - Canvas umbrella model

@MainActor
final class CanvasModeContextModel: ObservableObject {
    @Published var activeMode: CanvasMode = .select
    @Published var statusLEDPulse = 0
    @Published var rotation: Double = 0

    // Canvas object model.
    @Published var objects: [CanvasObject] = []
    @Published var selectedObjectID: UUID?

    // Per-mode tool state (just for display/inspection).
    @Published var lastSelectTool: SelectModeAction = .lasso
    @Published var currentFillIndex: Int = 0
    @Published var currentStrokeIndex: Int = 1 // 0=thin, 1=medium, 2=thick
    @Published var currentTextFontIndex: Int = 0 // 0=serif, 1=sans, 2=mono
    @Published var lastShapeStamp: ShapeModeAction = .square

    let sharedContext: ShortcutContext<CanvasSharedAction>
    let selectContext: ShortcutContext<SelectModeAction>
    let fillContext: ShortcutContext<FillModeAction>
    let strokeContext: ShortcutContext<StrokeModeAction>
    let textContext: ShortcutContext<TextModeAction>
    let shapeContext: ShortcutContext<ShapeModeAction>

    let shapeSelectedContext: ShortcutContext<ShapeSelectedAction>
    let textSelectedContext: ShortcutContext<TextSelectedAction>

    init() {
        sharedContext = ShortcutContext<CanvasSharedAction>("canvas.shared")
        selectContext = ShortcutContext<SelectModeAction>("canvas.select")
        fillContext = ShortcutContext<FillModeAction>("canvas.fill")
        strokeContext = ShortcutContext<StrokeModeAction>("canvas.stroke")
        textContext = ShortcutContext<TextModeAction>("canvas.text")
        shapeContext = ShortcutContext<ShapeModeAction>("canvas.shape")
        shapeSelectedContext = ShortcutContext<ShapeSelectedAction>("canvas.selection.shape")
        textSelectedContext = ShortcutContext<TextSelectedAction>("canvas.selection.text")
    }

    // MARK: - Handlers

    func handleShared(_ action: CanvasSharedAction, _ dispatch: ShortcutDispatch) {
        switch action {
        case .rotateRight, .rotateLeft:
            if case let .continuous(magnitude) = dispatch {
                rotation -= magnitude * 10
            }
        case .addRectangle:
            addObject(.rectangle(size: 60, fillIndex: currentFillIndex))
        case .addEllipse:
            addObject(.ellipse(size: 60, fillIndex: currentFillIndex))
        case .addText:
            addObject(.text(content: "Text", fontSize: 18, bold: false))
        case .deleteSelected: deleteSelected()
        case .selectNextObject: walkSelection(by: 1)
        case .selectPreviousObject: walkSelection(by: -1)
        }
    }

    func handleSelect(_ action: SelectModeAction, _: ShortcutDispatch) {
        lastSelectTool = action
        statusLEDPulse += 1
    }

    func handleFill(_ action: FillModeAction, _: ShortcutDispatch) {
        switch action {
        case .applyRed: currentFillIndex = 0
        case .applyBlue: currentFillIndex = 1
        case .applyGreen: currentFillIndex = 2
        }
        applyFillToSelection(currentFillIndex)
        statusLEDPulse += 1
    }

    func handleStroke(_ action: StrokeModeAction, _: ShortcutDispatch) {
        switch action {
        case .thin: currentStrokeIndex = 0
        case .medium: currentStrokeIndex = 1
        case .thick: currentStrokeIndex = 2
        }
        statusLEDPulse += 1
    }

    func handleText(_ action: TextModeAction, _: ShortcutDispatch) {
        switch action {
        case .serif: currentTextFontIndex = 0
        case .sans: currentTextFontIndex = 1
        case .mono: currentTextFontIndex = 2
        }
        statusLEDPulse += 1
    }

    func handleShape(_ action: ShapeModeAction, _: ShortcutDispatch) {
        lastShapeStamp = action
        switch action {
        case .square, .triangle:
            addObject(.rectangle(size: 60, fillIndex: currentFillIndex))
        case .circle:
            addObject(.ellipse(size: 60, fillIndex: currentFillIndex))
        }
        statusLEDPulse += 1
    }

    func handleShapeSelected(_ action: ShapeSelectedAction, _: ShortcutDispatch) {
        switch action {
        case .sizeUp: resizeSelectedShape(by: 10)
        case .sizeDown: resizeSelectedShape(by: -10)
        case .cycleFill: cycleFillOnSelection()
        }
        statusLEDPulse += 1
    }

    func handleTextSelected(_ action: TextSelectedAction, _: ShortcutDispatch) {
        switch action {
        case .fontSizeUp: resizeSelectedText(by: 2)
        case .fontSizeDown: resizeSelectedText(by: -2)
        case .toggleBold: toggleBoldOnSelection()
        }
        statusLEDPulse += 1
    }

    // MARK: - Mode → context routing

    /// Returns the per-mode context as a heterogeneous `any AnyShortcutContext`
    /// so the caller can apply `.activeShortcutContext(_:)` regardless of which
    /// concrete `Action` type backs the current mode.
    func modeContext(for mode: CanvasMode) -> any AnyShortcutContext {
        switch mode {
        case .select: selectContext
        case .fill: fillContext
        case .stroke: strokeContext
        case .text: textContext
        case .shape: shapeContext
        }
    }

    /// Per-mode context IDs in declaration order. Used by the legend and the
    /// context-wiring mutex set.
    var allModeContextIDs: [String] {
        [selectContext.id, fillContext.id, strokeContext.id, textContext.id, shapeContext.id]
    }

    /// The selection-driven context that should currently be active, or `nil`
    /// when nothing matching is selected. Returned as the existential so the
    /// view can apply the activation modifier without branching on type.
    var selectionContext: (any AnyShortcutContext)? {
        guard let selected = selectedObject else { return nil }
        return selected.isShape ? shapeSelectedContext : textSelectedContext
    }

    var selectedObject: CanvasObject? {
        guard let id = selectedObjectID else { return nil }
        return objects.first(where: { $0.id == id })
    }

    // MARK: - Object mutation

    private func addObject(_ kind: CanvasObject.Kind) {
        // Stagger new objects diagonally so they're visible rather than stacked.
        let n = objects.count
        let offsetX = 80 + Double(n % 8) * 60
        let offsetY = 80 + Double(n % 6) * 60
        let obj = CanvasObject(id: UUID(), position: CGPoint(x: offsetX, y: offsetY), kind: kind)
        objects.append(obj)
        selectedObjectID = obj.id
        statusLEDPulse += 1
    }

    private func deleteSelected() {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        objects.remove(at: idx)
        // Re-select neighbour if any.
        if objects.isEmpty {
            selectedObjectID = nil
        } else {
            let nextIdx = min(idx, objects.count - 1)
            selectedObjectID = objects[nextIdx].id
        }
        statusLEDPulse += 1
    }

    private func walkSelection(by step: Int) {
        guard !objects.isEmpty else { return }
        if let id = selectedObjectID,
           let idx = objects.firstIndex(where: { $0.id == id })
        {
            let next = (idx + step + objects.count) % objects.count
            selectedObjectID = objects[next].id
        } else {
            selectedObjectID = objects.first?.id
        }
        statusLEDPulse += 1
    }

    private func applyFillToSelection(_ fillIndex: Int) {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        switch objects[idx].kind {
        case let .rectangle(size, _):
            objects[idx].kind = .rectangle(size: size, fillIndex: fillIndex)
        case let .ellipse(size, _):
            objects[idx].kind = .ellipse(size: size, fillIndex: fillIndex)
        case .text:
            break
        }
    }

    private func cycleFillOnSelection() {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        switch objects[idx].kind {
        case let .rectangle(size, fill):
            objects[idx].kind = .rectangle(size: size, fillIndex: (fill + 1) % CanvasPalette.count)
        case let .ellipse(size, fill):
            objects[idx].kind = .ellipse(size: size, fillIndex: (fill + 1) % CanvasPalette.count)
        case .text:
            break
        }
    }

    private func resizeSelectedShape(by delta: Double) {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        switch objects[idx].kind {
        case let .rectangle(size, fill):
            objects[idx].kind = .rectangle(size: max(10, size + delta), fillIndex: fill)
        case let .ellipse(size, fill):
            objects[idx].kind = .ellipse(size: max(10, size + delta), fillIndex: fill)
        case .text:
            break
        }
    }

    private func resizeSelectedText(by delta: Double) {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        if case let .text(content, fontSize, bold) = objects[idx].kind {
            objects[idx].kind = .text(content: content, fontSize: max(8, fontSize + delta), bold: bold)
        }
    }

    private func toggleBoldOnSelection() {
        guard let id = selectedObjectID,
              let idx = objects.firstIndex(where: { $0.id == id })
        else { return }
        if case let .text(content, fontSize, bold) = objects[idx].kind {
            objects[idx].kind = .text(content: content, fontSize: fontSize, bold: !bold)
        }
    }
}
