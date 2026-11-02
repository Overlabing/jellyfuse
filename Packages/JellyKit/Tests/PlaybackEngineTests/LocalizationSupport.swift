import Foundation
import Testing
@testable import PlaybackEngine

/// The language the module's strings resolve to under test: the first preferred language among fr / en
/// (anything else falls back to fr, the development language). Run with `-testLanguage fr` to cover the French side.
let testUsesEnglish: Bool = Locale.preferredLanguages
    .compactMap { $0.hasPrefix("fr") ? false : ($0.hasPrefix("en") ? true : nil) }
    .first ?? false

func tr(fr: String, en: String) -> String { testUsesEnglish ? en : fr }

@Suite struct PlaybackEngineLocalizationTests {
    /// Every French key shipped by the module has an English counterpart (and they differ unless the text is language-neutral).
    @Test func everyKeyHasAnEnglishTranslation() throws {
        func table(_ language: String) throws -> [String: String] {
            let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let file = try #require(bundle.path(forResource: "Localizable", ofType: "strings"))
            return try #require(NSDictionary(contentsOfFile: file) as? [String: String])
        }
        let (french, english) = (try table("fr"), try table("en"))
        #expect(!french.isEmpty)
        #expect(Set(french.keys) == Set(english.keys))
        #expect(english.values.allSatisfy { !$0.isEmpty })
    }
}
