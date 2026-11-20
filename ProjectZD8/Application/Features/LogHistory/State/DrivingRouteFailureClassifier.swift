/// 走行ルートの読み込みの失敗を、出す文言と再試行の可否へ分類します。
///
/// 取消(`CancellationError`)はモデルの側で無視するので、ここでは分類しません(渡されれば一般の失敗として扱います)。
nonisolated struct DrivingRouteFailureClassifier: Sendable {
    /// 読み込みの失敗を分類します。
    ///
    /// 責務: 新しい版のアプリが作った軌跡は「アプリの更新が必要」(再試行不可)、それ以外は「読み込めませんでした」(再試行可)にします。
    /// - Parameter error: 読み込みで投げられた失敗。
    /// - Returns: 文言キーと再試行の可否。
    func failure(for error: any Error) -> DrivingRouteFailure {
        if case .unsupportedPayloadFormat = error as? ConnectionSessionLocationTrackCloudError {
            return DrivingRouteFailure(messageKey: "history.route.failure.update_required", isRetryable: false)
        }
        return DrivingRouteFailure(messageKey: "history.route.failure.load", isRetryable: true)
    }
}
