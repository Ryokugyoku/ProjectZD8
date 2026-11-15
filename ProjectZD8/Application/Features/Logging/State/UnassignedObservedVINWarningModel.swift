import Observation

/// 車両未割当で観測VINを持つセッションの照会結果を警告の表示状態へ変換します。
@MainActor
@Observable
final class UnassignedObservedVINWarningModel {
    /// ホームと車両画面が描画する現在の警告です。
    private(set) var warning: UnassignedObservedVINWarning = .hidden

    /// 未紐付けセッションを照会するユースケースです。
    @ObservationIgnored
    private let loadSessions: LoadUnassignedObservedVINConnectionSessionsUseCase

    /// 照会対象のアカウント識別子です。未サインインは `nil` です。
    @ObservationIgnored
    private var accountIdentifier: String?

    /// 照会ユースケースを注入して生成します。
    ///
    /// 責務: 警告の表示状態を未紐付けセッションの照会へ結び付けます。初期状態は非表示です。
    /// - Parameter loadSessions: 未紐付けセッションを照会するユースケース。
    init(loadSessions: LoadUnassignedObservedVINConnectionSessionsUseCase) {
        self.loadSessions = loadSessions
    }

    /// 受け取った操作を照会と表示状態へ反映します。
    ///
    /// 責務: 1件の操作をアカウント切替または再照会へ振り分けます。
    /// - Parameter action: App層または画面から通知された型付き操作。
    func send(_ action: UnassignedObservedVINWarningAction) {
        switch action {
        case let .accountIdentifierChanged(identifier):
            accountIdentifier = identifier
            reload()
        case .refreshRequested:
            reload()
        }
    }

    /// 現在のアカウントで照会し、結果を警告へ反映します。
    ///
    /// 責務: 未サインインなら非表示、照会成功なら件数に応じた警告、失敗なら空と区別した失敗状態にします。
    private func reload() {
        guard let accountIdentifier else {
            warning = .hidden
            return
        }
        do {
            warning = UnassignedObservedVINWarning(sessions: try loadSessions.execute(accountIdentifier: accountIdentifier))
        } catch {
            warning = .loadFailed
        }
    }
}
