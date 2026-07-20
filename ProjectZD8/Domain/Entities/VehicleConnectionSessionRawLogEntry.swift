import Foundation

/// 車両別学習抽出でセッション境界を保持する未デコードRawログです。
struct VehicleConnectionSessionRawLogEntry: Equatable, Sendable {
    /// ログを所有する登録車両IDです。
    let vehicleID: VehicleID
    /// ログを所有する接続セッションIDです。
    let sessionID: ConnectionSessionID
    /// セッションの開始日時です。
    let sessionStartedAt: Date
    /// セッション内順序を保持する未デコード応答です。
    let entry: ConnectionSessionRawLogEntry

    /// 車両、セッション、Raw応答を1件の学習抽出値として生成します。
    ///
    /// 責務: 1件のRaw応答へ車両とセッションの安定した所属情報を付与します。
    /// - Parameters:
    ///   - vehicleID: ログを所有する登録車両ID。
    ///   - sessionID: ログを所有する接続セッションID。
    ///   - sessionStartedAt: セッション開始日時。
    ///   - entry: セッション内順序を保持する未デコード応答。
    init(
        vehicleID: VehicleID,
        sessionID: ConnectionSessionID,
        sessionStartedAt: Date,
        entry: ConnectionSessionRawLogEntry
    ) {
        self.vehicleID = vehicleID
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.entry = entry
    }
}
