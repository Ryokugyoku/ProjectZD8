/// 重ね合わせ(5c の判定結果など)の区間に使う色調です。
nonisolated enum RouteAnalysisTone: String, CaseIterable, Sendable {
    /// 問題が無いことを示す色調。
    case positive
    /// 中立の色調。
    case neutral
    /// 注意を促す色調(短い区間に限ってオレンジ)。
    case caution
    /// 重大さを示す色調。
    case critical
    /// 判定できないことを示す色調。
    case unknown
}
