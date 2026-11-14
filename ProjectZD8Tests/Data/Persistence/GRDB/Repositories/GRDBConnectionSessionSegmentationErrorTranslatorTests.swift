import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionSegmentationErrorTranslator` の3分岐(素通し・制約違反・その他)を検証します。
final class GRDBConnectionSessionSegmentationErrorTranslatorTests: XCTestCase {
    /// テスト用の無関係なエラーです。
    private struct UnrelatedError: Error {}

    /// `ConnectionSessionRepositoryError` はそのまま返ります。
    ///
    /// 責務: 3つのケースがそれぞれ別のケースへ変換されないことを確認します。
    func testRepositoryErrorsPassThroughUnchanged() {
        let translator = GRDBConnectionSessionSegmentationErrorTranslator()

        for error in [ConnectionSessionRepositoryError.unavailable, .invalidState, .integrityConflict] {
            XCTAssertEqual(translator.repositoryError(for: error), error)
        }
    }

    /// SQLiteの制約違反は `integrityConflict` です。
    ///
    /// 責務: 主キー・外部キー・CHECKの実制約違反が `integrityConflict` になることを確認します。
    func testRealConstraintViolationsBecomeIntegrityConflict() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        try fixtures.queue.write { try fixtures.insertSegment($0) }
        let writes: [(Database) throws -> Void] = [
            { try fixtures.insertSegment($0) },
            { try fixtures.insertSegment($0, session: SegmentationSchemaFixtures.sessionB, ordinal: 1) },
            { try fixtures.insertSegment($0, ordinal: -1) }
        ]

        for write in writes {
            XCTAssertThrowsError(try fixtures.queue.write(write)) { error in
                XCTAssertEqual(
                    GRDBConnectionSessionSegmentationErrorTranslator().repositoryError(for: error),
                    .integrityConflict
                )
            }
        }
    }

    /// 制約違反以外のSQLiteエラーは `unavailable` です。
    ///
    /// 責務: BUSY・IOERR・汎用エラーのDatabaseErrorを制約違反扱いにしないことを確認します。
    func testNonConstraintDatabaseErrorsBecomeUnavailable() {
        let translator = GRDBConnectionSessionSegmentationErrorTranslator()

        for code in [ResultCode.SQLITE_BUSY, .SQLITE_IOERR, .SQLITE_ERROR, .SQLITE_READONLY, .SQLITE_FULL] {
            XCTAssertEqual(translator.repositoryError(for: DatabaseError(resultCode: code)), .unavailable, "\(code)")
        }
    }

    /// 合成した `SQLITE_CONSTRAINT` は `integrityConflict` です。
    ///
    /// 責務: 拡張コード付きを含む制約違反コードの分類を確認します。
    func testSyntheticConstraintDatabaseErrorBecomesIntegrityConflict() {
        let translator = GRDBConnectionSessionSegmentationErrorTranslator()

        for code in [ResultCode.SQLITE_CONSTRAINT, .SQLITE_CONSTRAINT_FOREIGNKEY, .SQLITE_CONSTRAINT_CHECK, .SQLITE_CONSTRAINT_PRIMARYKEY] {
            XCTAssertEqual(translator.repositoryError(for: DatabaseError(resultCode: code)), .integrityConflict, "\(code)")
        }
    }

    /// DatabaseError以外のエラーは `unavailable` です。
    ///
    /// 責務: 任意のSwiftエラーとNSErrorを成功や制約違反へ潰さないことを確認します。
    func testOtherErrorsBecomeUnavailable() {
        let translator = GRDBConnectionSessionSegmentationErrorTranslator()

        XCTAssertEqual(translator.repositoryError(for: UnrelatedError()), .unavailable)
        XCTAssertEqual(translator.repositoryError(for: NSError(domain: "test", code: 1)), .unavailable)
    }
}
