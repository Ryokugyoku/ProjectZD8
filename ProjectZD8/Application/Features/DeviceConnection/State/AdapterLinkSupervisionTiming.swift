import Foundation

/// 車両確認の確認窓と再確認間隔を1か所で定義する定数です。
nonisolated struct AdapterLinkSupervisionTiming: Equatable, Sendable {
    /// 本番で使う定数です。リンクが `ready` になってから10分間、30秒ごとに再確認します。
    static let standard = AdapterLinkSupervisionTiming(
        vehicleConfirmationWindow: 10 * 60,
        vehicleConfirmationInterval: 30
    )

    /// リンクが `ready` になった時刻(または再開時刻)から再確認を続ける秒数です。
    let vehicleConfirmationWindow: TimeInterval

    /// 無応答の後、次の再確認までに待つ秒数です。
    let vehicleConfirmationInterval: TimeInterval

    /// 確認窓と再確認間隔を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を1件の不変値へまとめます。
    /// - Parameters:
    ///   - vehicleConfirmationWindow: 確認窓の秒数。
    ///   - vehicleConfirmationInterval: 再確認間隔の秒数(0より大きい値)。
    init(vehicleConfirmationWindow: TimeInterval, vehicleConfirmationInterval: TimeInterval) {
        self.vehicleConfirmationWindow = vehicleConfirmationWindow
        self.vehicleConfirmationInterval = vehicleConfirmationInterval
    }

    /// 1つの確認窓で要求できる車両確認の最大回数です(最初の確認を含む)。
    ///
    /// 責務: 時計が進まない場合でも再確認が無限に続かないよう、窓と間隔から回数の上限を決めます。
    var maximumVehicleConfirmationAttempts: Int {
        guard vehicleConfirmationInterval > 0 else { return 1 }
        return max(1, Int(vehicleConfirmationWindow / vehicleConfirmationInterval))
    }

    /// 再確認までの待機時間を `Duration` で返します。
    ///
    /// 責務: 秒数の再確認間隔を待機ポートへ渡せる型へ変換します。
    var vehicleConfirmationIntervalDuration: Duration {
        .milliseconds(Int64((vehicleConfirmationInterval * 1000).rounded()))
    }
}
