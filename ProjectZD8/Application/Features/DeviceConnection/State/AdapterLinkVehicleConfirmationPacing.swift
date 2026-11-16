import Foundation

/// 応答駆動の確認で、次の確認をすぐ送るか、最短間隔に達するまで残り時間だけ待つかを決める純粋な方針です。
///
/// 確認の結果を受け取ったことを次の確認の起点にします(固定の待機は挟みません)。結果が最短間隔より早く返った場合
/// (即時のエラー応答など)だけ、空回りを防ぐために残り時間を1回待ちます。待ち明けの後に時計を見直して待ち直すことはしません。
nonisolated struct AdapterLinkVehicleConfirmationPacing: Sendable {
    /// 確認と確認の最短間隔の秒数です。
    let minimumInterval: TimeInterval

    /// 最短間隔を固定して生成します。
    ///
    /// 責務: 空回り防止の下限を判定へ結び付けます。
    /// - Parameter minimumInterval: 最短間隔の秒数。
    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    /// 次の確認までに待つ残り時間を返します。
    ///
    /// 責務: 最後に確認を送った時刻から最短間隔に達していなければ、その残り時間を返します。
    /// - Parameters:
    ///   - sentAt: 最後に確認を送った時刻。続けて送っていなければ `nil`。
    ///   - now: 結果を受け取った時刻。
    /// - Returns: 待つ残り時間。待たずに送ってよい(送った時刻が無い・最短間隔ちょうど以上経過)なら `nil`。
    func remainingWait(sentAt: Date?, now: Date) -> Duration? {
        guard let sentAt else { return nil }
        let remaining = minimumInterval - now.timeIntervalSince(sentAt)
        guard remaining > 0 else { return nil }
        return .microseconds(Int64((remaining * 1_000_000).rounded(.up)))
    }

    /// 次の確認を送る作用、または残り時間の待機の作用を返します。
    ///
    /// 責務: 残り時間が無ければ確認を、あればその時間の待機(待ち明けで `vehicleConfirmationIntervalElapsed`)を選びます。
    /// - Parameters:
    ///   - timeout: 次の確認のタイムアウト種別。
    ///   - sentAt: 最後に確認を送った時刻。
    ///   - now: 結果を受け取った時刻。
    /// - Returns: `.confirmVehicle(timeout)` または `.scheduleVehicleConfirmation(after:)`。
    func nextEffect(timeout: VehicleResponseTimeout, sentAt: Date?, now: Date) -> AdapterLinkSupervisionEffect {
        guard let wait = remainingWait(sentAt: sentAt, now: now) else { return .confirmVehicle(timeout) }
        return .scheduleVehicleConfirmation(after: wait)
    }
}
