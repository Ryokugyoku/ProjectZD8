import GRDB

/// 同期対象テーブルへのローカル書き込みを検知します。
///
/// セッションは記録中にカウンター列が頻繁に更新されるため、同期の判定に関わる列だけを監視します。
nonisolated struct SyncLocalChangeMonitor: Sendable {
    private let database: AppDatabase

    /// 責務: 共有データベースを監視する監視器を生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 同期対象の行がコミットされるたびに要素を流すストリームを返します。購読開始時には流しません。
    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = DatabaseRegionObservation(tracking: [
            Table("vehicles"),
            Table("photos"),
            Table("maintenance_records"),
            Table("sessions").select(Column("modifiedAt"), Column("deletedAt"), Column("endedAt")),
        ])
        let cancellable = observation.start(in: database.writer, onError: { _ in
            continuation.finish()
        }, onChange: { _ in
            continuation.yield()
        })
        continuation.onTermination = { _ in cancellable.cancel() }
        return stream
    }
}
