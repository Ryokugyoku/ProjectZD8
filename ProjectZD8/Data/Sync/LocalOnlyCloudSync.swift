/// CloudKitに触れてはいけない環境(単体テストのホスト、iCloudエンタイトルメントの無い署名なしビルド)で使う同期です。
///
/// 常に `.unavailable(.temporarilyUnavailable)` を報告し、送受信と復元は `CloudSyncFailure.other` で失敗します。
/// 全データ削除はこの端末のデータだけを消去します。
nonisolated struct LocalOnlyCloudSync: CloudSyncPort {
    private let eraser: SyncLocalDataEraser

    /// 責務: 共有データベースと写真ストアだけを扱う同期を生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore) {
        self.eraser = SyncLocalDataEraser(database: database, photoFiles: photoFiles)
    }

    /// 責務: 何もしません(同期を開始しない)。
    func start() async {}

    /// 責務: 利用できない状態を1回流して終わるストリームを返します。
    func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        AsyncStream { continuation in
            continuation.yield(.unavailable(.temporarilyUnavailable))
            continuation.finish()
        }
    }

    /// 責務: 同期できないため失敗します。
    func syncNow() async throws {
        throw CloudSyncFailure.other
    }

    /// 責務: iCloudから取得できないため失敗します。
    func restoreSessionArchive(_ id: SessionID, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw CloudSyncFailure.other
    }

    /// 責務: この端末の全ユーザーデータを消去します。
    func eraseAllData() async throws {
        try eraser.eraseAll()
    }
}
