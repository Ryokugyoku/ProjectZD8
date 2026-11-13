import Foundation

/// 実時間で動く `AcquisitionClock` です。
nonisolated struct SystemAcquisitionClock: AcquisitionClock {
    private let origin = ContinuousClock.now

    /// 責務: 生成時点を起点とする時計を作ります。
    init() {}

    /// 責務: 生成時点からの経過時間(マイクロ秒)を返します。
    func nowMicroseconds() -> Int64 {
        let components = (ContinuousClock.now - origin).components
        return components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
    }

    /// 責務: 指定時間だけ待機します。取り消された場合は直ちに戻ります。
    func sleep(microseconds: Int64) async {
        guard microseconds > 0 else { return }
        try? await Task.sleep(for: .microseconds(microseconds))
    }
}
