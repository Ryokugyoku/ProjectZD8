import Foundation

/// 接続履歴をGarage表示用の車両別アクティビティへ縮約します。
struct LoadVehicleActivitySummariesUseCase {
    /// アカウント単位の接続履歴取得境界です。
    private let repository: any ConnectionSessionRepository

    /// セッション取得先を固定してユースケースを生成します。
    ///
    /// 責務: 1件の接続履歴Repositoryを車両別アクティビティ集約へ結び付けます。
    /// - Parameter repository: アカウント単位の接続履歴取得先。
    init(repository: any ConnectionSessionRepository) {
        self.repository = repository
    }

    /// 指定アカウントの履歴を車両IDごとの軽量集計へ変換します。
    ///
    /// 責務: 接続履歴を1回だけ走査して登録車両別のセッション統計を返します。
    /// - Parameter accountIdentifier: 集計対象のAppleアカウント識別子。
    /// - Returns: 登録車両IDをキーとするGarage表示用アクティビティ。
    /// - Throws: 接続履歴を取得できない場合のRepositoryエラー。
    func execute(accountIdentifier: String) throws -> [VehicleID: VehicleActivitySummary] {
        var summaries: [VehicleID: VehicleActivitySummary] = [:]
        var latestOdometerDateByVehicleID: [VehicleID: Date] = [:]
        for session in try repository.sessions(for: accountIdentifier) {
            guard let vehicleID = session.vehicle?.id else { continue }
            let previous = summaries[vehicleID] ?? VehicleActivitySummary()
            let sessionDate = session.endedAt ?? session.startedAt
            let shouldUseOdometer = session.endingOdometerKilometers != nil
                && sessionDate >= (latestOdometerDateByVehicleID[vehicleID] ?? .distantPast)
            if shouldUseOdometer { latestOdometerDateByVehicleID[vehicleID] = sessionDate }
            summaries[vehicleID] = VehicleActivitySummary(
                sessionCount: previous.sessionCount + 1,
                lastLoggedAt: latest(previous.lastLoggedAt, sessionDate),
                totalRecordedDuration: previous.totalRecordedDuration + recordedDuration(of: session),
                interruptedCount: previous.interruptedCount + (session.status == .interrupted ? 1 : 0),
                isConnected: previous.isConnected || session.status == .connected,
                latestOdometerKilometers: shouldUseOdometer ? session.endingOdometerKilometers : previous.latestOdometerKilometers,
                odometerModelCode: shouldUseOdometer ? session.distanceSourceModelCode : previous.odometerModelCode
            )
        }
        return summaries
    }

    /// 2件の任意日時から新しい日時を返します。
    ///
    /// 責務: 車両別アクティビティに保持する最終ログ日時を単一値へ縮約します。
    /// - Parameters:
    ///   - lhs: 既に集約済みの日時。
    ///   - rhs: 新しく比較する日時。
    /// - Returns: 2件のうち新しい日時。
    private func latest(_ lhs: Date?, _ rhs: Date) -> Date {
        max(lhs ?? .distantPast, rhs)
    }

    /// 1件の終了済みセッションから非負の記録時間を返します。
    ///
    /// 責務: セッションの開始・終了日時をGarage集計用の非負秒数へ変換します。
    /// - Parameter session: 記録時間を求める接続セッション。
    /// - Returns: 未終了時は0、終了済みの場合は非負の経過秒数。
    private func recordedDuration(of session: ConnectionSession) -> TimeInterval {
        max(0, session.endedAt?.timeIntervalSince(session.startedAt) ?? 0)
    }
}
