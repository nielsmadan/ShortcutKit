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
        let holder = ModelHolder()
        sharedContext = Self.makeSharedContext(holder)
        selectContext = Self.makeSelectContext(holder)
        fillContext = Self.makeFillContext(holder)
        strokeContext = Self.makeStrokeContext(holder)
        textContext = Self.makeTextContext(holder)
        shapeContext = Self.makeShapeContext(holder)
        shapeSelectedContext = Self.makeShapeSelectedContext(holder)
        textSelectedContext = Self.makeTextSelectedContext(holder)
        holder.target = self
    }

    // MARK: - Context factories

    private static func makeSharedContext(_ holder: ModelHolder)
        -> ShortcutContext<CanvasSharedAction>
    {
        ShortcutContext<CanvasSharedAction>("canvas.shared") { action, dispatch in
            guard let t = holder.target else { return }
            switch action {
            case .rotateRight, .rotateLeft:
                if case let .continuous(magnitude) = dispatch {
                    // NSEvent's rotation is CCW-positive; SwiftUI rotationEffect
                    // is CW-positive. Negate, then scale for visible feedback.
                    t.rotation -= magnitude * 10
                }
            case .addRectangle:
                t.addObject(.rectangle(size: 60, fillIndex: t.currentFillIndex))
            case .addEllipse:
                t.addObject(.ellipse(size: 60, fillIndex: t.currentFillIndex))
            case .addText:
                t.addObject(.text(content: "Text", fontSize: 18, bold: false))
            case .deleteSelected:
                t.deleteSelected()
            case .selectNextObject:
                t.walkSelection(by: 1)
            case .selectPreviousObject:
                t.walkSelection(by: -1)
            }
        }
    }

    private static func makeSelectContext(_ holder: ModelHolder)
        -> ShortcutContext<SelectModeAction>
    {
        ShortcutContext<SelectModeAction>("canvas.select") { action, _ in
            guard let t = holder.target else { return }
            t.lastSelectTool = action
            t.statusLEDPulse += 1
        }
    }

    private static func makeFillContext(_ holder: ModelHolder)
        -> ShortcutContext<FillModeAction>
    {
        ShortcutContext<FillModeAction>("canvas.fill") { action, _ in
            guard let t = holder.target else { return }
            switch action {
            case .applyRed: t.currentFillIndex = 0
            case .applyBlue: t.currentFillIndex = 1
            case .applyGreen: t.currentFillIndex = 2
            }
            t.applyFillToSelection(t.currentFillIndex)
            t.statusLEDPulse += 1
        }
    }

    private static func makeStrokeContext(_ holder: ModelHolder)
        -> ShortcutContext<StrokeModeAction>
    {
        ShortcutContext<StrokeModeAction>("canvas.stroke") { action, _ in
            guard let t = holder.target else { return }
            switch action {
            case .thin: t.currentStrokeIndex = 0
            case .medium: t.currentStrokeIndex = 1
            case .thick: t.currentStrokeIndex = 2
            }
            t.statusLEDPulse += 1
        }
    }

    private static func makeTextContext(_ holder: ModelHolder)
        -> ShortcutContext<TextModeAction>
    {
        ShortcutContext<TextModeAction>("canvas.text") { action, _ in
            guard let t = holder.target else { return }
            switch action {
            case .serif: t.currentTextFontIndex = 0
            case .sans: t.currentTextFontIndex = 1
            case .mono: t.currentTextFontIndex = 2
            }
            t.statusLEDPulse += 1
        }
    }

    private static func makeShapeContext(_ holder: ModelHolder)
        -> ShortcutContext<ShapeModeAction>
    {
        ShortcutContext<ShapeModeAction>("canvas.shape") { action, _ in
            guard let t = holder.target else { return }
            t.lastShapeStamp = action
            switch action {
            case .square, .triangle:
                t.addObject(.rectangle(size: 60, fillIndex: t.currentFillIndex))
            case .circle:
                t.addObject(.ellipse(size: 60, fillIndex: t.currentFillIndex))
            }
            t.statusLEDPulse += 1
        }
    }

    private static func makeShapeSelectedContext(_ holder: ModelHolder)
        -> ShortcutContext<ShapeSelectedAction>
    {
        ShortcutContext<ShapeSelectedAction>("canvas.selection.shape") { action, _ in
            guard let t = holder.target else { return }
            switch action {
            case .sizeUp: t.resizeSelectedShape(by: 10)
            case .sizeDown: t.resizeSelectedShape(by: -10)
            case .cycleFill: t.cycleFillOnSelection()
            }
            t.statusLEDPulse += 1
        }
    }

    private static func makeTextSelectedContext(_ holder: ModelHolder)
        -> ShortcutContext<TextSelectedAction>
    {
        ShortcutContext<TextSelectedAction>("canvas.selection.text") { action, _ in
            guard let t = holder.target else { return }
            switch action {
            case .fontSizeUp: t.resizeSelectedText(by: 2)
            case .fontSizeDown: t.resizeSelectedText(by: -2)
            case .toggleBold: t.toggleBoldOnSelection()
            }
            t.statusLEDPulse += 1
        }
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

    private final class ModelHolder { weak var target: CanvasModeContextModel? }
}
