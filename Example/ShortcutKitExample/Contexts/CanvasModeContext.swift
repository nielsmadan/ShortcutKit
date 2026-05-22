import Combine
import ShortcutKit

enum CanvasModeAction: String, ShortcutAction {
    case primaryTool
    case secondaryTool
    case tertiaryTool
    case rotateRight
    case rotateLeft

    var definition: ShortcutActionDefinition {
        switch self {
        case .primaryTool: .init("Primary", Shortcut("b"))
        case .secondaryTool: .init("Secondary", Shortcut("g"))
        case .tertiaryTool: .init("Tertiary", Shortcut("e"))
        case .rotateRight:
            .init("Rotate Right", .continuous(.init(kind: .rotateClockwise, modifiers: [], sensitivity: 0.5)))
        case .rotateLeft:
            .init("Rotate Left", .continuous(.init(kind: .rotateCounterClockwise, modifiers: [], sensitivity: 0.5)))
        }
    }
}

@MainActor
final class CanvasModeContextModel: ObservableObject {
    @Published var activeMode: CanvasMode = .select
    @Published var lastFired: (mode: CanvasMode, action: CanvasModeAction)?
    @Published var statusLEDPulse = 0
    @Published var rotation: Double = 0

    let contexts: [CanvasMode: ShortcutContext<CanvasModeAction>]

    init() {
        let holder = ModelHolder()
        var built: [CanvasMode: ShortcutContext<CanvasModeAction>] = [:]
        for mode in CanvasMode.allCases {
            built[mode] = ShortcutContext<CanvasModeAction>("canvas.\(mode.rawValue)") { action, dispatch in
                guard let target = holder.target else { return }
                switch action {
                case .rotateRight:
                    if case let .continuous(magnitude) = dispatch {
                        target.rotation += magnitude * 180
                    }
                case .rotateLeft:
                    if case let .continuous(magnitude) = dispatch {
                        target.rotation -= magnitude * 180
                    }
                default:
                    target.lastFired = (mode, action)
                    target.statusLEDPulse += 1
                }
            }
        }
        contexts = built
        holder.target = self
    }

    // Safe force-unwrap: dict was built from CanvasMode.allCases so every case has an entry.
    func context(for mode: CanvasMode) -> ShortcutContext<CanvasModeAction> {
        contexts[mode]!
    }

    private final class ModelHolder { weak var target: CanvasModeContextModel? }
}
