import Foundation

/// 走行セッションとRawサンプルの永続化契約です。Rawは追記のみで、更新しません。
nonisolated protocol SessionRepository: Sendable {
    /// 責務: セッションと取得条件(PID一覧)を1トランザクションで保存し、記録を開始します。
    func begin(_ session: DriveSession, pids: [SessionPID]) async throws
    /// 責務: 1ティック分のサンプルを1トランザクションで追記し、セッションの集計値を更新します。
    func append(_ samples: [SessionSample], to id: SessionID) async throws
    /// 責務: セッションの開始・終了距離とその観測元を記録します。
    func recordDistance(startKilometers: Double, endKilometers: Double, source: DistanceSource, for id: SessionID) async throws
    /// 責務: 記録中のセッションを終了状態にして返します。既に終了していれば `StoreError.invalidState` を投げます。
    func finish(_ id: SessionID, at date: Date, reason: SessionEndReason) async throws -> DriveSession
    /// 責務: 前回起動時に閉じられなかった全セッションを `appTerminated` で終了し、終了したセッションを返します。
    func finishUnfinishedSessions(at date: Date) async throws -> [DriveSession]
    /// 責務: 削除されていないセッションを開始日時の新しい順で返します。`vehicleID` が `nil` なら全車両分を返します。
    func sessions(for vehicleID: VehicleID?) async throws -> [DriveSession]
    /// 責務: IDに一致するセッションを返します。無ければ `nil` を返します。
    func session(_ id: SessionID) async throws -> DriveSession?
    /// 責務: セッションの取得条件を並び順どおりに返します。
    func pids(for id: SessionID) async throws -> [SessionPID]
    /// 責務: `afterSequence` より後のサンプルを通し番号順に最大 `limit` 件返します。先頭から読む場合は -1 を渡します。
    func samples(for id: SessionID, afterSequence: Int64, limit: Int) async throws -> [SessionSample]
    /// 責務: セッションを取得条件・サンプルごと削除します。
    func delete(_ id: SessionID) async throws
    /// 責務: この端末のサンプルだけを解放し、`rawAvailability` を `cloudOnly` にします。アーカイブ未アップロードなら `StoreError.invalidState` を投げます。
    func evictSamples(for id: SessionID) async throws
    /// 責務: アーカイブの内容でセッション・取得条件・サンプルを置き換え、`rawAvailability` を `local` にします。
    func importArchive(_ archive: SessionArchive) async throws
}
