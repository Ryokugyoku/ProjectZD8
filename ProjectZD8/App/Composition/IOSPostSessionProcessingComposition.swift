#if os(iOS)
import Foundation

/// 記録セッション終了後の後処理(`BGProcessingTask`)を、iOSのルートの依存関係へ結び付ける手順です。
///
/// 予約は `ConnectionSessionLifecycleModel` の終了保存の通知から、実行はOSの起動ハンドラから行います。
/// macOSには配線しません。
@MainActor
struct IOSPostSessionProcessingComposition {
    /// 認証状態の確認が終わるのを待つ1回の間隔(ナノ秒)です。
    private static let accountResolutionPollIntervalNanoseconds: UInt64 = 100_000_000
    /// 認証状態の確認が終わるのを待つ回数の上限です(間隔と合わせて約10秒)。
    private static let accountResolutionMaximumPollCount = 100

    /// 予約と起動ハンドラの登録を受け付けるiOS実装です。
    let scheduler: IOSBackgroundTaskPostSessionProcessingScheduler
    /// 後処理の実行を予約するユースケースです。
    let schedule: SchedulePostSessionProcessingUseCase
    /// アカウント別の自動アップロード設定の読み出し元です。
    private let accountSettings: AccountSettingsUseCase
    /// 終了直後に走行ルート(位置の軌跡)のアップロードを1回起動するトリガーです。
    private let locationTrackUploadTrigger: ConnectionSessionLocationTrackUploadTrigger

    /// 予約に必要な依存関係を組み立てます。
    ///
    /// 責務: BGTaskScheduler の予約境界・統合ログの診断記録・アカウント設定の読み出し元・軌跡の即時送信のトリガーを1回ずつ生成します。
    init() {
        let scheduler = IOSBackgroundTaskPostSessionProcessingScheduler()
        self.scheduler = scheduler
        schedule = SchedulePostSessionProcessingUseCase(
            scheduler: scheduler,
            diagnostics: OSLogPostSessionProcessingDiagnosticsAdapter()
        )
        accountSettings = AccountSettingsUseCase(store: UbiquitousKeyValueStoreAccountSettingsStore())
        locationTrackUploadTrigger = ConnectionSessionLocationTrackUploadTrigger(
            diagnostics: OSLogConnectionSessionLocationTrackSyncDiagnosticsAdapter()
        )
    }

    /// 終了を保存できたセッションの所有アカウントの自動アップロード設定で、後処理を予約し、軌跡の即時送信を起動します。
    ///
    /// 責務: 1件の終了保存の通知を予約要求と軌跡の即時送信の要求へ変換します。設定は画面の表示を待たずに保存先から読みます。
    /// - Parameter session: 終了を保存できたセッション。
    func sessionEndPersisted(_ session: ConnectionSession) {
        let automaticUploadEnabled = isAutomaticUploadEnabled(for: session.accountIdentifier)
        schedule.execute(automaticUploadEnabled: automaticUploadEnabled)
        locationTrackUploadTrigger.sessionDidEnd(session, automaticUploadEnabled: automaticUploadEnabled)
    }

    /// 後処理の起動ハンドラを登録します。アプリの起動完了より前に1回だけ呼びます。
    ///
    /// 責務: 記録中の判定・アカウントの解決・設定・既存の同期・軌跡のアップロード・整理のユースケースを実行のユースケースへ結び付け、
    /// その完了をOSへの完了報告へ結び付けます。軌跡のアップロードは即時送信のトリガーにも結び付けます。
    /// - Parameters:
    ///   - foundation: 接続セッション保存先と履歴モデルを持つ共通の土台。
    ///   - liveTelemetry: 記録中かどうかを持つPID継続取得のモデル。
    ///   - authentication: サインイン中アカウントの持ち主。
    func registerLaunchHandler(
        foundation: ApplicationRootFoundation,
        liveTelemetry: LiveTelemetryModel,
        authentication: AuthenticationSessionModel
    ) {
        let storage = foundation.storage.sessions
        let synchronization = IOSApplicationComposition.makeConnectionSessionSynchronization(storage: storage)
        let eviction = EvictStaleConnectionSessionRawLogsUseCase(sessionRepository: storage, rawLogRepository: storage)
        let history = foundation.history
        let locationTrackUpload = ConnectionSessionLocationTrackSyncComposition.makeUploadUseCase(database: foundation.database)
        locationTrackUploadTrigger.connect { try await locationTrackUpload.execute(accountIdentifier: $0) }
        let run = RunPostSessionProcessingUseCase(
            isRecordingActive: { liveTelemetry.state.isConnectionActive },
            resolveAccountIdentifier: { await Self.resolveAccountIdentifier(authentication) },
            isAutomaticUploadEnabled: { isAutomaticUploadEnabled(for: $0) },
            upload: { accountIdentifier in
                try await synchronization.execute(accountIdentifier: accountIdentifier, uploadsPendingSessions: true)
                history.send(.localDataChanged)
            },
            uploadLocationTracks: { accountIdentifier in
                _ = try await locationTrackUpload.execute(accountIdentifier: accountIdentifier)
            },
            evictStaleRawLogs: { accountIdentifier in
                try eviction.execute(accountIdentifier: accountIdentifier)
                history.send(.localDataChanged)
            },
            schedule: schedule,
            diagnostics: OSLogPostSessionProcessingDiagnosticsAdapter()
        )
        scheduler.registerLaunchHandler { await run.execute() == .completed }
    }

    /// 指定アカウントの自動アップロード設定を保存先から読みます。
    ///
    /// 責務: アカウント識別子を保存済みの自動アップロード設定(未保存なら既定のオフ)へ変換します。
    /// - Parameter accountIdentifier: 設定を読むアカウントの識別子。
    /// - Returns: 自動アップロードがオンなら `true`。
    private func isAutomaticUploadEnabled(for accountIdentifier: String) -> Bool {
        accountSettings.load(for: accountIdentifier).automaticSessionUploadEnabled
    }

    /// サインイン中アカウントの識別子を、保存済みセッションの確認が終わるまで上限付きで待って返します。
    ///
    /// 責務: バックグラウンド起動直後の確認中(`checkingSession`)を待ち、サインイン済みの時だけ識別子を返します。
    /// 確認の開始は常駐リンク監視の起動(`IOSAdapterLinkSupervisionDriver.launch()`)が行います。
    /// - Parameter authentication: 認証状態の持ち主。
    /// - Returns: サインイン済みアカウントの識別子。サインアウト・上限までに確認が終わらない・キャンセルでは `nil`。
    private static func resolveAccountIdentifier(_ authentication: AuthenticationSessionModel) async -> String? {
        for _ in 0..<accountResolutionMaximumPollCount {
            switch authentication.state.phase {
            case .signedIn: return authentication.state.session?.userIdentifier
            case .signedOut, .deletingAccount: return nil
            case .checkingSession, .signingIn: break
            }
            do {
                try await Task.sleep(nanoseconds: accountResolutionPollIntervalNanoseconds)
            } catch {
                return nil
            }
        }
        return nil
    }
}
#endif
