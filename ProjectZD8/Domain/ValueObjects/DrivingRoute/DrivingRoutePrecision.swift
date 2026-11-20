/// 走行ルートの区間を描く位置の精度の段階です。区間ごとに一定で、線の種類(実線 / 破線)を決めます。
nonisolated enum DrivingRoutePrecision: Equatable, Sendable {
    /// 正確な位置(精度を下げていない取得)。
    case precise
    /// 概略の位置(精度を下げた取得)。
    case approximate
}
