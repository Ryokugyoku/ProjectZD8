/// 整備記録の端末内保存を利用できない状態です。
enum MaintenanceRepositoryError: Error, Equatable {
    /// 製品データベースを準備できませんでした。
    case unavailable
}
