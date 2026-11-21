import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 軌跡の同期Repositoryのテストが共有する、同一Queue上のRepository群と前準備の部品です。
struct GRDBConnectionSessionLocationTrackSyncFixtures {
    /// 位置・事象Repositoryと親セッションRepositoryを持つ共有部品です。
    let location: GRDBConnectionSessionLocationFixtures
    /// 検証対象の同期Repositoryです。
    let sync: GRDBConnectionSessionLocationTrackSyncRepository

    /// テストが直接SQLを流し込めるインメモリDB Queueです。
    var queue: DatabaseQueue { location.queue }

    /// 空のDBへ同期Repositoryを用意します。
    ///
    /// 責務: 同一Queue上に位置Repositoryと同期Repositoryを作ります。
    /// - Throws: DB作成またはMigrationの失敗。
    init() throws {
        location = try GRDBConnectionSessionLocationFixtures()
        sync = try GRDBConnectionSessionLocationTrackSyncRepository(databaseQueue: location.queue)
    }

    /// 位置と事象を追記した、終了済み(または未終了)のセッションを保存します。
    ///
    /// 責務: 未終了で保存し、行を追記し、必要なら終了済みで保存し直します。
    /// - Parameters:
    ///   - account: 所有アカウント識別子。
    ///   - samples: 追記する位置の件数。
    ///   - events: 追記する事象の件数。
    ///   - ended: 終了済みにするか。
    /// - Returns: 保存したセッションID。
    /// - Throws: 保存または追記の失敗。
    @discardableResult
    func seedSession(
        account: String = "account",
        samples: Int = 0,
        events: Int = 0,
        ended: Bool = true
    ) throws -> ConnectionSessionID {
        let id = try location.seedSession(account: account)
        try appendRows(to: id, samples: samples, events: events)
        if ended {
            try location.sessions.save(GRDBConnectionSessionRepositoryFixtures.endedSession(id: id, account: account))
        }
        return id
    }

    /// 段階1のRepository経由で位置と事象を追記します。
    ///
    /// 責務: 位置を `samples` 件、事象を `events` 件、番号 0 から追記します。
    /// - Parameters:
    ///   - id: 対象セッションID。
    ///   - samples: 位置の件数。
    ///   - events: 事象の件数。
    /// - Throws: 追記の失敗。
    func appendRows(to id: ConnectionSessionID, samples: Int, events: Int) throws {
        for index in 0..<samples {
            try location.locations.appendSample(try ConnectionSessionLocationTrackValueFixtures.fix(index), for: id)
        }
        for index in 0..<events {
            try location.locations.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 3_000 + Double(index)), for: id)
        }
    }

    /// 同期記録の行を、Repositoryを介さずに直接挿入します。
    ///
    /// 責務: 固定SQLと引数バインドで `connection_session_location_track_sync_states` へ1行追加します。
    /// - Parameter record: 挿入する同期記録。
    /// - Throws: SQLite書込み失敗。
    func insertSyncRow(_ record: ConnectionSessionLocationTrackSyncRecord) throws {
        let mark = record.watermark
        let values: [(any DatabaseValueConvertible)?] = [
            record.sessionID.rawValue.uuidString.lowercased(), record.origin.rawValue, record.manifestDigest,
            mark.sampleCount, mark.lastSampleSequence, mark.eventCount, mark.lastEventOrdinal,
            Int64(record.syncedAt.timeIntervalSince1970 * 1_000_000)
        ]
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_session_location_track_sync_states
                    (sessionID, origin, manifestDigest, sampleCount, lastSampleSequence, eventCount, lastEventOrdinal, syncedAtMicroseconds)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: StatementArguments(values)
            )
        }
    }

    /// 同期記録テーブルの全行数を数えます。
    ///
    /// 責務: Repositoryを介さず固定SQLで行数を返します。
    /// - Returns: 行数。
    /// - Throws: SQLite読込失敗。
    func syncRowCount() throws -> Int {
        try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_track_sync_states") ?? -1 }
    }
}
