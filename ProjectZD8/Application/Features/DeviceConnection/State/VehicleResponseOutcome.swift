/// 車両確認でECUから応答が得られたかどうかの結果です。
nonisolated enum VehicleResponseOutcome: Equatable, Sendable {
    /// ECUが要求へ応答しました。車両の検知として扱います。
    case responding

    /// 指定したタイムアウト内にECUの応答がありませんでした。
    case noResponse
}
