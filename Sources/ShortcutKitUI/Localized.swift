import Foundation

/// Resolves one of ShortcutKitUI's built-in (chrome) strings against the
/// package's own bundle, so the library ships and uses its own translations —
/// the same approach Sparkle and sindresorhus/KeyboardShortcuts take — rather
/// than resolving against the host app's main bundle.
///
/// Adopter-supplied strings (action/context `displayName`/`description`, which
/// are `LocalizedStringResource`s the adopter created) are deliberately **not**
/// routed here: those resolve against the adopter's own bundle.
///
/// The string is pre-resolved to a `String` so it can be passed uniformly into
/// SwiftUI controls (`Text`, `Button`, `Toggle`, `Section`, `Picker`,
/// `TextField`, `alert`), whose `LocalizedStringKey` initializers otherwise each
/// resolve against `Bundle.main` and don't thread a bundle the same way.
func uiString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Test seam: the localizations bundled with ShortcutKitUI. Confirms the String
/// Catalog resource is packaged (`Bundle.module` here is ShortcutKitUI's bundle).
func shortcutKitUILocalizations() -> [String] {
    Bundle.module.localizations
}
