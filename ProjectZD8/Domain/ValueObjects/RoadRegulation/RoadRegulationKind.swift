import Foundation

/// 取り込んで判定に使う交通規制の種別です。`rawValue` は DB の CHECK 制約に固定されているので変えません。
nonisolated enum RoadRegulationKind: String, CaseIterable, Codable, Sendable {
    /// 最高速度(区間。共通規制種別コード 112)。
    case speedLimitSection
    /// 最高速度(可変区間。113)。
    case speedLimitVariableSection
    /// 最高速度(区域。114)。
    case speedLimitZone
    /// 一時停止(63)。
    case stop
    /// 一方通行(11)。
    case oneWay
    /// 徐行(61)。
    case slowDown

    /// 共通規制種別コードから種別を作ります。
    ///
    /// 責務: 対象の6種のコードだけを種別へ対応付けます。
    /// - Parameter commonCode: JARTIC の共通規制種別コード。
    /// - Returns: 対象外のコードなら `nil`。
    init?(commonCode: Int) {
        guard let kind = Self.allCases.first(where: { $0.commonCode == commonCode }) else { return nil }
        self = kind
    }

    /// JARTIC の共通規制種別コードです。
    var commonCode: Int {
        switch self {
        case .speedLimitSection: 112
        case .speedLimitVariableSection: 113
        case .speedLimitZone: 114
        case .stop: 63
        case .oneWay: 11
        case .slowDown: 61
        }
    }

    /// この種別の行が持つべき形状です(一時停止は点、区域は面、ほかは線)。
    var expectedShape: RoadRegulationShape {
        switch self {
        case .stop: .point
        case .speedLimitZone: .area
        case .speedLimitSection, .speedLimitVariableSection, .oneWay, .slowDown: .line
        }
    }
}
