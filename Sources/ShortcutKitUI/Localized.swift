import Foundation

// Library chrome and adopter-supplied text belong to different localization bundles.
func uiString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

func shortcutKitUILocalizations() -> [String] {
    Bundle.module.localizations
}
