import Foundation

/// 記録セッション終了後の後処理を、Rawのアップロード → 走行ルートのアップロード → Rawキャッシュの整理の順に1回実行します。
///
/// 順序はRawを端末から消す整理の前にCloudKitへの保存を確かめるためです。整理の対象は保存が確認できた
/// (`cloudState == .uploaded` かつ manifest digest あり)終了済みセッションだけなので、アップロードを先に行うと、
/// 送信待ちだったセッションもこの実行の中で整理の対象になり得ます(詳細は `PostSessionProcessingStep`)。
///
/// 処理本体は既存の `SynchronizeConnectionSessionsUseCase`(送信待ちを含む同期)と
/// `EvictStaleConnectionSessionRawLogsUseCase` で、この型は実行条件・順序・結果・再予約だけを決めます。
/// 呼び出し元(OSのバックグラウンド実行)は期限切れのときこの処理の `Task` をキャンセルします。
@MainActor
struct RunPostSessionProcessingUseCase {
    /// 記録中(PID継続取得の接続中段階)かどうかを返す処理です。
    private let isRecordingActive: @MainActor () -> Bool
    /// サインイン中アカウントの識別子を返す処理です。解決できなければ `nil` を返します。
    private let resolveAccountIdentifier: @MainActor () async -> String?
    /// 指定アカウントの自動アップロード設定がオンかどうかを返す処理です。
    private let isAutomaticUploadEnabled: @MainActor (String) -> Bool
    /// 指定アカウントの送信待ちセッションをアップロードする処理です。
    private let upload: @MainActor (String) async throws -> Void
    /// 指定アカウントの未送信の走行ルート(位置の軌跡)をアップロードする処理です。
    private let uploadLocationTracks: @MainActor (String) async throws -> Void
    /// 指定アカウントの保持期限切れRawキャッシュを整理する処理です。
    private let evictStaleRawLogs: @MainActor (String) throws -> Void
    /// 未完了のとき次回の実行を予約するユースケースです。
    private let schedule: SchedulePostSessionProcessingUseCase
    /// 実行の経過を残す診断記録の境界です。
    private let diagnostics: any PostSessionProcessingDiagnosticsPort

    /// 実行条件の取得元・各ステップ・再予約・診断記録を固定して生成します。
    ///
    /// 責務: 後処理の各判断を、注入された狭い処理と既存ユースケースへの結び付けで構成します。
    /// - Parameters:
    ///   - isRecordingActive: 記録中なら `true` を返す処理(`LiveTelemetryState.isConnectionActive` 相当)。
    ///   - resolveAccountIdentifier: サインイン中アカウントの識別子を返す処理。解決できなければ `nil`。
    ///   - isAutomaticUploadEnabled: 指定アカウントの自動アップロード設定を返す処理。
    ///   - upload: 送信待ちを含む同期を行う処理(`SynchronizeConnectionSessionsUseCase` へ結び付けます)。
    ///   - uploadLocationTracks: 未送信の走行ルートをアップロードする処理(自動アップロードがオンの時だけ実行されます)。
    ///   - evictStaleRawLogs: Rawキャッシュを整理する処理(`EvictStaleConnectionSessionRawLogsUseCase` へ結び付けます)。
    ///   - schedule: 未完了のとき次回の実行を予約するユースケース。
    ///   - diagnostics: 実行の経過を残す診断記録の境界。
    init(
        isRecordingActive: @escaping @MainActor () -> Bool,
        resolveAccountIdentifier: @escaping @MainActor () async -> String?,
        isAutomaticUploadEnabled: @escaping @MainActor (String) -> Bool,
        upload: @escaping @MainActor (String) async throws -> Void,
        uploadLocationTracks: @escaping @MainActor (String) async throws -> Void,
        evictStaleRawLogs: @escaping @MainActor (String) throws -> Void,
        schedule: SchedulePostSessionProcessingUseCase,
        diagnostics: any PostSessionProcessingDiagnosticsPort
    ) {
        self.isRecordingActive = isRecordingActive
        self.resolveAccountIdentifier = resolveAccountIdentifier
        self.isAutomaticUploadEnabled = isAutomaticUploadEnabled
        self.upload = upload
        self.uploadLocationTracks = uploadLocationTracks
        self.evictStaleRawLogs = evictStaleRawLogs
        self.schedule = schedule
        self.diagnostics = diagnostics
    }

