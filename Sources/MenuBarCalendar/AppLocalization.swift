import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static var isChinese: Bool {
        let preferredLanguage = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return preferredLanguage.lowercased().hasPrefix("zh")
    }
}
