/// 車両未割当で観測VINを持つセッションの集計です。
struct UnassignedObservedVINSummary: Equatable, Sendable {
    /// 未登録の車両数です。大文字小文字だけが異なるVINは同じ車両として数えます。
    let vehicleCount: Int
    /// 未登録車両のログ件数です。
    let sessionCount: Int
    /// 最も新しく開始したセッションで観測した、登録画面へ引き渡すVINです。
    let latestVIN: String

    /// セッション一覧から集計を生成します。
    ///
    /// 責務: 車両未割当かつ観測VINを持つセッションだけを数え、VINの種類数・件数・最新VINへ縮約します。
    /// - Parameter sessions: 照会結果のセッション一覧。順序は問いません。
    /// - Returns: 対象セッションが1件以上ある場合の集計。0件なら `nil`。
    init?(sessions: [ConnectionSession]) {
        let candidates = sessions.compactMap { session -> (session: ConnectionSession, vin: String)? in
            guard session.vehicle == nil,
                  let vin = ConnectionSession.normalizedObservedVIN(session.observedVIN) else { return nil }
            return (session, vin)
        }
        guard let latest = candidates.max(by: { $0.session.startedAt < $1.session.startedAt }) else { return nil }
        vehicleCount = Set(candidates.map { $0.vin.uppercased() }).count
        sessionCount = candidates.count
        latestVIN = latest.vin.uppercased()
    }
}
