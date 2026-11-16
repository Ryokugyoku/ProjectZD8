import Foundation

/// 常時表示の境界への操作を受け付けた順に1件ずつ実行し、記録セッションの世代で古い操作を捨てます。
///
/// - セッションごとに世代を進めます。開始・更新は受け付けた世代が実行時点でまだ続いている時だけ実行します
///   (終わったセッションの開始・更新が、次のセッションの表示を上書きしないため)。
/// - 終了は世代に関係なく、実行時点で表示が出ている時だけ実行します。開始の最中にセッションが終わっても、
///   終了は開始の完了後に実行されるため、表示は直ちに閉じられます。
/// - 操作の失敗は診断へ1件ずつ残し、呼び出し元へは伝えません。後続の操作は失敗に関係なく実行します。
@MainActor
final class RecordingSessionActivityOperationSequencer {
    /// 記録セッションの世代です。
    typealias Generation = Int

    /// 常時表示の境界です。
    private let activity: any SessionActivityPort
    /// 失敗を残す診断記録です。
    private let diagnostics: any RecordingSessionActivityDiagnosticsPort
    /// 最後に始めたセッションの世代です。
    private var latestGeneration: Generation = 0
    /// 続いているセッションの世代です。セッションが無ければ `nil` です。
    private var liveGeneration: Generation?
    /// 直前に受け付けた操作です。次の操作はこれの完了を待ってから始めます。
    private var operationTail: Task<Void, Never>?

    /// 境界と診断記録を固定して生成します。
    ///
    /// 責務: 操作の実行先と失敗の記録先を保持します。
    /// - Parameters:
    ///   - activity: 常時表示の境界。
    ///   - diagnostics: 失敗を残す診断記録。
    init(activity: any SessionActivityPort, diagnostics: any RecordingSessionActivityDiagnosticsPort) {
        self.activity = activity
        self.diagnostics = diagnostics
    }

    /// 続いているセッションの世代です。セッションが無ければ `nil` です。
    var currentGeneration: Generation? { liveGeneration }

    /// 新しいセッションの世代を始めます。
    ///
    /// 責務: 世代を1つ進めて続いている世代にし、以前の世代の開始・更新を以後実行させないようにします。
    /// - Returns: 始めた世代。
    @discardableResult
    func beginSession() -> Generation {
        latestGeneration += 1
        liveGeneration = latestGeneration
        return latestGeneration
    }

    /// 続いているセッションを終わらせます。
    ///
    /// 責務: 続いている世代を外し、まだ実行していない開始・更新を以後実行させないようにします。
    func endSession() {
        liveGeneration = nil
    }

    /// 指定の世代がまだ続いているかどうかを返します。
    ///
    /// 責務: 世代の一致で、操作を実行してよいセッションかを判定します。
    /// - Parameter generation: 判定する世代。
    /// - Returns: 続いているセッションの世代なら `true`。
    func isLive(_ generation: Generation) -> Bool {
        liveGeneration == generation
    }

    /// 表示の開始を受け付けます。
    ///
    /// 責務: 実行時点で世代が続いていて表示が出ていなければ開始し、開始できたら `didStart` を呼びます。
    /// - Parameters:
    ///   - content: 最初に出す表示内容。
    ///   - generation: 受け付けたセッションの世代。
    ///   - didStart: 開始できた後の処理。
    func enqueueStart(
        _ content: RecordingSessionActivityContent,
        generation: Generation,
        didStart: @escaping @MainActor () -> Void
    ) {
        enqueue(.start) { [weak self] activity in
            guard let self, isLive(generation), !activity.isPresenting else { return }
            try await activity.start(content)
            didStart()
        }
    }

    /// 表示内容の更新を受け付けます。
    ///
    /// 責務: 実行時点で世代が続いている時だけ更新します。
    /// - Parameters:
    ///   - content: 新しい表示内容。
    ///   - generation: 受け付けたセッションの世代。
    func enqueueUpdate(_ content: RecordingSessionActivityContent, generation: Generation) {
        enqueue(.update) { [weak self] activity in
            guard let self, isLive(generation) else { return }
            try await activity.update(content)
        }
    }

    /// 最終内容での終了を受け付けます。
    ///
    /// 責務: 先に受け付けた開始の完了後、実行時点で表示が出ていれば最終内容で閉じ、閉じられたら `didEnd` を呼びます。
    /// - Parameters:
    ///   - finalContent: 終了時に出す最終内容。
    ///   - didEnd: 閉じられた後の処理。
    func enqueueEnd(_ finalContent: RecordingSessionActivityContent, didEnd: @escaping @MainActor () -> Void) {
        enqueue(.end) { activity in
            guard activity.isPresenting else { return }
            try await activity.end(finalContent)
            didEnd()
        }
    }

    /// 受け付けた操作がすべて終わるまで待ちます。
    ///
    /// 責務: 呼び出し時点までに受け付けた操作の完了を待てるようにします。
    func waitForPendingOperations() async {
        await operationTail?.value
    }

    /// 操作を、先に受け付けた操作の完了後に実行するよう受け付けます。
    ///
    /// 責務: 操作を1列に並べ、失敗を診断へ残して呼び出し元へ波及させません。
    /// - Parameters:
    ///   - operation: 診断に残す操作の種類。
    ///   - body: 実行する操作。
    private func enqueue(
        _ operation: RecordingSessionActivityOperation,
        _ body: @escaping @MainActor (any SessionActivityPort) async throws -> Void
    ) {
        let previous = operationTail
        let activity = activity
        let diagnostics = diagnostics
        operationTail = Task { @MainActor in
            await previous?.value
            do {
                try await body(activity)
            } catch {
                diagnostics.operationFailed(operation, error: error)
            }
        }
    }
}
