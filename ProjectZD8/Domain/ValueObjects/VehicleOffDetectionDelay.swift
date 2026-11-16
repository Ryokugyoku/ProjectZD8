/// 車両の応答が無くなってから、エンジン停止(車両応答なし)とみなして取得を終えるまでの時間です。
///
/// 最後の受信からの経過がこの時間に達し、かつアダプター自体は応答している場合に、3分の猶予を待たずに取得を終えます。
nonisolated enum VehicleOffDetectionDelay: Int, CaseIterable, Identifiable, Equatable, Sendable {
    /// 10秒です。
    case seconds10 = 10
    /// 30秒です(既定)。
    case seconds30 = 30
    /// 60秒です。
    case seconds60 = 60
    /// 180秒です。
    case seconds180 = 180

    /// 未設定の場合に使う既定の時間です。
    static let `default`: VehicleOffDetectionDelay = .seconds30

    /// 一覧表示とアクセシビリティ参照に使う安定識別子です。
    var id: Int { rawValue }

    /// 時間をナノ秒で返します。
    ///
    /// 責務: 単調時計の値と比較できるよう、秒数をナノ秒へ変換します。
    var nanoseconds: UInt64 {
        UInt64(rawValue) * 1_000_000_000
    }
}
