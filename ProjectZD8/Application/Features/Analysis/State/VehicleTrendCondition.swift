/// 長期傾向の集計に使う運転条件です。
nonisolated enum VehicleTrendCondition: String, Codable, CaseIterable, Sendable {
    /// 全走行(条件なし)。
    case all
    /// 暖機後のアイドル(停車・低回転・水温80℃以上)。
    case warmIdle
    /// 安定巡航(時速40km以上で3秒前との差が3km/h以内)。
    case steadyCruise
}
