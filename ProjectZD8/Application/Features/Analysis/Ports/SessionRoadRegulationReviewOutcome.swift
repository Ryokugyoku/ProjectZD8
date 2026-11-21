import Foundation

/// 1件の判定の分類です。宣言の順が「まとめ」「凡例」の並びと、重ね合わせの色の優先順です。
nonisolated enum SessionRoadRegulationReviewOutcome: String, CaseIterable, Sendable {
    /// 超過の可能性・停止していない可能性・逆走の可能性があります。
    case possibleIssue
    /// 判定できません。
    case undeterminable
    /// 制限内・停止した・指定の向きです。
    case compliant
    /// 徐行区間を通過しました(数値と目安だけを示し、良否を言いません)。
    case observedOnly
    /// 規制の指定がありません(最高速度だけ)。
    case unregulated
}
