/// 「エンジン停止とみなす時間」を端末ローカルに保持する保存境界です。
///
/// 取得ループが取得開始時点に読むため、メインアクター以外からも呼べます。
nonisolated protocol VehicleOffDetectionDelayPreferencePort: Sendable {
    /// 保存済みの時間を読み込みます。
    ///
    /// 責務: 端末ローカルに保存された時間を1件返します。
    /// - Returns: 保存済みの時間。未保存または解釈できない値の場合は `VehicleOffDetectionDelay.standard`。
    func load() -> VehicleOffDetectionDelay

    /// 時間を保存します。
    ///
    /// 責務: 1件の時間を端末ローカルへ置き換えて保存します。
    /// - Parameter delay: 保存する時間。
    func save(_ delay: VehicleOffDetectionDelay)
}
