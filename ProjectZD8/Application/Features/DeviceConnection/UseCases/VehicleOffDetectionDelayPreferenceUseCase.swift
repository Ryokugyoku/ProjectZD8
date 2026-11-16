/// 「エンジン停止とみなす時間」の設定を読み書きします。
struct VehicleOffDetectionDelayPreferenceUseCase {
    /// 設定の保存境界です。
    private let preferencePort: any VehicleOffDetectionDelayPreferencePort

    /// 保存境界を注入して生成します。
    ///
    /// 責務: 設定の読み書きを1件の保存境界へ結び付けます。
    /// - Parameter preferencePort: 設定の保存境界。
    init(preferencePort: any VehicleOffDetectionDelayPreferencePort) {
        self.preferencePort = preferencePort
    }

    /// 現在の設定を返します。
    ///
    /// 責務: 設定の読込を保存境界へ委譲します。
    /// - Returns: 保存済みの時間。
    func load() -> VehicleOffDetectionDelay {
        preferencePort.load()
    }

    /// 設定を保存します。
    ///
    /// 責務: 1件の設定の保存を保存境界へ委譲します。実行中の取得には反映せず、次回の取得開始から反映されます。
    /// - Parameter delay: 保存する時間。
    func save(_ delay: VehicleOffDetectionDelay) {
        preferencePort.save(delay)
    }
}
