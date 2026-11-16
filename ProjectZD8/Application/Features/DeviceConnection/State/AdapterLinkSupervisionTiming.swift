import Foundation

/// 車両確認の確認窓・確認と確認の最短間隔・抑止中の見張りの上限・リンク待ちの保持の上限を1か所で定義する定数です。
///
/// 確認は応答駆動で、確認の結果を受け取ったことを次の確認の起点にします。最短間隔は空回り防止の下限で、
/// 結果がそれより早く返った場合だけ残り時間を待ちます。時刻はすべて単調時計基準です。
nonisolated struct AdapterLinkSupervisionTiming: Equatable, Sendable {
    /// 本番で使う定数です。リンクが `ready` になってから10分間、最短1秒間隔で確認し、抑止中の見張りは8時間までです。
    /// リンクが `ready` でない間のユーザー切断から3分以内にリンクが戻れば、同じ走行として保持を続けます。
    static let standard = AdapterLinkSupervisionTiming(
        vehicleConfirmationWindow: 10 * 60,
        vehicleConfirmationInterval: 1,
        heldWatchLimit: 8 * 60 * 60,
        heldLinkWaitLimit: 3 * 60
    )

    /// リンクが `ready` になった時刻(または窓の取り直しの時刻)から確認を続ける秒数です。
    let vehicleConfirmationWindow: TimeInterval

    /// 確認を送ってから次の確認を送るまでの最短の秒数です(空回り防止)。
    let vehicleConfirmationInterval: TimeInterval

    /// 抑止に入って(または前面復帰で取り直して)から見張りを続ける秒数の上限です。
    let heldWatchLimit: TimeInterval

    /// リンクが `ready` でない間にユーザーが切断してから、リンクの復帰を同じ走行とみなす秒数の上限です(ちょうどは同じ走行)。
    let heldLinkWaitLimit: TimeInterval

    /// 確認窓・最短間隔・見張りの上限・リンク待ちの保持の上限を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を1件の不変値へまとめます。
    /// - Parameters:
    ///   - vehicleConfirmationWindow: 確認窓の秒数。
    ///   - vehicleConfirmationInterval: 確認と確認の最短間隔の秒数(0より大きい値)。
    ///   - heldWatchLimit: 抑止中の見張りの上限の秒数。既定は8時間。
    ///   - heldLinkWaitLimit: リンク待ちの保持で、ユーザー切断からリンクの復帰を同じ走行とみなす秒数。既定は3分。
    init(
        vehicleConfirmationWindow: TimeInterval,
        vehicleConfirmationInterval: TimeInterval,
        heldWatchLimit: TimeInterval = 8 * 60 * 60,
        heldLinkWaitLimit: TimeInterval = 3 * 60
    ) {
        self.vehicleConfirmationWindow = vehicleConfirmationWindow
        self.vehicleConfirmationInterval = vehicleConfirmationInterval
        self.heldWatchLimit = heldWatchLimit
        self.heldLinkWaitLimit = heldLinkWaitLimit
    }

    /// 1つの確認窓で要求できる車両確認の最大回数です(最初の確認を含む)。
    ///
    /// 責務: 時計が進まない場合でも確認が無限に続かないよう、窓と最短間隔から回数の上限(安全上限)を決めます。
    var maximumVehicleConfirmationAttempts: Int {
        guard vehicleConfirmationInterval > 0 else { return 1 }
        return max(1, Int(vehicleConfirmationWindow / vehicleConfirmationInterval))
    }
}
