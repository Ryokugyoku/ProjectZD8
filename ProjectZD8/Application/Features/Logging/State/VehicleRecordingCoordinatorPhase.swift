/// 記録の調停役が把握している、常駐リンク監視から依頼された記録の段階です。
///
/// 手動接続で始めた記録はここに現れません(常に `idle` のまま扱います)。
nonisolated enum VehicleRecordingCoordinatorPhase: Equatable, Sendable {
    /// 常駐リンク監視から依頼された記録はありません。
    case idle
    /// 依頼を受け、VINに一致する登録済み車両を照合しています。
    case resolvingVehicle
    /// 依頼された記録を開始し、テレメトリの終了を待っています。
    case recording
}
