/// 取得エンジンが使う単調増加時計と待機の契約です。
nonisolated protocol AcquisitionClock: Sendable {
    /// 責務: 任意の起点からの単調増加する経過時間(マイクロ秒)を返します。
    func nowMicroseconds() -> Int64
    /// 責務: 指定時間だけ待機します。
    func sleep(microseconds: Int64) async
}
