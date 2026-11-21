import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 位置記録Repositoryのテストが共有する、同一Queue上のRepository群と値生成の部品です。
struct GRDBConnectionSessionLocationFixtures {
    /// 接続セッションRepositoryの共有部品です(親セッションの保存と終了済みセッションの用意に使います)。
    let base: GRDBConnectionSessionRepositoryFixtures
    /// 検証対象の位置Repositoryです。
    let locations: GRDBConnectionSessionLocationRepository

    /// テストが直接SQLを流し込めるインメモリDB Queueです。
    var queue: DatabaseQueue { base.queue }
    /// 親セッションを保存するRepositoryです。
    var sessions: GRDBConnectionSessionRepository { base.repository }

    /// 空のDBへ接続セッションRepositoryと位置Repositoryを用意します。
    ///
    /// 責務: 同一Queue上に2つのRepositoryを作ります。
    /// - Throws: DB作成またはMigrationの失敗。
    init() throws {
        base = try GRDBConnectionSessionRepositoryFixtures()
        locations = try GRDBConnectionSessionLocationRepository(databaseQueue: base.queue)
    }

    /// 未終了の親セッションを保存してIDを返します。
    ///
    /// 責務: 位置の外部キー参照先となるセッションを1件追加します。
    /// - Parameter account: 所有アカウント識別子。
    /// - Returns: 保存済みのセッションID。
    /// - Throws: セッション保存の失敗。
    func seedSession(account: String = "account") throws -> ConnectionSessionID {
        let id = ConnectionSessionID()
        try sessions.save(ConnectionSession(id: id, accountIdentifier: account, startedAt: Date(timeIntervalSince1970: 100)))
        return id
    }

    /// 同じDBに対する別の位置Repositoryインスタンスを作ります。
    ///
    /// 責務: アプリの再起動や続行による復帰で、同じDBへ新しいRepositoryを作る状況を再現します。
    /// - Returns: 新しい位置Repository。
    /// - Throws: Repository生成の失敗。
    func makeRecreatedRepository() throws -> GRDBConnectionSessionLocationRepository {
        try GRDBConnectionSessionLocationRepository(databaseQueue: queue)
    }

    /// 指定セッションの位置行数と事象行数を数えます。
    ///
    /// 責務: Repositoryを介さず固定SQLで2表の行数を返します。
    /// - Parameter sessionID: 対象セッションID。
    /// - Returns: (位置の行数, 事象の行数)。
    /// - Throws: SQLite読込失敗。
    func rowCounts(for sessionID: ConnectionSessionID) throws -> (samples: Int, events: Int) {
        let key = sessionID.rawValue.uuidString.lowercased()
        return try queue.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_location_samples WHERE sessionID = ?", arguments: [key]) ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_location_events WHERE sessionID = ?", arguments: [key]) ?? -1
            )
        }
    }

    /// 全項目に値を持つ位置を生成します。
    ///
    /// 責務: マイクロ秒未満を含まない時刻と、指定項目だけ差し替えた既定値で1点の位置を返します。
    /// - Parameters:
    ///   - latitude: 緯度。
    ///   - longitude: 経度。
    ///   - observedAt: 観測時刻(マイクロ秒精度で正確に表せる値)。
    ///   - monotonic: 単調時計のナノ秒。
    /// - Returns: 不変条件を満たす位置。
    /// - Throws: 不変条件を満たさず生成できない場合の `XCTUnwrap` 失敗。
    static func fix(
        latitude: Double = 35.5,
        longitude: Double = 139.25,
        observedAt: Date = Date(timeIntervalSince1970: 2_000.5),
        monotonic: UInt64 = 5_000_000_123
    ) throws -> LocationFix {
        try XCTUnwrap(
            LocationFix(
                latitude: latitude, longitude: longitude, altitudeMeters: 12.5, horizontalAccuracyMeters: 4.5,
                verticalAccuracyMeters: 3.25, speedMetersPerSecond: 8.75, courseDegrees: 270.5,
                observedAt: observedAt, monotonicNanoseconds: monotonic
            )
        )
    }

    /// 任意項目をすべて `nil` にした位置を生成します。
    ///
    /// 責務: 標高・垂直精度・速度・進行方向が無い1点の位置を返します。
    /// - Parameter observedAt: 観測時刻(マイクロ秒精度で正確に表せる値)。
    /// - Returns: 任意項目が `nil` の位置。
    /// - Throws: 生成できない場合の `XCTUnwrap` 失敗。
    static func fixWithoutOptionals(observedAt: Date = Date(timeIntervalSince1970: 2_001.25)) throws -> LocationFix {
        try XCTUnwrap(
            LocationFix(
                latitude: -33.5, longitude: -70.25, altitudeMeters: nil, horizontalAccuracyMeters: 0,
                verticalAccuracyMeters: nil, speedMetersPerSecond: nil, courseDegrees: nil,
                observedAt: observedAt, monotonicNanoseconds: 0
            )
        )
    }
}
