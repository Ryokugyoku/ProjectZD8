import UserNotifications

/// 通知の許可状態から、監視通知を提示してよいかを決める方針です。
///
/// `UNUserNotificationCenter` には依存しないので、macOSのテストから検証できます。
nonisolated struct VehicleDetectionNotificationAuthorizationPolicy: Sendable {
    /// 許可状態で監視通知を提示してよいかを判定します。
    ///
    /// 責務: 許可済み・仮許可・一時許可だけを提示可能とし、拒否・未決定・未知の状態では提示させません。
    /// - Parameter status: 通知の許可状態。
    /// - Returns: 提示してよいなら `true`。
    func allowsPresentation(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }
}
