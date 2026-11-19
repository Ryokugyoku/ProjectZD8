#if os(iOS)
import ActivityKit
import Foundation
import OSLog

/// 記録中セッションの常時表示を、ActivityKitのLive Activityで出すiOS実装です。
///
/// このプロセスが開始した表示を1件だけ追跡し、`activityStateUpdates` で終了・消去を検知して追跡を外します。
/// アプリ自身の `end` では先に追跡を外すため、追跡中に終了・消去を検知した場合だけ、システムまたはユーザーによる終了として診断へ残します。
/// 開始・更新では受け取った有効期限を渡し、更新が途絶えた表示をシステムが古い扱い(`isStale`)にできるようにします。
@MainActor
final class ActivityKitRecordingSessionActivityAdapter: SessionActivityPort {
    /// 表示内容をLive Activityの形へ写す変換器です。
    private let mapper = RecordingSessionActivityContentStateMapper()
    /// このプロセスが開始し、まだ終了を検知していない表示です。
    private var activity: Activity<RecordingSessionActivityAttributes>?
    /// 追跡中の表示の状態変化を購読するタスクです。
    private var stateObservation: Task<Void, Never>?
    /// 残った表示を片付けた件数を残す統合ログです(category `LiveActivity`)。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "LiveActivity")
    /// システムまたはユーザーによる表示の終了を残す診断記録です。未設定なら記録しません。
    private let lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)?

    /// 追跡中の表示がない状態で生成します。
    ///
    /// 責務: 表示を開始せずに境界を用意します。
    /// - Parameter lifecycleDiagnostics: システムまたはユーザーによる表示の終了を残す診断記録。
    init(lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)? = nil) {
        self.lifecycleDiagnostics = lifecycleDiagnostics
    }

    /// 追跡中の表示がシステム上に出ているかどうかです。
    var isPresenting: Bool {
        guard let activity else { return false }
        return Self.isUnfinished(activity.activityState)
    }

    /// 前のプロセスが残した表示を閉じてから、表示を開始します。
    ///
    /// 責務: 許可を確かめ、残っている表示を即時に閉じ、新しい表示を有効期限つきで要求して終了検知を始めます。
    /// - Parameters:
    ///   - content: 最初に出す表示内容。
    ///   - staleDate: 次の更新が届かなければ表示が古い扱いになる時刻。
    /// - Throws: 表示が許可されていなければ `SessionActivityPortError.notAuthorized`、システムが断ればActivityKitのエラー。
    func start(_ content: RecordingSessionActivityContent, staleDate: Date) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw SessionActivityPortError.notAuthorized }
        for leftover in Activity<RecordingSessionActivityAttributes>.activities {
            await leftover.end(nil, dismissalPolicy: .immediate)
        }
        let started = try Activity.request(
            attributes: RecordingSessionActivityAttributes(),
            content: ActivityContent(state: mapper.contentState(from: content), staleDate: staleDate),
            pushType: nil
        )
        track(started)
    }

    /// 追跡中の表示の内容を更新します。
    ///
    /// 責務: 1件の表示内容と有効期限をLive Activityへ渡します。
    /// - Parameters:
    ///   - content: 新しい表示内容。
    ///   - staleDate: 次の更新が届かなければ表示が古い扱いになる時刻。
    /// - Throws: 表示が出ていなければ `SessionActivityPortError.notPresenting`。
    func update(_ content: RecordingSessionActivityContent, staleDate: Date) async throws {
        guard isPresenting, let activity else { throw SessionActivityPortError.notPresenting }
        await activity.update(ActivityContent(state: mapper.contentState(from: content), staleDate: staleDate))
    }

    /// 最終内容を出して追跡中の表示を終了します。
    ///
    /// 責務: 最終内容を渡して表示を閉じ、追跡を外します。閉じた後の表示は `dismissAt` までロック画面に残り、その後に消えます。
    /// - Parameters:
    ///   - finalContent: 終了時に出す最終内容。
    ///   - dismissAt: 終了表示を自動で消す時刻。
    /// - Throws: 表示が出ていなければ `SessionActivityPortError.notPresenting`。
    func end(_ finalContent: RecordingSessionActivityContent, dismissAt: Date) async throws {
        guard isPresenting, let activity else { throw SessionActivityPortError.notPresenting }
        stopTracking()
        await activity.end(
            ActivityContent(state: mapper.contentState(from: finalContent), staleDate: nil),
            dismissalPolicy: .after(dismissAt)
        )
    }

    /// このプロセスが追跡していない、まだ終了していない表示をすべて即時に閉じます。
    ///
    /// 責務: 前回のプロセスが残した開始待ち・表示中・古い扱いの表示を閉じます。終了済みで消去待ちの終了表示と、
    /// 追跡中の表示は閉じません。閉じた件数を統合ログへ残します。
    func endOrphanedPresentations() async {
        let trackedID = activity?.id
        let orphans = Activity<RecordingSessionActivityAttributes>.activities.filter {
            $0.id != trackedID && Self.isUnfinished($0.activityState)
        }
        for orphan in orphans {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
        guard !orphans.isEmpty else { return }
        logger.notice("Live Activity orphaned presentations ended: \(orphans.count, privacy: .public)")
    }

    /// 表示の状態が、まだ終了していない(開始待ち・表示中・古い扱い)かどうかを判定します。
    ///
    /// 責務: ActivityKitの表示状態を、未終了か終了済みかへ分けます。
    /// - Parameter state: 表示の状態。
    /// - Returns: 開始待ち・表示中・古い扱いなら `true`。
    private static func isUnfinished(_ state: ActivityState) -> Bool {
        switch state {
        case .active, .stale, .pending: true
        case .ended, .dismissed: false
        @unknown default: false
        }
    }

    /// 開始した表示を追跡し、終了・消去を検知したら追跡を外します。
    ///
    /// 責務: 1件の表示の状態変化の購読を始めます。購読は表示が終わると終わります。
    /// 追跡中のまま終了・消去を検知したら、システムまたはユーザーによる終了として診断へ残します。
    /// - Parameter started: 開始した表示。
    private func track(_ started: Activity<RecordingSessionActivityAttributes>) {
        stopTracking()
        activity = started
        stateObservation = Task { [weak self] in
            for await state in started.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                guard let self, activity?.id == started.id else { return }
                stopTracking()
                lifecycleDiagnostics?.activityClosedBySystem()
                return
            }
        }
    }

    /// 追跡中の表示と購読を外します。
    ///
    /// 責務: 表示の参照と状態購読タスクを破棄します。表示そのものは閉じません。
    private func stopTracking() {
        stateObservation?.cancel()
        stateObservation = nil
        activity = nil
    }
}
#endif
