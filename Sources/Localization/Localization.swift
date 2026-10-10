import Foundation
import Combine

/// App-owned copy only. Device, application, and plugin names are never translated.
enum L10n {
    private static let placeholderRegex = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
    static func text(_ key: String, _ arguments: [String] = [], language: String? = nil) -> String {
        let selected = language ?? UserDefaults.standard.string(forKey: "AudiomeeterLanguage") ?? "ja"
        var result = selected == "en" ? (EnglishCatalog.strings[key] ?? key) : (JapaneseCatalog.strings[key] ?? key)
        // Replace all placeholders in a single pass; argument contents are not templates.
        for match in placeholderRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let indexRange = Range(match.range(at: 1), in: result), let index = Int(result[indexRange]), arguments.indices.contains(index), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
}

final class LocalizationStore: ObservableObject {
    static let shared = LocalizationStore()
    @Published private(set) var language: String
    private init() { language = UserDefaults.standard.string(forKey: "AudiomeeterLanguage") == "en" ? "en" : "ja" }
    func select(_ next: String) {
        guard ["ja", "en"].contains(next), language != next else { return }
        UserDefaults.standard.set(next, forKey: "AudiomeeterLanguage")
        language = next
        NotificationCenter.default.post(name: .audiomeeterLanguageChanged, object: nil)
    }
}
extension Notification.Name {
    static let audiomeeterLanguageChanged = Notification.Name("AudiomeeterLanguageChanged")
}
