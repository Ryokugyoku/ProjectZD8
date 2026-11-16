#if os(iOS)
/// iOSのホームと車両画面で、車両を特定できなかったログの警告を表示するかを決める判定です。
enum IOSVehicleUnknownSessionWarningVisibility {
    /// 警告を表示するかどうかを返します。
    ///
    /// 責務: 表示対象の警告で、車両の識別・登録・編集の最中でない時だけ表示すると判定します。
    /// - Parameters:
    ///   - warning: 車両不明ログの警告。
    ///   - vehiclePhase: 車両管理の段階。
    /// - Returns: 表示するなら `true`。
    static func isVisible(warning: VehicleUnknownSessionWarning, vehiclePhase: VehicleManagementState.Phase) -> Bool {
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
