import Foundation

/// 通知の[記録開始]の選択を、検知待ちの選択・有効期限つきの意思・捨てる選択のどれとして扱うかと、意思の有効期限を決める純粋な方針です。
nonisolated struct AdapterLinkRecordingIntentPolicy: Sendable {
    /// 意思の有効期限です(選択を受け取ってから2分)。
    static let standardLifetime: TimeInterval = 2 * 60

    /// 意思の有効期限の秒数です。
    let lifetime: TimeInterval

    /// 有効期限を固定して生成します。
    ///
    /// 責務: 意思の有効期限を判定へ結び付けます。
    /// - Parameter lifetime: 有効期限の秒数。既定は2分。
    init(lifetime: TimeInterval = AdapterLinkRecordingIntentPolicy.standardLifetime) {
        self.lifetime = lifetime
    }

    /// 選択をどう扱うかを返します。
    ///
    /// 責務: 検知待ち・記録中・終了処理中・抑止中は状態機械へ渡し、それ以外(待機・初期化中・確認中・VIN読取中)は、
    /// 監視の停止・未サインイン・既定のBLEアダプターなしなら捨て、処理できれば意思として保持します。
    /// - Parameters:
    ///   - state: 選択を受け取った時の監視状態。
    ///   - conditions: 稼働条件。
    /// - Returns: 判定結果。
    func disposition(
        for state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkRecordingSelectionDisposition {
        switch state {
        case .vehicleDetected(_, .awaitingRecordingStart), .recording, .finishing, .heldAfterUserStop:
            return .forwardToTransition
        case .standby, .initializing, .confirmingVehicle, .vehicleDetected(_, .readingVIN):
            guard let reason = rejectionReason(conditions) else { return .keepAsIntent }
            return .reject(reason)
        }
    }

    /// 稼働条件から、意思を処理できない理由を返します。
    ///
    /// 責務: 監視の停止(検知できない)・未サインイン・既定のBLEアダプターなしを、この順に判定します。
    /// - Parameter conditions: 稼働条件。
    /// - Returns: 処理できない理由。処理できるなら `nil`。
    func rejectionReason(_ conditions: AdapterLinkSupervisionConditions) -> AdapterLinkRecordingStartFailureReason? {
        if !conditions.isSupervisionStarted { return .vehicleNotDetected }
        if !conditions.isSignedIn { return .signInRequired }
        if case .none = conditions.operatingPreference { return .adapterNotConfigured }
        return nil
    }

    /// 意思が有効期限内かどうかを返します。
    ///
    /// 責務: 選択からの経過が有効期限以下(ちょうど2分を含む)なら有効と判定します。
    /// - Parameters:
    ///   - intent: 保持している意思。
    ///   - now: 判定する時刻。
    /// - Returns: 有効なら `true`。
    func isValid(_ intent: AdapterLinkRecordingIntent, now: Date) -> Bool {
        now.timeIntervalSince(intent.selectedAt) <= lifetime
    }

    /// 有効期限の満了を確かめる待ちの長さを返します。
    ///
    /// 責務: ちょうど2分は有効なので、それを1ミリ秒超えた時点で確かめる長さを返します。
    var expiryCheckDelay: Duration {
        .milliseconds(Int64((lifetime * 1000).rounded()) + 1)
    }
}
