import Foundation
@main struct LocalizationTests {
    static func main() {
        precondition(L10n.text("閉じる", language: "en") == "Close")
        precondition(L10n.text("閉じる", language: "ja") == "閉じる")
        precondition(L10n.text("Mute", language: "ja") == "Mute")
        precondition(L10n.text("{0} フェーダー", ["A1"], language: "en") == "A1 fader")
        precondition(L10n.text("{0} フェーダー", ["{1}"], language: "en") == "{1} fader", "Arguments must not be interpreted as placeholders")
        for (key, value) in EnglishCatalog.strings {
            precondition(!value.isEmpty)
            let placeholder = try! NSRegularExpression(pattern: #"\{[0-9]+\}|%[.0-9]*[df]"#)
            func parameters(_ text: String) -> [String] {
                placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }.sorted()
            }
            precondition(parameters(key) == parameters(value), "Translation changed format arguments: \(key)")
            precondition(value.range(of: #"[ぁ-んァ-ヶ一-龯]"#, options: .regularExpression) == nil, "Japanese leaked into English: \(key)")
        }
        print("Localization tests passed: Japanese/English labels, templates, argument integrity, complete English catalog")
    }
}
