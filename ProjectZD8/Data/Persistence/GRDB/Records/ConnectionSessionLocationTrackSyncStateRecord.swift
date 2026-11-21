import Foundation
import GRDB

/// GRDBへ保存する走行ルートの同期記録の永続化表現です。
nonisolated struct ConnectionSessionLocationTrackSyncStateRecord: Codable, FetchableRecord, PersistableRecord {
    /// 同期記録表名です。
    static let databaseTableName = "connection_session_location_track_sync_states"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// 同期記録の由来のrawValueです。
    let origin: String
    /// iCloudへ保存したAssetバイト列のSHA-256(小文字16進)です。
    let manifestDigest: String
    /// 同期時点のサンプル件数です。
    let sampleCount: Int64
    /// 同期時点の最後のサンプルsequenceです。
    let lastSampleSequence: Int64?
    /// 同期時点の事象件数です。
    let eventCount: Int64
    /// 同期時点の最後の事象ordinalです。
    let lastEventOrdinal: Int64?
    /// 同期した時刻のmicrosecondです。
    let syncedAtMicroseconds: Int64

    /// Domainの同期記録をGRDB保存値へ変換します。
    ///
    /// 責務: 1件の同期記録を列指向の永続化表現へ変換します。
    /// - Parameter record: 保存する同期記録。
    /// - Throws: 時刻がInt64列へ表現できない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(_ record: ConnectionSessionLocationTrackSyncRecord) throws {
        sessionID = record.sessionID.rawValue.uuidString.lowercased()
        origin = record.origin.rawValue
        manifestDigest = record.manifestDigest
        sampleCount = Int64(record.watermark.sampleCount)
        lastSampleSequence = record.watermark.lastSampleSequence
        eventCount = Int64(record.watermark.eventCount)
        lastEventOrdinal = record.watermark.lastEventOrdinal.map(Int64.init)
        syncedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: record.syncedAt)
    }

    /// GRDB列からDomainの同期記録を復元します。
    ///
    /// 責務: 1件の保存済み同期記録をIDと由来と件数の範囲を検証してDomainへ復元します。
    /// - Returns: 復元した同期記録。
    /// - Throws: 不正なUUID・未知の由来・範囲外の件数は `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainRecord() throws -> ConnectionSessionLocationTrackSyncRecord {
        guard let uuid = UUID(uuidString: sessionID),
              let origin = ConnectionSessionLocationTrackSyncOrigin(rawValue: origin),
              let samples = Int(exactly: sampleCount),
              let events = Int(exactly: eventCount),
              samples >= 0, events >= 0 else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationTrackSyncRecord(
            sessionID: ConnectionSessionID(rawValue: uuid),
            origin: origin,
            manifestDigest: manifestDigest,
            watermark: ConnectionSessionLocationTrackWatermark(
                sampleCount: samples,
                lastSampleSequence: lastSampleSequence,
                eventCount: events,
                lastEventOrdinal: try lastEventOrdinal.map(Self.ordinal)
            ),
            syncedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: syncedAtMicroseconds)
        )
    }

    /// Int64のordinalをIntへ変換します。
    ///
    /// 責務: Intで表現できない値を整合性エラーにします。
    private static func ordinal(_ value: Int64) throws -> Int {
        guard let converted = Int(exactly: value) else { throw ConnectionSessionRepositoryError.integrityConflict }
        return converted
    }
}
