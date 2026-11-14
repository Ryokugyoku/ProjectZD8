import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// セグメント・欠損・CANフレーム表の制約テストが共有する、全Migration適用済みDBと直接INSERTの部品です。
///
/// SQLは固定リテラルと引数バインドだけで組み立て、文字列連結・補間は使いません。
struct SegmentationSchemaFixtures {
    /// 1件目の親セッションIDです。
    static let sessionA = "00000000-0000-0000-0000-00000000000a"
    /// 2件目の親セッションIDです。
    static let sessionB = "00000000-0000-0000-0000-00000000000b"

    /// 全Migration適用済み・外部キー有効のインメモリDB Queueです。
    let queue: DatabaseQueue

    /// 全Migrationを適用した空DBを生成します。
    ///
    /// 責務: 1件のテスト専用DBを作り、外部キーが有効であることを前提として確認します。
    /// - Throws: DB作成またはMigrationの失敗。
    init() throws {
        queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)
        let foreignKeys = try queue.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") }
        XCTAssertEqual(foreignKeys, 1)
    }

    /// 親セッション行を挿入します。
    ///
    /// 責務: 未終了の1件の `connection_sessions` 行を固定SQLで追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - id: セッションID(小文字UUID文字列)。
    /// - Throws: SQLite書込み失敗。
    func insertSession(_ database: Database, id: String = sessionA) throws {
        try database.execute(
            sql: "INSERT INTO connection_sessions (id, accountIdentifier, startedAt) VALUES (?, 'account', ?)",
            arguments: [id, Date(timeIntervalSince1970: 100)]
        )
    }

    /// セグメント行を挿入します。
    ///
    /// 責務: 既定値が制約を満たす1件の `connection_session_segments` 行を、指定列だけ差し替えて追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - session: 親セッションID。
    ///   - ordinal: セグメント番号。
    ///   - startReason: 開始理由の保存値。
    ///   - mode: 取得モードの保存値。
    ///   - startedAt: 開始マイクロ秒。
    ///   - anchor: 単調時計アンカーのナノ秒。
    ///   - firstSequence: 先頭記録順序。
    ///   - endedAt: 終了マイクロ秒。
    ///   - endReason: 終了理由の保存値。
    ///   - lastSequence: 末尾記録順序。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    func insertSegment(
        _ database: Database,
        session: String = sessionA,
        ordinal: Int64 = 0,
        startReason: String = "initial",
        mode: String = "pidPolling",
        startedAt: Int64 = 1_000,
        anchor: Int64 = 0,
        firstSequence: Int64 = 0,
        endedAt: Int64? = nil,
        endReason: String? = nil,
        lastSequence: Int64? = nil
    ) throws {
        let values: [(any DatabaseValueConvertible)?] = [
            session, ordinal, startReason, mode, startedAt, anchor, firstSequence, endedAt, endReason, lastSequence
        ]
        try database.execute(
            sql: """
                INSERT INTO connection_session_segments
                (sessionID, segmentOrdinal, startReason, acquisitionMode, startedAtMicroseconds,
                 monotonicAnchorNanoseconds, firstSequence, endedAtMicroseconds, endReason, lastSequence)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 欠損行を挿入します。
    ///
    /// 責務: 既定値が制約を満たす1件の `connection_session_gaps` 行を、指定列だけ差し替えて追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - session: 親セッションID。
    ///   - ordinal: 欠損番号。
    ///   - preceding: 直前セグメント番号。
    ///   - following: 直後セグメント番号。
    ///   - startedAt: 開始マイクロ秒。
    ///   - endedAt: 終了マイクロ秒。
    ///   - cause: 原因の保存値。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    func insertGap(
        _ database: Database,
        session: String = sessionA,
        ordinal: Int64 = 0,
        preceding: Int64 = 0,
        following: Int64? = nil,
        startedAt: Int64 = 2_000,
        endedAt: Int64? = nil,
        cause: String = "linkLost"
    ) throws {
        let values: [(any DatabaseValueConvertible)?] = [session, ordinal, preceding, following, startedAt, endedAt, cause]
        try database.execute(
            sql: """
                INSERT INTO connection_session_gaps
                (sessionID, gapOrdinal, precedingSegmentOrdinal, followingSegmentOrdinal,
                 startedAtMicroseconds, endedAtMicroseconds, cause)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// CANフレーム行を挿入します。
    ///
    /// 責務: 既定値が制約を満たす1件の `connection_session_can_frames` 行を、指定列だけ差し替えて追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - session: 親セッションID。
    ///   - sequence: 記録順序。
    ///   - segment: 所属セグメント番号。
    ///   - identifier: CAN識別子。
    ///   - payload: payload。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    func insertFrame(
        _ database: Database,
        session: String = sessionA,
        sequence: Int64 = 0,
        segment: Int64 = 0,
        identifier: Int64 = 0x123,
        payload: Data = Data([0x01])
    ) throws {
        let values: [(any DatabaseValueConvertible)?] = [session, sequence, segment, 3_000, 10, identifier, payload]
        try database.execute(
            sql: """
                INSERT INTO connection_session_can_frames
                (sessionID, sequence, segmentOrdinal, receivedAtMicroseconds, monotonicNanoseconds,
                 canIdentifier, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 親セッションと0番の未終了セグメントを保存します。
    ///
    /// 責務: 欠損・フレーム・カスケードの試験が前提にする最小の親行を1回の書込みで用意します。
    /// - Throws: SQLite書込み失敗。
    func seedSessionWithSegment() throws {
        try queue.write { database in
            try insertSession(database)
            try insertSegment(database)
        }
    }

    /// 指定した書込みが制約違反(`SQLITE_CONSTRAINT`)で拒否されることを検証します。
    ///
    /// 責務: 書込みが成功や別種のエラーにならず、制約違反として失敗したことを確認します。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - body: 拒否されるべき書込み。
    func assertRejected(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: (Database) throws -> Void
    ) {
        XCTAssertThrowsError(try queue.write(body), file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT, "\(error)", file: file, line: line)
        }
    }

    /// 指定した表の行数を返します。
    ///
    /// 責務: 3つの対象表のうち1つの全行数を固定SQLで数えます。
    /// - Parameter table: 対象表。
    /// - Returns: 行数。
    /// - Throws: SQLite読込失敗。
    func rowCount(_ table: Table) throws -> Int {
        try queue.read { database in
            let sql: String
            switch table {
            case .segments: sql = "SELECT COUNT(*) FROM connection_session_segments"
            case .gaps: sql = "SELECT COUNT(*) FROM connection_session_gaps"
            case .canFrames: sql = "SELECT COUNT(*) FROM connection_session_can_frames"
            }
            return try Int.fetchOne(database, sql: sql) ?? -1
        }
    }

    /// 行数確認の対象表です。
    enum Table {
        /// `connection_session_segments`
        case segments
        /// `connection_session_gaps`
        case gaps
        /// `connection_session_can_frames`
        case canFrames
    }
}
