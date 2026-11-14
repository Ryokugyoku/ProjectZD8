import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` のテスト群が共有するDB準備と期待エラー検証の部品です。
struct GRDBConnectionSessionRepositoryFixtures {
    /// テストが直接SQLを流し込めるインメモリDB Queueです。
    let queue: DatabaseQueue
    /// 検証対象のRepositoryです。
    let repository: GRDBConnectionSessionRepository

    /// 空のインメモリDBへRepositoryを生成します。
    ///
    /// 責務: 1件のテスト専用DBと検証対象Repositoryの組を返します。
    /// - Throws: DB作成またはMigrationの失敗。
    init() throws {
        queue = try DatabaseQueue()
        repository = try GRDBConnectionSessionRepository(databaseQueue: queue)
    }

    /// 指定Payloadを持つ未デコード応答を生成します。
    ///
    /// 責務: 1件のRaw応答観測値を固定値で組み立てます。
    /// - Parameters:
    ///   - payload: 応答データバイト。
    ///   - elapsed: バッチ経過ナノ秒。
    /// - Returns: 追記用のRaw応答観測値。
    static func observation(payload: [UInt8] = [0x01], elapsed: UInt64 = 1_000) -> OBDRawResponseObservation {
        OBDRawResponseObservation(
            observedAt: Date(timeIntervalSince1970: 1_000),
            batchElapsedNanoseconds: elapsed,
            request: OBDPIDRequest(service: 0x01, pid: 0x0C),
            payload: payload
        )
    }

    /// 終了済みのセッションを生成します。
    ///
    /// 責務: 開始と終了の日時が確定した1件のDomainセッションを返します。
    /// - Parameters:
    ///   - id: セッションID。
    ///   - account: 所有アカウント識別子。
    ///   - startedAt: 開始日時。
    /// - Returns: `userDisconnected` で終了済みのセッション。
    static func endedSession(
        id: ConnectionSessionID = ConnectionSessionID(),
        account: String = "account",
        startedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ConnectionSession {
        var session = ConnectionSession(id: id, accountIdentifier: account, startedAt: startedAt)
        session.endedAt = startedAt.addingTimeInterval(10)
        session.endReason = .userDisconnected
        return session
    }

    /// 指定件数のRaw応答を持つ終了済みセッションを保存します。
    ///
    /// 責務: 未終了で保存、追記、終了保存の順を実Repository経由で再現します。
    /// - Parameters:
    ///   - count: 追記するRaw応答数。Payloadは各 `[sequence]`。
    ///   - id: セッションID。
    ///   - account: 所有アカウント識別子。
    ///   - startedAt: 開始日時。
    /// - Returns: 保存済みの終了済みセッション。
    /// - Throws: 保存または追記の失敗。
    @discardableResult
    func seedEndedSession(
        rawCount count: Int,
        id: ConnectionSessionID = ConnectionSessionID(),
        account: String = "account",
        startedAt: Date = Date(timeIntervalSince1970: 100)
    ) throws -> ConnectionSession {
        let ended = Self.endedSession(id: id, account: account, startedAt: startedAt)
        try repository.save(ConnectionSession(id: id, accountIdentifier: account, startedAt: startedAt))
        for index in 0..<count {
            try repository.append(Self.observation(payload: [UInt8(index)]), to: id)
        }
        try repository.save(ended)
        return ended
    }

    /// 保存済み列をDomain補正なしで返します。
    ///
    /// 責務: Repositoryの表示補正を経由せず1件のセッション行を取得します。
    /// - Parameter id: 取得するセッションID。
    /// - Returns: 保存済みレコード。
    /// - Throws: 行が存在しない場合またはSQLite読込失敗。
    func storedRecord(_ id: ConnectionSessionID) throws -> ConnectionSessionRecord {
        try XCTUnwrap(try queue.read { try ConnectionSessionRecord.fetchOne($0, key: id.rawValue.uuidString.lowercased()) })
    }

    /// 保存済みセッションの1列を直接更新します。
    ///
    /// 責務: 不正値や期待外状態を作るため、指定SQLをCHECK制約込みで1件のセッション行へ実行します。
    /// - Parameters:
    ///   - assignments: `SET` 句の内容。
    ///   - id: 更新対象のセッションID。
    /// - Throws: SQLite更新失敗。
    func updateSessionRow(_ assignments: String, id: ConnectionSessionID) throws {
        try queue.write { database in
            try database.execute(
                sql: "UPDATE connection_sessions SET \(assignments) WHERE id = ?",
                arguments: [id.rawValue.uuidString.lowercased()]
            )
        }
    }

    /// CHECK制約を一時的に無効化して書込みます。
    ///
    /// 責務: スキーマ制約が通常は禁止する破損行を作るため、1回の書込み中だけCHECK制約を無視します。
    /// - Parameter body: 破損行を書き込む処理。
    /// - Throws: SQLite書込み失敗。
    func writeIgnoringCheckConstraints(_ body: (Database) throws -> Void) throws {
        try queue.inDatabase { database in
            try database.execute(sql: "PRAGMA ignore_check_constraints = ON")
        }
        defer {
            try? queue.inDatabase { database in
                try database.execute(sql: "PRAGMA ignore_check_constraints = OFF")
            }
        }
        try queue.write(body)
    }

    /// Raw行を範囲外の値で直接挿入します。
    ///
    /// 責務: Domainへ復元できない1件のRaw行を指定セッションへ追加します。
    /// - Parameters:
    ///   - id: 親セッションID。
    ///   - sequence: 挿入する記録順序。
    ///   - service: 挿入するService値。
    ///   - elapsed: 挿入する経過ナノ秒。
    /// - Throws: SQLite書込み失敗。
    func insertRawRow(_ id: ConnectionSessionID, sequence: Int64, service: Int, elapsed: Int64) throws {
        try writeIgnoringCheckConstraints { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_session_raw_logs
                    (sessionID, sequence, observedAt, batchElapsedNanoseconds, service, pid, payload)
                    VALUES (?, ?, '2026-01-01 00:00:00.000', ?, ?, 12, x'01')
                    """,
                arguments: [id.rawValue.uuidString.lowercased(), sequence, elapsed, service]
            )
        }
    }
}

/// 指定した期待エラーが投げられることを検証します。
///
/// 責務: 1件の式が期待エラー値と同じ値を投げたことを確認します。
/// - Parameters:
///   - expected: 期待するエラー値。
///   - expression: 実行する式。
///   - file: 失敗を報告するファイル。
///   - line: 失敗を報告する行。
func assertThrowsError<Expected: Error & Equatable>(
    _ expected: Expected,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () throws -> Void
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        XCTAssertEqual(error as? Expected, expected, file: file, line: line)
    }
}
