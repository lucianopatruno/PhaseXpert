import Foundation
import XCTest
@testable import PhaseXpert

final class LocalizationTests: XCTestCase {
    func testLanguageOptionsAndEnglishDefault() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "nb"])
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.norwegian.rawValue, "nb")
    }

    func testNorwegianCatalogCoversExtractedUserInterface() throws {
        let strings = try catalogStrings()
        XCTAssertGreaterThan(strings.count, 400)

        for key in [
            "Calculator", "Phase Diagram", "Saved Cases", "More", "Settings",
            "Language", "Appearance", "Calculate mixture", "Validation details",
            "Results and phase information", "About", "Property Sweep", "Stream Mixing"
        ] {
            let translation = try XCTUnwrap(norwegianTranslation(for: key, in: strings))
            XCTAssertFalse(translation.isEmpty)
            XCTAssertNotEqual(translation, key, "Expected a Bokmål translation for \(key)")
        }
    }

    func testScientificSymbolsAndUnitsArePreserved() throws {
        let strings = try catalogStrings()
        let protectedTokens = ["CO₂", "H₂O", "N₂", "O₂", "CH₄", "H₂", "H₂S", "Ar", "CO", "bar(a)", "MPa(a)", "ppm", "mol%"]

        for (key, entry) in strings {
            guard let entry = entry as? [String: Any] else { continue }
            guard let translation = norwegianTranslation(in: entry) else { continue }
            for token in protectedTokens where key.contains(token) {
                XCTAssertTrue(translation.contains(token), "\(token) changed in translation for \(key)")
            }
        }
    }

    func testUserFacingCatalogExcludesDevelopmentStylePhrases() throws {
        let serialized = try JSONSerialization.data(withJSONObject: try catalogStrings())
        let catalogText = String(decoding: serialized, as: UTF8.self).lowercased()
        for phrase in [
            "fall back", "fallback", "does not silently", "will not silently",
            "native bridge", "native abi", "unsafe high-level", "provider route",
            "provider path", "routing remains unchanged", "shipped interaction entries"
        ] {
            XCTAssertFalse(catalogText.contains(phrase), "User-facing catalog contains: \(phrase)")
        }
    }

    private func catalogStrings() throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let catalogURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "PhaseXpert/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    private func norwegianTranslation(for key: String, in strings: [String: Any]) -> String? {
        guard let entry = strings[key] as? [String: Any] else { return nil }
        return norwegianTranslation(in: entry)
    }

    private func norwegianTranslation(in entry: [String: Any]) -> String? {
        let localizations = entry["localizations"] as? [String: Any]
        let norwegian = localizations?["nb"] as? [String: Any]
        let unit = norwegian?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }
}
