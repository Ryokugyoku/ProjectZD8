@testable import ProjectZD8

/// 後処理の予約要求を記録し、指定があれば予約を失敗させる spy です。
@MainActor
final class PostSessionProcessingSchedulerSpy: PostSessionProcessingSchedulerPort {
    /// 予約要求ごとの `requiresNetworkConnectivity` です。失敗した要求も含みます。
    private(set) var requiresNetworkConnectivityRequests: [Bool] = []

    /// 予約で投げるエラーです。`nil` なら予約は成功します。
    var error: (any Error)?

    /// 責務: 予約要求を記録し、指定されたエラーがあれば投げます。
    /// - Parameter requiresNetworkConnectivity: ネットワーク接続を実行条件にするかどうか。
    /// - Throws: `error` が設定されている場合はそのエラー。
    func schedule(requiresNetworkConnectivity: Bool) throws {
        requiresNetworkConnectivityRequests.append(requiresNetworkConnectivity)
        if let error { throw error }
    }
}