    /// 後処理を1回実行し、`completed` 以外なら次回の実行を予約します。
    ///
    /// 責務: 実行条件の確認と各ステップの実行を1件の結果へまとめ、未完了なら持ち越しの予約を出します。
    /// - Returns: 実行結果。`completed` 以外は再予約済み(予約の失敗は診断記録へ残ります)。
    func execute() async -> PostSessionProcessingOutcome {
        diagnostics.started()
        var accountIdentifier: String?
        let outcome = await process(resolvedAccountIdentifier: &accountIdentifier)
        diagnostics.finished(outcome)
        if outcome != .completed {
            schedule.execute(automaticUploadEnabled: accountIdentifier.map(isAutomaticUploadEnabled) ?? false)
        }
        return outcome
    }

    /// 実行条件を確認し、条件を満たせば各ステップを順に実行します。
    ///
    /// 責務: 開始時の記録中・アカウント未解決・期限切れを持ち越しや中断へ振り分け、残りをステップの実行へ渡します。
    /// - Parameter resolvedAccountIdentifier: 解決できたアカウント識別子の書き込み先(再予約の条件に使います)。
    /// - Returns: 実行結果。
    private func process(resolvedAccountIdentifier: inout String?) async -> PostSessionProcessingOutcome {
        if isRecordingActive() {
            diagnostics.deferredForActiveRecording()
            return .deferredForActiveRecording
        }
        guard let accountIdentifier = await resolveAccountIdentifier(), !accountIdentifier.isEmpty else {
            if Task.isCancelled { return interrupt() }
            diagnostics.deferredForUnavailableAccount()
            return .deferredForUnavailableAccount
        }
        resolvedAccountIdentifier = accountIdentifier
        return await runSteps(accountIdentifier: accountIdentifier)
    }

    /// 各ステップを宣言順に実行します。片方が失敗しても、もう片方は実行します。
    ///
    /// 責務: ステップごとに記録開始と期限切れを確認し、設定オフの時は自動アップロードのステップを省き、成否を1件の結果へまとめます。
    /// - Parameter accountIdentifier: 処理対象のアカウント識別子。
    /// - Returns: 実行結果。
    private func runSteps(accountIdentifier: String) async -> PostSessionProcessingOutcome {
        let uploadEnabled = isAutomaticUploadEnabled(accountIdentifier)
        var failedSteps = Set<PostSessionProcessingStep>()
        for step in PostSessionProcessingStep.allCases {
            if let interruption = interruptionBeforeStep() { return interruption }
            if step.requiresAutomaticUpload, !uploadEnabled {
                diagnostics.stepSkippedForAutomaticUploadOff(step)
                continue
            }
            do {
                try await perform(step, accountIdentifier: accountIdentifier)
                diagnostics.stepSucceeded(step)
            } catch is CancellationError {
                return interrupt()
            } catch {
                let nsError = error as NSError
                diagnostics.stepFailed(step, errorDomain: nsError.domain, errorCode: nsError.code)
                failedSteps.insert(step)
            }
        }
        return failedSteps.isEmpty ? .completed : .stepsFailed(failedSteps)
    }

    /// ステップの前に、期限切れまたは記録の開始で残りを止めるべきかを判定します。
    ///
    /// 責務: キャンセルを期限切れによる中断へ、記録中を持ち越しへ変換し、続けてよければ `nil` を返します。
    /// - Returns: 止める場合の結果。続ける場合は `nil`。
    private func interruptionBeforeStep() -> PostSessionProcessingOutcome? {
        if Task.isCancelled { return interrupt() }
        if isRecordingActive() {
            diagnostics.deferredForActiveRecording()
            return .deferredForActiveRecording
        }
        return nil
    }

    /// 期限切れによる中断を診断記録へ残します。
    ///
    /// 責務: 中断の記録と結果を1か所で対応させます。
    /// - Returns: 期限切れによる中断。
    private func interrupt() -> PostSessionProcessingOutcome {
        diagnostics.interruptedByExpiration()
        return .interruptedByExpiration
    }

    /// 1つのステップを、注入された処理で実行します。
    ///
    /// 責務: ステップの種類を対応する処理の呼び出しへ振り分けます。
    /// - Parameters:
    ///   - step: 実行するステップ。
    ///   - accountIdentifier: 処理対象のアカウント識別子。
    /// - Throws: 処理が投げたエラー。
    private func perform(_ step: PostSessionProcessingStep, accountIdentifier: String) async throws {
        switch step {
        case .upload: try await upload(accountIdentifier)
        case .locationTrackUpload: try await uploadLocationTracks(accountIdentifier)
        case .eviction: try evictStaleRawLogs(accountIdentifier)
        }
    }
}
