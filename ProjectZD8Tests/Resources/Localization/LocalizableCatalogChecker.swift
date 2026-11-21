import Foundation
import XCTest
@testable import ProjectZD8

/// `Localizable.xcstrings` を JSON として読み、キーごとの訳の有無・書式指定子・未訳の写しを検証するテスト用の補助です。
struct LocalizableCatalogChecker {
    /// 検証する言語です。
    static let languages = ["ja", "en", "es"]

    /// カタログの `strings` です。
    private let strings: [String: Any]

    /// カタログを読み込みます。
    ///
    /// 責務: テストファイル位置からリポジトリ直下を求め、`Localizable.xcstrings` の `strings` を取り出します。
    init() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        strings = try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any], "strings が読めない")
    }

    /// 接頭辞で始まるカタログのキーを返します。
    ///
    /// 責務: カタログ側のキーを昇順で返します(製品コードのキーの取りこぼしを見つけるため)。
    func catalogKeys(prefix: String) -> [String] {
        strings.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// あるキー・言語の訳を返します。
    ///
    /// 責務: `stringUnit.value` を返し、無ければ複数形の `other` の値を返します。どちらも無ければ nil です。
    func translation(_ key: String, language: String) -> String? {
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        let entry = localizations?[language] as? [String: Any]
        if let value = (entry?["stringUnit"] as? [String: Any])?["value"] as? String { return value }
        let plural = (entry?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        return ((plural?["other"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// 全キーが、ja / en / es とも空でない訳を持つことを確かめます。
    ///
    /// 責務: キーの欠落・言語の欠落・空白だけの訳を XCTFail で報告します。
    func assertTranslated(_ keys: [String], file: StaticString = #filePath, line: UInt = #line) {
        for key in keys {
            XCTAssertNotNil(strings[key], "カタログに無い: \(key)", file: file, line: line)
            for language in Self.languages {
                let trimmed = translation(key, language: language)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                XCTAssertFalse(trimmed.isEmpty, "訳が無いか空: \(key) [\(language)]", file: file, line: line)
            }
        }
    }

    /// 書式指定子の種類と数が、ja / en / es で一致することを確かめます。
    ///
    /// 責務: 日本語の訳の指定子(`%@`・`%lld` など。`%%` は除く)の並べ替えた一覧を、en / es と比べます。
    func assertSameFormatSpecifiers(_ keys: [String], file: StaticString = #filePath, line: UInt = #line) {
        for key in keys {
            guard let japanese = translation(key, language: "ja") else { continue }
            let expected = Self.specifiers(in: japanese)
            for language in ["en", "es"] {
                let actual = Self.specifiers(in: translation(key, language: language) ?? "")
                XCTAssertEqual(actual, expected, "書式指定子が ja と違う: \(key) [\(language)]", file: file, line: line)
            }
        }
    }

    /// en / es の訳が、ja の文字列のままになっていないことを確かめます。
    ///
    /// 責務: 日本語の訳に日本語の文字(ひらがな・カタカナ・漢字)が含まれるキーだけを対象に、en / es が ja と同じなら失敗にします。
    /// 日本語の文字を含まない訳(固有名詞・記号だけ)は対象外です。
    func assertNotUntranslated(_ keys: [String], file: StaticString = #filePath, line: UInt = #line) {
        for key in keys {
            guard let japanese = translation(key, language: "ja"), Self.containsJapaneseCharacter(japanese) else { continue }
            for language in ["en", "es"] where translation(key, language: language) == japanese {
                XCTFail("ja のままの訳: \(key) [\(language)]", file: file, line: line)
            }
        }
    }

    /// キーの一覧が空でなく、重複しないことを確かめます。
    ///
    /// 責務: 製品コードから作った一覧が空や重複で形だけ通ることを防ぎます。
    func assertDistinct(_ keys: [String], expectedCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(keys.count, expectedCount, "キーの数", file: file, line: line)
        XCTAssertEqual(Set(keys).count, keys.count, "キーが重複している: \(keys)", file: file, line: line)
    }

    /// 訳の存在・書式指定子・ja のままでないことを、まとめて確かめます。
    ///
    /// 責務: 3つの検証を同じキーの一覧に適用します。
    func assertAll(_ keys: [String], file: StaticString = #filePath, line: UInt = #line) {
        assertTranslated(keys, file: file, line: line)
        assertSameFormatSpecifiers(keys, file: file, line: line)
        assertNotUntranslated(keys, file: file, line: line)
    }

    /// 文字列の書式指定子の一覧(長さ修飾+変換文字。並べ替え済み)を返します。
    ///
    /// 責務: `%@`・`%1$@`・`%lld`・`%.1f` などを取り出し、`%%` は除きます。位置の番号は比べません。
    static func specifiers(in text: String) -> [String] {
        let pattern = "%(?:\\d+\\$)?[-+ 0#]*\\d*(?:\\.\\d+)?((?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSp])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ["<invalid pattern>"] }
        let stripped = text.replacingOccurrences(of: "%%", with: "")
        let nsText = stripped as NSString
        let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: nsText.length))
        let result: [String] = matches.map { nsText.substring(with: $0.range(at: 1)) }
        return result.sorted()
    }

    /// 日本語の文字(ひらがな・カタカナ・漢字)を含むかを返します。
    ///
    /// 責務: 文字ごとの Unicode スカラーの範囲で判定します。
    static func containsJapaneseCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
}
