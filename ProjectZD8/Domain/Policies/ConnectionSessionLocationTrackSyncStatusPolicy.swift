/// ローカルの軌跡の水位と同期記録から、軌跡の同期状態を判定します。
///
/// 判定は上から順に適用します: 同期記録が restored → `restoredFromCloud` / ローカルが空 → `nothingToSync` /
/// 同期記録なし → `notUploaded` / 水位が等しい → `uploaded` / それ以外 → `changedSinceUpload`。
nonisolated struct ConnectionSessionLocationTrackSyncStatusPolicy: Sendable {
    /// 状態を持たない判定を作ります。
    ///
    /// 責務: 判定に必要な設定を持たない値を構築します。
    init() {}

    /// 軌跡の同期状態を返します。
    ///
    /// 責務: 水位と同期記録の組を、同期状態の1つへ分類します。
    /// - Parameters:
    ///   - localWatermark: ローカルの軌跡の現在の水位。
    ///   - record: 保存済みの同期記録。無ければ nil。
    /// - Returns: 同期状態。
    func status(
        localWatermark: ConnectionSessionLocationTrackWatermark,
        record: ConnectionSessionLocationTrackSyncRecord?
    ) -> ConnectionSessionLocationTrackSyncStatus {
        if let record, record.origin == .restored {
            return .restoredFromCloud(manifestDigest: record.manifestDigest)
        }
        if localWatermark.sampleCount == 0, localWatermark.eventCount == 0 {
            return .nothingToSync
        }
        guard let record else {
            return .notUploaded
        }
        if record.watermark == localWatermark {
            return .uploaded(manifestDigest: record.manifestDigest)
        }
        return .changedSinceUpload(previousDigest: record.manifestDigest)
    }
}
