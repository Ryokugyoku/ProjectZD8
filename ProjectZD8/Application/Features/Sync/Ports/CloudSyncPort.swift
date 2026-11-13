import Foundation

/// iCloud(CloudKitプライベートデータベース)との同期の契約です。
///
/// 車両・整備記録・写真・セッション属性はレコード単位で自動同期します。
/// セッションのRawは終了後にアーカイブとして1回だけアップロードします。デモセッションは同期しません。
nonisolated protocol CloudSyncPort: Sendable {
    /// 責務: 同期を開始します。アプリ起動時に1回呼びます。
    func start() async
    /// 責務: 同期状態の変化を流すストリームを返します。購読開始時に現在の状態を1回流します。
    func statusUpdates() -> AsyncStream<CloudSyncStatus>
    /// 責務: 未送信の変更の送信と、リモート変更の取得を今すぐ行います。
    func syncNow() async throws
    /// 責務: `cloudOnly` のセッションのアーカイブをダウンロードして検証し、ローカルへ復元します。
    /// - Parameter progress: 0〜1の進捗を受け取るクロージャ。
    func restoreSessionArchive(_ id: SessionID, progress: @escaping @Sendable (Double) -> Void) async throws
    /// 責務: iCloud上とこの端末の全ユーザーデータを削除します。
    func eraseAllData() async throws
}

/// 同期の現在の状態です。
nonisolated enum CloudSyncStatus: Equatable, Sendable {
    /// iCloudにサインインしていない、または利用が制限されている。データはこの端末にだけ保存されます。
    case unavailable(CloudSyncUnavailableReason)
    /// 同期済みで待機中。
    case idle(lastSyncedAt: Date?)
    /// 送受信中。
    case syncing
    /// 直近の同期に失敗した。次の機会に自動で再試行します。
    case failed(CloudSyncFailure)
}

/// 同期を利用できない理由です。
nonisolated enum CloudSyncUnavailableReason: Equatable, Sendable {
    case noAccount
    case restricted
    case temporarilyUnavailable
}

/// 同期の失敗です。
nonisolated enum CloudSyncFailure: Error, Equatable, Sendable {
    case network
    case quotaExceeded
    /// ダウンロードしたアーカイブの検証に失敗した。
    case integrity
    case notFound
    case other
}
