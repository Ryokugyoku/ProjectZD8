import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBRoadRegulationErrorTranslator` の分類(素通し・制約違反・SQLITE_FULL・その他)を検証します。
@MainActor
final class GRDBRoadRegulationErrorTranslatorTests: XCTestCase {
    private let translator = GRDBRoadRegulationErrorTranslator()

    /// テスト用の無関係なエラーです。
    private struct UnrelatedError: Error {}

    /// `RoadRegulationRepositoryError` はそのまま返ります。
    ///
    /// 責務: 4つのケースが別のケースへ変換されないことを確認します。
    func testRepositoryErrorsPassThroughUnchanged() {
        for error in [RoadRegulationRepositoryError.unavailable, .integrityConflict, .storageFull, .notFound] {
            XCTAssertEqual(translator.repositoryError(for: error), error)
        }
    }

    /// `SQLITE_FULL` は `storageFull` です。
    ///
    /// 責務: 容量不足が利用不能や制約違反に潰されないことを確認します。
    func testSQLiteFullBecomesStorageFull() {
        XCTAssertEqual(translator.repositoryError(for: DatabaseError(resultCode: .SQLITE_FULL)), .storageFull)
    }

    /// 制約違反(合成コードと実際の違反)は `integrityConflict` です。
    ///
    /// 責務: 拡張コード付きの合成エラーと、実表への CHECK 違反の挿入を確認します。
    func testConstraintViolationsBecomeIntegrityConflict() throws {
        for code in [ResultCode.SQLITE_CONSTRAINT, .SQLITE_CONSTRAINT_FOREIGNKEY, .SQLITE_CONSTRAINT_CHECK, .SQLITE_CONSTRAINT_UNIQUE] {
            XCTAssertEqual(translator.repositoryError(for: DatabaseError(resultCode: code)), .integrityConflict, "\(code)")
        }
        let rows = try RoadRegulationSchemaRows()
        XCTAssertThrowsError(try rows.queue.write { try rows.insert($0, RoadRegulationSchemaRows.Dataset(prefecture: 0)) }) {
            XCTAssertEqual(self.translator.repositoryError(for: $0), .integrityConflict)
        }
    }

    /// 制約違反と容量不足以外の SQLite エラー、DB 以外のエラーは `unavailable` です。
    ///
    /// 責務: BUSY・IOERR・汎用エラー・任意の Swift エラーが成功や制約違反にならないことを確認します。
    func testOtherErrorsBecomeUnavailable() {
        for code in [ResultCode.SQLITE_BUSY, .SQLITE_IOERR, .SQLITE_ERROR, .SQLITE_READONLY] {
            XCTAssertEqual(translator.repositoryError(for: DatabaseError(resultCode: code)), .unavailable, "\(code)")
        }
        XCTAssertEqual(translator.repositoryError(for: UnrelatedError()), .unavailable)
        XCTAssertEqual(translator.repositoryError(for: NSError(domain: "test", code: 1)), .unavailable)
    }
}
