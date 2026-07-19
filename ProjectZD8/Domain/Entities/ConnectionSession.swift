import Foundation

/// HOME接続開始から通信終了までの1回の接続履歴です。
struct ConnectionSession: Identifiable, Equatable, Codable, Sendable {
    /// 履歴画面が表示するセッション状態です。
    enum Status: Equatable, Sendable {
        /// 現在も接続と取得が継続しています。
        case connected
        /// ユーザー操作によって正常に終了しました。
        case completed
        /// 通信または処理上の理由で中断しました。
        case interrupted
    }

    /// セッションの安定識別子です。
    let id: ConnectionSessionID
    /// セッションを所有するAppleアカウント識別子です。
    let accountIdentifier: String
    /// HOMEで接続開始を押した日時です。
    let startedAt: Date
    /// 終了が確定した日時です。
    var endedAt: Date?
    /// 終了が確定した直接原因です。
    var endReason: ConnectionSessionEndReason?
    /// 接続時点の登録車両表示情報です。
    var vehicle: ConnectionSessionVehicle?
    /// セッション内で最初に取得できた累積走行距離です。
    var startingOdometerKilometers: Double?
    /// セッション内で最後に取得できた累積走行距離です。
    var endingOdometerKilometers: Double?

    /// 終了情報から履歴表示用の現在状態を返します。
    var status: Status {
        guard let endReason else { return .connected }
        return endReason == .userDisconnected ? .completed : .interrupted
    }

    /// セッション中の累積走行距離差分です。
    var recordedDistanceKilometers: Double? {
        guard let startingOdometerKilometers, let endingOdometerKilometers,
              startingOdometerKilometers.isFinite, endingOdometerKilometers.isFinite,
              startingOdometerKilometers >= 0, endingOdometerKilometers >= startingOdometerKilometers else {
            return nil
        }
        return endingOdometerKilometers - startingOdometerKilometers
    }

    /// セッションの所有者と開始時刻を固定して生成します。
    ///
    /// 責務: 1回のHOME接続開始を未終了の接続セッションへ変換します。
    /// - Parameters:
    ///   - id: セッションへ割り当てる安定識別子。
    ///   - accountIdentifier: セッションを所有するAppleアカウント識別子。
    ///   - startedAt: HOMEで接続開始を押した日時。
    ///   - vehicle: 開始時点で確定済みの場合に保持する車両情報。
    init(
        id: ConnectionSessionID = ConnectionSessionID(),
        accountIdentifier: String,
        startedAt: Date = Date(),
        vehicle: ConnectionSessionVehicle? = nil
    ) {
        self.id = id
        self.accountIdentifier = accountIdentifier
        self.startedAt = startedAt
        endedAt = nil
        endReason = nil
        self.vehicle = vehicle
        startingOdometerKilometers = nil
        endingOdometerKilometers = nil
    }
}
