import Foundation
import Toml

/// A TOML key path whose components remain distinct from dotted key syntax.
public struct TOMLPath: Sendable, Hashable, ExpressibleByArrayLiteral, CustomStringConvertible {
    public let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public init(arrayLiteral elements: String...) {
        components = elements
    }

    public var description: String {
        components.map(Self.render).joined(separator: ".")
    }

    public func appending(_ component: String) -> Self {
        Self(components + [component])
    }

    private static func render(_ component: String) -> String {
        guard !component.isEmpty, component.unicodeScalars.allSatisfy({
            ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z")
                || ($0 >= "0" && $0 <= "9") || $0 == "_" || $0 == "-"
        }) else {
            return Toml.encode(.string(component))
        }
        return component
    }
}
