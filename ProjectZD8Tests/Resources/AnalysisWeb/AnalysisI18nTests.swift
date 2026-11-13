import XCTest
@testable import ProjectZD8

/// analysis-i18n.js の文言表を検証します。
final class AnalysisI18nTests: XCTestCase {
    private func dictionary() throws -> [String: [String: String]] {
        try AnalysisWebScriptRunner.evaluate("return DICTIONARY;", in: AnalysisWebScriptRunner.makeContext())
    }

    /// 責務: 3言語のキー集合が一致し、空の文言が無く、差し込み名も一致することを確認します。
    func testLanguagesAreComplete() throws {
        let dict = try dictionary()
        XCTAssertEqual(Set(dict.keys), ["ja", "en", "es"])
        let keys = Set(try XCTUnwrap(dict["en"]).keys)
        XCTAssertGreaterThan(keys.count, 150)
        for language in ["ja", "es"] { XCTAssertEqual(Set(try XCTUnwrap(dict[language]).keys), keys, language) }
        let placeholder = try NSRegularExpression(pattern: #"\{(\w+)\}"#)
        for key in keys {
            var names: [Set<String>] = []
            for language in ["ja", "en", "es"] {
                let text = try XCTUnwrap(dict[language]?[key])
                XCTAssertFalse(text.isEmpty, "\(language) \(key)")
                let range = NSRange(text.startIndex..., in: text)
                names.append(Set(placeholder.matches(in: text, range: range).map { String(text[Range($0.range(at: 1), in: text)!]) }))
            }
            XCTAssertEqual(names[0], names[1], key)
            XCTAssertEqual(names[1], names[2], key)
        }
    }

    /// 責務: スクリプトが参照する文言キーが全て表に存在することを確認します。
    func testEveryReferencedKeyExists() throws {
        let english = try XCTUnwrap(dictionary()["en"])
        let literal = try NSRegularExpression(pattern: #"\bt\('([A-Za-z0-9_.]+)'"#)
        var used = Set<String>()
        for name in AnalysisWebFiles.scripts {
            let source = try AnalysisWebScriptRunner.source(named: name)
            for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                used.insert(String(source[Range(match.range(at: 1), in: source)!]))
            }
        }
        XCTAssertGreaterThan(used.count, 100)
        for key in used { XCTAssertNotNil(english[key], "文言キーが未定義: \(key)") }
        // 動的に組み立てるキー。
        for key in ["segment.stop", "segment.idle", "segment.acceleration", "segment.cruise", "segment.deceleration",
                    "event.hardAcceleration", "event.hardBraking", "event.highCoolant", "event.fuelTrimExcursion", "event.rpmPeak",
                    "trends.all", "trends.warmIdle", "trends.steadyCruise", "derived.accel.name", "derived.ratio.desc", "derived.gear.name", "derived.trimsum.desc",
                    "view.overview", "view.timeseries", "view.scatter", "view.distribution", "view.maptable", "view.derived", "view.compare", "view.trends", "view.quality", "view.export"] {
            XCTAssertNotNil(english[key], key)
        }
        for failure in ["sessionNotFound", "vehicleNotFound", "rawUnavailable", "inconsistentRaw", "noSamples", "store", "downloadFailed", "tooManySessions", "encoding"] {
            XCTAssertNotNil(english["host.failure.\(failure)"], failure)
        }
    }

    /// 責務: 言語の解決・フォールバック・差し込みを確認します。
    func testTranslator() throws {
        let ctx = try AnalysisWebScriptRunner.makeContext()
        let r: [String] = try AnalysisWebScriptRunner.evaluate("""
            return [resolveLanguage('ja-JP'), resolveLanguage('es_MX'), resolveLanguage('fr'), resolveLanguage(null),
                    makeTranslator('es')('derived.added', { name: 'X' }), makeTranslator('en')('no.such.key'), makeTranslator('ja')('overview.lastService', { title: 'T', days: 3 })];
        """, in: ctx)
        XCTAssertEqual(r[0], "ja"); XCTAssertEqual(r[1], "es"); XCTAssertEqual(r[2], "en"); XCTAssertEqual(r[3], "en")
        XCTAssertEqual(r[4], "Se añadió \"X\"")
        XCTAssertEqual(r[5], "no.such.key")
        XCTAssertTrue(r[6].contains("T") && r[6].contains("3"))
    }

    /// 責務: Swift側のホストメッセージが使う失敗種別が、Web側の文言キーと対応することを確認します。
    func testFailureKindsMatchWebKeys() throws {
        let english = try XCTUnwrap(dictionary()["en"])
        let failures: [AnalysisFailure] = [.sessionNotFound, .vehicleNotFound, .rawUnavailable, .inconsistentRaw, .noSamples, .store, .downloadFailed(.network), .tooManySessions, .encoding]
        for failure in failures { XCTAssertNotNil(english["host.failure.\(failure.kind)"], failure.kind) }
    }
}
