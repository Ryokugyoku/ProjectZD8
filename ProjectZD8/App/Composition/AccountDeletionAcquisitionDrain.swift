import Foundation

/// アカウント削除の開始時に、自動アップロードを止め、PID継続取得の終了を上限付きで待つ配線です。
///
/// 取得の終了通知(`LiveTelemetryModel` の停止完了。接続セッションの保存はその完了時に同期で行われる)を、
/// 取得段階が接続中でなくなることで確認します。
@MainActor
final class AccountDeletionAcquisitionDrain: AccountDeletionAcquisitionDrainPort {
    /// 待ちの上限回数の既定値です。
    static let defaultMaximumPollCount = 300

    /// 待ちの間隔の既定値です。
    static let defaultPollInterval: Duration = .milliseconds(100)

    /// 終了を指示し、状態を確認するPID継続取得のモデルです。
    private let liveTelemetry: LiveTelemetryModel

    /// 終了で保存されるセッションが自動アップロードされないよう、アップロードを止める処理です。
    private let suspendAutomaticUpload: @MainActor () -> Void

    /// 待ちの上限回数です。
    private let maximumPollCount: Int

    /// 確認の間隔です。
    private let pollInterval: Duration

    /// 待機に使う処理です。テストは実時間を待たない実装を渡します。
    private let sleep: @Sendable (Duration) async throws -> Void

    /// 終了を待つ対象と上限を固定します。
    ///
    /// 責務: 取得モデルと自動アップロード停止処理、待ちの上限を結び付けます。
    /// - Parameters:
    ///   - liveTelemetry: 終了を指示するPID継続取得のモデル。
    ///   - suspendAutomaticUpload: 自動アップロードを止める処理。
    ///   - maximumPollCount: 待ちの上限回数。
    ///   - pollInterval: 確認の間隔。
    ///   - sleep: 待機に使う処理。
    init(
        liveTelemetry: LiveTelemetryModel,
        suspendAutomaticUpload: @escaping @MainActor () -> Void,
        maximumPollCount: Int = AccountDeletionAcquisitionDrain.defaultMaximumPollCount,
        pollInterval: Duration = AccountDeletionAcquisitionDrain.defaultPollInterval,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.liveTelemetry = liveTelemetry
        self.suspendAutomaticUpload = suspendAutomaticUpload
        self.maximumPollCount = maximumPollCount
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    /// 自動アップロードを止めて取得を終了させ、取得が接続中でなくなるまで上限付きで待ちます。
    ///
    /// 責務: 削除でクラウドへ再アップロードされないようにしてから、記録中の取得を `accountSignedOut` で終えます。
    /// - Throws: 上限までに終了を確認できない場合は `AccountDeletionAcquisitionDrainError.timedOut`。キャンセルされた場合は `CancellationError`。
    func endAcquisitionAndWaitUntilSaved() async throws {
        suspendAutomaticUpload()
        liveTelemetry.send(.endRequested(.accountSignedOut))
        for _ in 0..<maximumPollCount {
            if !liveTelemetry.state.isConnectionActive { return }
            try await sleep(pollInterval)
        }
        if !liveTelemetry.state.isConnectionActive { return }
        throw AccountDeletionAcquisitionDrainError.timedOut
    }
}

extension ApplicationRootModels {
    /// アカウント削除の開始時に取得を終わらせる待ちを、認証モデルへ結び付けます。
    ///
    /// 責務: 認証モデルへ取得終了待ちの境界を渡し、待ちの開始時に接続セッションと接続履歴の自動アップロードを止めます。
    func connectAccountDeletionDrain() {
        let lifecycle = connectionSessionLifecycle
        let history = connectionHistory
        authentication.acquisitionDrain = AccountDeletionAcquisitionDrain(liveTelemetry: liveTelemetry) {
            lifecycle.send(.automaticUploadChanged(false))
            history.send(.automaticUploadChanged(false))
        }
    }
}
