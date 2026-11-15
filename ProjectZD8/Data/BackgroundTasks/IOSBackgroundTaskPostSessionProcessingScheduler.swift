#if os(iOS)
import BackgroundTasks
import Foundation
import OSLog

/// 記録セッション終了後の後処理を、`BGTaskScheduler` の `BGProcessingTask` として予約・起動するiOS実装です。
///
/// 実行の判断(記録中・アカウント・設定・順序・結果・再予約)は `RunPostSessionProcessingUseCase` に置き、
/// この型はOSへの予約・起動ハンドラの登録・期限切れの伝達・完了の報告だけを行います(`BGTask` は単体テストで生成できないため)。
/// タスク識別子は `<bundle ID>.post-session-processing` で、Info.plist の `BGTaskSchedulerPermittedIdentifiers` に同じ値が必要です。
///
/// - Important: バックグラウンドでの後処理の起動(OSによる `BGProcessingTask` の実行・期限切れ・完了報告)は実機で未検証です。
///   ビルドが通ることだけを確認しています。
@MainActor
final class IOSBackgroundTaskPostSessionProcessingScheduler: PostSessionProcessingSchedulerPort {
    /// 後処理のタスク識別子です。`Bundle.main.bundleIdentifier` から組み立てます。
    static var taskIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "ProjectZD8").post-session-processing"
    }

    /// 起動ハンドラをこのプロセスで登録済みかどうかです。`BGTaskScheduler` へ同じ識別子を2回登録しないために使います。
    private static var hasRegisteredLaunchHandler = false

    /// 予約と登録を受け付けるシステム境界です。
    private let scheduler: BGTaskScheduler

    /// 起動ハンドラの登録失敗を記録するロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "PostSessionProcessing")

    /// システム境界を固定して生成します。
    ///
    /// 責務: 予約と登録の送り先を受け取ります。
    /// - Parameter scheduler: 予約と登録を受け付けるシステム境界。
    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    /// 後処理を `BGProcessingTaskRequest` として予約します。同じ識別子の予約済み要求は置き換わります。
    ///
    /// 責務: ネットワーク条件を引数のとおり、外部電源を不要として1件の要求をOSへ渡します。
    /// - Parameter requiresNetworkConnectivity: ネットワーク接続を実行条件にする場合は `true`。
    /// - Throws: OSが予約を受け付けなかった場合の `BGTaskScheduler.Error` 等。
    func schedule(requiresNetworkConnectivity: Bool) throws {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = requiresNetworkConnectivity
        request.requiresExternalPower = false
        try scheduler.submit(request)
    }

    /// 後処理の起動ハンドラを登録します。アプリの起動完了より前に1回だけ呼びます(2回目以降は何もしません)。
    ///
    /// 責務: OSが後処理を起動したとき `run` を `Task` で走らせ、期限切れでその `Task` をキャンセルし、
    /// `run` が `true`(completed)を返したときだけ成功として完了を報告するハンドラを登録します。
    /// - Parameter run: 後処理を1回実行し、completed なら `true` を返す処理(`RunPostSessionProcessingUseCase` へ結び付けます)。
    /// - Side Effects: 識別子が Info.plist で許可されていない等で登録できなかった場合は fault を出力します。
    func registerLaunchHandler(run: @escaping @MainActor () async -> Bool) {
        guard !Self.hasRegisteredLaunchHandler else { return }
        Self.hasRegisteredLaunchHandler = true
        let registered = scheduler.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                Self.handle(task, run: run)
            }
        }
        if !registered {
            logger.fault("Post-session processing launch handler registration failed")
        }
    }

    /// OSが起動した1件のタスクを処理します。
    ///
    /// 責務: 実行の `Task` を始め、期限切れをキャンセルへ、実行結果を完了報告へ写します。
    /// - Parameters:
    ///   - task: OSが起動したタスク。
    ///   - run: 後処理を1回実行し、completed なら `true` を返す処理。
    private static func handle(_ task: BGTask, run: @escaping @MainActor () async -> Bool) {
        let work = Task { @MainActor in
            let completed = await run()
            task.setTaskCompleted(success: completed)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
#endif
