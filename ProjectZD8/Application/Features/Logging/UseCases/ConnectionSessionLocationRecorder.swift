/// 位置の流れを受けて、セッションへ保存する受け手です。メインスレッド外で消費します。
///
/// - 位置は1点ずつ保存します。保存の失敗は診断へ残し、流れの消費は続けます。
/// - 取得可否の変化は保存せず報告します(初期状態は「取得可」。同じ値を続けて報告しません)。
/// - 取消されずに流れが終わったら「取得不可」を報告します。
nonisolated struct ConnectionSessionLocationRecorder: Sendable {
    /// 位置の保存先です。
    private let repository: any ConnectionSessionLocationRepository
    /// 保存の失敗を残す診断です。
    private let diagnostics: any SessionLocationRecordingDiagnosticsPort

    /// 保存先と診断を注入して生成します。
    ///
    /// 責務: 位置の保存に必要な境界を固定します。
    /// - Parameters:
    ///   - repository: 位置の保存先。
    ///   - diagnostics: 保存の失敗を残す診断。
    init(
        repository: any ConnectionSessionLocationRepository,
        diagnostics: any SessionLocationRecordingDiagnosticsPort
    ) {
        self.repository = repository
        self.diagnostics = diagnostics
    }

    /// 位置の流れを最後まで消費して保存します。
    ///
    /// 責務: 位置を保存し、取得可否の変化と、取消されずに終わった流れを「取得不可」として報告します。
    /// - Parameters:
    ///   - updates: 位置または取得不可の通知の流れ。
    ///   - sessionID: 位置を保存する接続セッション。
    ///   - availabilityDidChange: 取得可否が変わった時に新しい値を受け取る処理。
    @concurrent
    func record(
        _ updates: AsyncStream<LocationUpdateEvent>,
        sessionID: ConnectionSessionID,
        availabilityDidChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) async {
        var isAvailable = true
        for await event in updates {
            let eventAvailability = handle(event, sessionID: sessionID)
            if eventAvailability != isAvailable {
                isAvailable = eventAvailability
                await availabilityDidChange(eventAvailability)
            }
        }
        guard !Task.isCancelled, isAvailable else { return }
        await availabilityDidChange(false)
    }

    /// 1件の事象を処理し、その事象が示す取得可否を返します。
    ///
    /// 責務: 位置なら保存し(失敗は診断へ残す)、事象を取得可否へ変換します。
    /// - Parameters:
    ///   - event: 受け取った事象。
    ///   - sessionID: 位置を保存する接続セッション。
    /// - Returns: 位置なら `true`、取得不可の通知なら `false`。
    private func handle(_ event: LocationUpdateEvent, sessionID: ConnectionSessionID) -> Bool {
        switch event {
        case let .fix(fix):
            store(fix, sessionID: sessionID)
            return true
        case .unavailable:
            return false
        }
    }

    /// 位置を1点保存します。
    ///
    /// 責務: 位置を保存先へ追記し、失敗したら診断へ残して呼び出し元へは伝えません。
    /// - Parameters:
    ///   - fix: 保存する位置。
    ///   - sessionID: 位置を保存する接続セッション。
    private func store(_ fix: LocationFix, sessionID: ConnectionSessionID) {
        do {
            try repository.appendSample(fix, for: sessionID)
        } catch {
            diagnostics.sampleStorageFailed(sessionID: sessionID, error: error)
        }
    }
}
