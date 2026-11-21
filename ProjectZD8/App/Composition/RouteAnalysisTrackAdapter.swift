import Foundation

/// 解析の走行ルートの読み込み(`RouteAnalysisTrackPort`)を、LogHistory の軌跡の読み込みと状態の決定で実装します。
///
/// Analysis が LogHistory の具象型に依存しないよう、App 層に置きます。
/// - 描けない理由と注記のキーは、セッション詳細と同じ `DrivingRouteStatusResolver` で決めます(判定を複製しません)。
/// - 失敗はセッション詳細と同じ `DrivingRouteFailureClassifier` で値にします。投げるのは `CancellationError` だけです。
/// - 軌跡の区切りはメインの外(`Task.detached`)で行います。
@MainActor final class RouteAnalysisTrackAdapter: RouteAnalysisTrackPort {
    /// 軌跡を読み込む処理です(セッション ID とアカウント識別子を受け取ります)。
    private let load: @MainActor (ConnectionSessionID, String) async throws -> ConnectionSessionLocationTrackAvailability
    /// 取得結果から表示の状態を決める部品です。
    private let resolver: DrivingRouteStatusResolver
    /// 読み込みの失敗を分類する部品です。
    private let failureClassifier: DrivingRouteFailureClassifier

    /// 読み込みの処理と状態・失敗の部品を固定して生成します。
    ///
    /// 責務: 軌跡の読み込みの closure と、状態の決定・失敗の分類の部品を保持します。
    /// - Parameters:
    ///   - load: 軌跡を読み込む処理(段階2の `LoadConnectionSessionLocationTrackUseCase` を包んだもの)。
    ///   - resolver: 取得結果から表示の状態を決める部品。
    ///   - failureClassifier: 読み込みの失敗を分類する部品。
    init(
        load: @escaping @MainActor (ConnectionSessionID, String) async throws -> ConnectionSessionLocationTrackAvailability,
        resolver: DrivingRouteStatusResolver = .init(),
        failureClassifier: DrivingRouteFailureClassifier = .init()
    ) {
        self.load = load
        self.resolver = resolver
        self.failureClassifier = failureClassifier
    }

    /// セッションの走行ルートを読み込みます。
    ///
    /// 責務: 軌跡を読み、区切って状態を決め、描ける時はルートと注記、描けない時は理由、失敗は分類した値を返します。
    /// - Parameters:
    ///   - sessionID: 読み込むセッションの ID。
    ///   - accountIdentifier: サインイン中のアカウントの識別子。
    /// - Returns: 読み込みの結果。
    /// - Throws: 取り消された時だけ `CancellationError`。
    func loadRoute(sessionID: ConnectionSessionID, accountIdentifier: String) async throws -> RouteAnalysisTrackLoadResult {
        let availability: ConnectionSessionLocationTrackAvailability
        do {
            availability = try await load(sessionID, accountIdentifier)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let failure = failureClassifier.failure(for: error)
            return .failed(messageKey: failure.messageKey, isRetryable: failure.isRetryable)
        }
        try Task.checkCancellation()
        let status = await resolvedStatus(for: availability)
        try Task.checkCancellation()
        return Self.result(for: status)
    }

    /// 取得結果の区切りと判定をメインの外で行います。
    ///
    /// 責務: 純粋な状態の決定を `Task.detached` へ渡し、呼び出し側の取消を伝えます。
    /// - Parameter availability: 軌跡の取得結果。
    /// - Returns: 表示の状態。
    private func resolvedStatus(for availability: ConnectionSessionLocationTrackAvailability) async -> DrivingRouteStatus {
        let resolver = resolver
        let task = Task.detached(priority: .userInitiated) {
            resolver.status(for: availability)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 表示の状態を、解析の読み込みの結果へ写します。
    ///
    /// 責務: ルートがあれば注記と共に、無ければ理由(無い時は「記録なし」の理由)を返します。
    /// 描けない時の注記は、結果の型に入れる所が無いので渡しません。
    /// - Parameter status: 表示の状態。
    /// - Returns: 読み込みの結果。
    private static func result(for status: DrivingRouteStatus) -> RouteAnalysisTrackLoadResult {
        if let route = status.route {
            return .available(route, noticeKeys: status.noticeKeys)
        }
        let absence = status.absence ?? DrivingRouteTextKeys().absence(.notRecorded)
        return .unavailable(reasonKey: absence.messageKey, systemImage: absence.systemImage)
    }
}
