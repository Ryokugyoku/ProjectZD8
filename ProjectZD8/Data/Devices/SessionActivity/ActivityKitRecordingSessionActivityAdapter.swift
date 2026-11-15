#if os(iOS)
import ActivityKit
import Foundation

/// 記録中セッションの常時表示を、ActivityKitのLive Activityで出すiOS実装です。
///
/// このプロセスが開始した表示を1件だけ追跡し、`activityStateUpdates` で終了・消去を検知して追跡を外します。
@MainActor
final class ActivityKitRecordingSessionActivityAdapter: SessionActivityPort {
    /// 表示内容をLive Activityの形へ写す変換器です。
    private let mapper = RecordingSessionActivityContentStateMapper()
    /// このプロセスが開始し、まだ終了を検知していない表示です。
    private var activity: Activity<RecordingSessionActivityAttributes>?
    /// 追跡中の表示の状態変化を購読するタスクです。
    private var stateObservation: Task<Void, Never>?

    /// 追跡中の表示がない状態で生成します。
    ///
    /// 責務: 表示を開始せずに境界を用意します。
    init() {}

    /// 追跡中の表示がシステム上に出ているかどうかです。
    var isPresenting: Bool {
        guard let activity else { return false }
        switch activity.activityState {
        case .active, .stale, .pending: return true
        case .ended, .dismissed: return false
        @unknown default: return false
        }
    }

    /// 前のプロセスが残した表示を閉じてから、表示を開始します。
    ///
    /// 責務: 許可を確かめ、残っている表示を即時に閉じ、新しい表示を要求して終了検知を始めます。
    /// - Parameter content: 最初に出す表示内容。
    /// - Throws: 表示が許可されていなければ `SessionActivityPortError.notAuthorized`、システムが断ればActivityKitのエラー。
    func start(_ content: RecordingSessionActivityContent) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw SessionActivityPortError.notAuthorized }
        for leftover in Activity<RecordingSessionActivityAttributes>.activities {
            await leftover.end(nil, dismissalPolicy: .immediate)
        }
        let started = try Activity.request(
            attributes: RecordingSessionActivityAttributes(),
            content: ActivityContent(state: mapper.contentState(from: content), staleDate: nil),
            pushType: nil
        )
        track(started)
    }

    /// 追跡中の表示の内容を更新します。
    ///
    /// 責務: 1件の表示内容をLive Activityへ渡します。
    /// - Parameter content: 新しい表示内容。
    /// - Throws: 表示が出ていなければ `SessionActivityPortError.notPresenting`。
    func update(_ content: RecordingSessionActivityContent) async throws {
        guard isPresenting, let activity else { throw SessionActivityPortError.notPresenting }
        await activity.update(ActivityContent(state: mapper.contentState(from: content), staleDate: nil))
    }

    /// 最終内容を出して追跡中の表示を終了します。
    ///
    /// 責務: 最終内容を渡して表示を閉じ、追跡を外します。閉じた後の表示はシステムの既定の時間だけロック画面に残ります。
    /// - Parameter finalContent: 終了時に出す最終内容。
    /// - Throws: 表示が出ていなければ `SessionActivityPortError.notPresenting`。
    func end(_ finalContent: RecordingSessionActivityContent) async throws {
        guard isPresenting, let activity else { throw SessionActivityPortError.notPresenting }
        stopTracking()
        await activity.end(
            ActivityContent(state: mapper.contentState(from: finalContent), staleDate: nil),
            dismissalPolicy: .default
        )
    }

    /// 開始した表示を追跡し、終了・消去を検知したら追跡を外します。
    ///
    /// 責務: 1件の表示の状態変化の購読を始めます。購読は表示が終わると終わります。
    /// - Parameter started: 開始した表示。
    private func track(_ started: Activity<RecordingSessionActivityAttributes>) {
        stopTracking()
        activity = started
        stateObservation = Task { [weak self] in
            for await state in started.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                if self?.activity?.id == started.id { self?.stopTracking() }
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
