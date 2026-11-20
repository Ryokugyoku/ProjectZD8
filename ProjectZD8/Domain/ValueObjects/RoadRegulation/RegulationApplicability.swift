import Foundation

/// 規制の条件がいまの走行に当てはまるかの3値です。組み合わせはクリーネの3値論理に従います。
nonisolated enum RegulationApplicability: Equatable, Sendable {
    /// 当てはまる。
    case applies
    /// 当てはまらない。
    case doesNotApply
    /// 当てはまるか分からない。
    case unknown

    /// 論理積を返します。
    ///
    /// 責務: どちらかが `doesNotApply` なら `doesNotApply`、両方 `applies` なら `applies`、それ以外は `unknown` にします。
    /// - Parameter other: 右辺。
    /// - Returns: 3値の論理積。
    func and(_ other: RegulationApplicability) -> RegulationApplicability {
        if self == .doesNotApply || other == .doesNotApply { return .doesNotApply }
        return self == .applies && other == .applies ? .applies : .unknown
    }

    /// 論理和を返します。
    ///
    /// 責務: どちらかが `applies` なら `applies`、両方 `doesNotApply` なら `doesNotApply`、それ以外は `unknown` にします。
    /// - Parameter other: 右辺。
    /// - Returns: 3値の論理和。
    func or(_ other: RegulationApplicability) -> RegulationApplicability {
        negated.and(other.negated).negated
    }

    /// 否定です(`applies` と `doesNotApply` を入れ替え、`unknown` はそのまま)。
    var negated: RegulationApplicability {
        switch self {
        case .applies: .doesNotApply
        case .doesNotApply: .applies
        case .unknown: .unknown
        }
    }
}
