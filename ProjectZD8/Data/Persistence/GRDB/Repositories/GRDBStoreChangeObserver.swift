import GRDB

/// GRDBの `DatabaseRegionObservation` で永続化データの変更を通知します。
nonisolated struct GRDBStoreChangeObserver: StoreChangeObserving {
    private let database: AppDatabase

    /// 責務: 共有データベースを監視するオブザーバーを生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 指定領域のテーブルへ書き込みが確定するたびに要素を流します。購読開始時には流さず、読み取り失敗時はストリームを終了します。
    func changes(in areas: Set<StoreArea>) -> AsyncStream<Void> {
        let tables = Set(areas.flatMap(Self.tables(of:))).sorted()
        let writer = database.writer
        return AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard !tables.isEmpty else {
                continuation.finish()
                return
            }
            let observation = DatabaseRegionObservation(tracking: tables.map { Table($0) })
            let cancellable = observation.start(
                in: writer,
                onError: { _ in continuation.finish() },
                onChange: { _ in continuation.yield() }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// 責務: 領域が対象とするテーブル名を返します。
    private static func tables(of area: StoreArea) -> [String] {
        switch area {
        case .vehicles: ["vehicles"]
        case .pidSettings: ["vehicle_pid_settings"]
        case .maintenance: ["maintenance_records"]
        case .photos: ["photos"]
        case .sessions: ["sessions", "session_pids", "session_samples"]
        }
    }
}
