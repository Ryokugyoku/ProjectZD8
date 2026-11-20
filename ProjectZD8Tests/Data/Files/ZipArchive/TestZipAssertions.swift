import Foundation
import XCTest
@testable import ProjectZD8

/// ZIP の異常系の検証を、期限つきで行う補助です。
@MainActor
enum TestZipAssertions {
    /// 責務: ZIP を最後まで読み出し、期待した ZIP のエラーで終わることを期限つきで確かめます。
    /// - Parameters:
    ///   - zip: ZIP のバイト列。
    ///   - expected: 期待するエラー。
    ///   - testCase: 実行するテスト。
    ///   - inflater: 使う展開器。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    static func assertFails(
        _ zip: [UInt8], with expected: ZipArchiveError, on testCase: XCTestCase,
        inflater: ZipEntryInflater = ZipEntryInflater(),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let outcome = TestBoundedExecution.run(on: testCase, file: file, line: line) {
            TestZipExtraction.outcome(of: zip, inflater: inflater)
        }
        XCTAssertEqual(outcome, .zipError(expected), file: file, line: line)
    }

    /// 責務: ZIP を最後まで読み出し、候補のどれかの ZIP のエラーで終わることを期限つきで確かめます。
    /// - Parameters:
    ///   - zip: ZIP のバイト列。
    ///   - candidates: 許される ZIP のエラー。
    ///   - testCase: 実行するテスト。
    ///   - inflater: 使う展開器。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    static func assertFails(
        _ zip: [UInt8], withOneOf candidates: [ZipArchiveError], on testCase: XCTestCase,
        inflater: ZipEntryInflater = ZipEntryInflater(),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let outcome = TestBoundedExecution.run(on: testCase, file: file, line: line) {
            TestZipExtraction.outcome(of: zip, inflater: inflater)
        }
        guard case .zipError(let error)? = outcome else {
            XCTFail("ZIP のエラーで終わるはずが \(String(describing: outcome))", file: file, line: line)
            return
        }
        XCTAssertTrue(candidates.contains(error), "想定外のエラー: \(error)", file: file, line: line)
    }
}
