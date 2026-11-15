import Foundation

/// 記録セッション終了後の後処理(アップロードとRawキャッシュの整理)の実行をOSへ予約します。
@MainActor
struct SchedulePostSessionProcessingUseCase {
    /// 実行をOSへ予約する境界です。
    private let scheduler: any PostSessionProcessingSchedulerPort
    /// 予約の成否を残す診断記録の境界です。
    private let diagnostics: any PostSessionProcessingDiagnosticsPort

    /// 予約の境界と診断記録の境界を固定して生成します。
    ///
    /// 責務: 予約要求をOSの予約境界と診断記録へ結び付けます。
    /// - Parameters:
    ///   - scheduler: 実行をOSへ予約する境界。
    ///   - diagnostics: 予約の成否を残す診断記録の境界。
    init(
        scheduler: any PostSessionProcessingSchedulerPort,
        diagnostics: any PostSessionProcessingDiagnosticsPort
    ) {
        self.scheduler = scheduler
        self.diagnostics = diagnostics
    }

    /// 後処理の実行を予約します。自動アップロードがオンのときだけネットワーク接続を実行条件にします。
    ///
    /// 責務: 自動アップロード設定を予約条件へ変換して予約し、成否を診断記録と呼び出し元へ返します。
    /// - Parameter automaticUploadEnabled: アカウントの自動アップロード設定がオンなら `true`。
    /// - Returns: 予約できた場合は `true`。OSが受け付けなかった場合は `false`(診断記録へ失敗を残します)。
    @discardableResult
    func execute(automaticUploadEnabled: Bool) -> Bool {
        do {
            try scheduler.schedule(requiresNetworkConnectivity: automaticUploadEnabled)
            diagnostics.scheduled()
            return true
        } catch {
            let nsError = error as NSError
            diagnostics.scheduleFailed(errorDomain: nsError.domain, errorCode: nsError.code)
            return false
        }
    }
}
