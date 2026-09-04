import Foundation

/// Returns a translation from Netmin's bundled strings and keeps the English source as a safe
/// fallback. English source text is used as the key so SwiftUI literals and AppKit-created views
/// share one localization catalogue.
func localized(_ english: String) -> String {
    #if NETMIN_SWIFTPM
    Bundle.module.localizedString(forKey: english, value: english, table: nil)
    #else
    Bundle.main.localizedString(forKey: english, value: english, table: nil)
    #endif
}

/// Formats a localized printf-style string with the user's current number and date conventions.
func localizedFormat(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: localized(english), locale: .current, arguments: arguments)
}
