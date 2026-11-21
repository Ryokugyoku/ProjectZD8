import Foundation
import GRDB

/// GRDBへ保存する位置サンプルの永続化表現です。
nonisolated struct ConnectionSessionLocationSampleRecord: Codable, FetchableRecord, PersistableRecord {
    /// 位置サンプル表名です。
    static let databaseTableName = "connection_session_location_samples"

    /// 親接続セッションUUIDの文字列表現です。
    let sessionID: String
    /// セッション内の位置の連番です。
    let sequence: Int64
    /// 位置が観測された実時間のmicrosecondです。
    let observedAtMicroseconds: Int64
    /// 位置が観測された時点の単調時計(ナノ秒)です。
    let monotonicNanoseconds: Int64
    /// 緯度(度)です。
    let latitude: Double
    /// 経度(度)です。
    let longitude: Double
    /// 標高(メートル)です。
    let altitudeMeters: Double?
    /// 水平精度(メートル)です。
    let horizontalAccuracyMeters: Double
    /// 垂直精度(メートル)です。
    let verticalAccuracyMeters: Double?
    /// 対地速度(メートル毎秒)です。
    let speedMetersPerSecond: Double?
    /// 進行方向(度)です。
    let courseDegrees: Double?

    /// Domainの位置をGRDB保存値へ変換します。
    ///
    /// 責務: 1点の位置を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - fix: 保存する位置。
    ///   - sequence: セッション内の連番。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 時刻や単調時計がInt64列へ表現できない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(fix: LocationFix, sequence: Int64, sessionID: ConnectionSessionID) throws {
        guard let monotonic = Int64(exactly: fix.monotonicNanoseconds) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        self.sessionID = sessionID.rawValue.uuidString.lowercased()
        self.sequence = sequence
        observedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: fix.observedAt)
        monotonicNanoseconds = monotonic
        latitude = fix.latitude
        longitude = fix.longitude
        altitudeMeters = fix.altitudeMeters
        horizontalAccuracyMeters = fix.horizontalAccuracyMeters
        verticalAccuracyMeters = fix.verticalAccuracyMeters
        speedMetersPerSecond = fix.speedMetersPerSecond
        courseDegrees = fix.courseDegrees
    }

    /// GRDB列からDomainの位置サンプルを復元します。
    ///
    /// 責務: 1件の保存済み位置を範囲と不変条件を検証してDomainへ復元します。
    /// - Returns: 復元した位置サンプル。
    /// - Throws: 範囲外の値や位置の不変条件違反は `ConnectionSessionRepositoryError.integrityConflict`。
    func makeDomainSample() throws -> ConnectionSessionLocationSample {
        guard sequence >= 0,
              let monotonic = UInt64(exactly: monotonicNanoseconds),
              let fix = LocationFix(
                  latitude: latitude,
                  longitude: longitude,
                  altitudeMeters: altitudeMeters,
                  horizontalAccuracyMeters: horizontalAccuracyMeters,
                  verticalAccuracyMeters: verticalAccuracyMeters,
                  speedMetersPerSecond: speedMetersPerSecond,
                  courseDegrees: courseDegrees,
                  observedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: observedAtMicroseconds),
                  monotonicNanoseconds: monotonic
              ) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationSample(sequence: sequence, fix: fix)
    }
}
