#if os(iOS)
/// iOSのホームと車両画面で未登録車両の警告を表示するかどうかを判定します。
enum IOSUnassignedObservedVINWarningVisibility {
    /// 警告を表示するかどうかを返します。
    ///
    /// 責務: 警告の内容と車両管理の段階を、警告の表示可否へ変換します。識別・登録・編集の最中は重ねて表示しません。
    /// - Parameters:
    ///   - warning: 現在の未登録車両の警告。
    ///   - vehiclePhase: 現在の車両管理の段階。
    /// - Returns: 警告が表示対象で、車両の識別・確認・登録・編集の最中でない場合に `true`。
    static func isVisible(
        warning: UnassignedObservedVINWarning,
        vehiclePhase: VehicleManagementState.Phase
    ) -> Bool {
        guard warning.isVisible else { return false }
        switch vehiclePhase {
        case .identifying, .confirmingIdentification, .registering, .editing:
            return false
        case .idle, .loading, .readyToConnect, .failed:
            return true
        }
    }
}
#endif
