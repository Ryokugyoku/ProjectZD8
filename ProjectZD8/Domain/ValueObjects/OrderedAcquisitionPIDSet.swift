/// 取得開始時に固定する順序付きPID集合です。
nonisolated struct OrderedAcquisitionPIDSet: Equatable, Sendable {
    /// 要求順を保持する重複のないService/PID一覧です。
    let requests: [OBDPIDRequest]

    /// 重複を拒否して順序付きPID集合を生成します。
    ///
    /// 責務: 取得対象のService/PIDを入力順のまま一意な集合へ固定します。
    /// - Parameter requests: 取得開始時の要求順に並べたService/PID一覧。
    /// - Throws: 同じService/PIDが複数含まれる場合は `OrderedAcquisitionPIDSetError.duplicateRequest`。
    init(requests: [OBDPIDRequest]) throws {
        guard Set(requests).count == requests.count else {
            throw OrderedAcquisitionPIDSetError.duplicateRequest
        }
        self.requests = requests
    }
}

/// 順序付きPID集合を確定できない理由です。
nonisolated enum OrderedAcquisitionPIDSetError: Error, Equatable, Sendable {
    /// 同じService/PIDが複数指定されています。
    case duplicateRequest
}
