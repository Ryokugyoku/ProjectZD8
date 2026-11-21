import Foundation

/// 規制の判定・判定できない理由・規制の種類から、ローカライズキー(`String`)を返します。
///
/// どのキーも書式の引数を持ちません(数値は表示側で別に並べます)。判定できない判定は、その理由のキーを返します。
nonisolated struct RoadRegulationVerdictTextKeys: Sendable {
    /// キーの共通の接頭辞です。
    private static let prefix = "road_regulation"

    /// 状態を持たないキーの選択器を作ります。
    ///
    /// 責務: 定数だけでキーを決める選択器を用意します。
    init() {}

    /// 最高速度の判定のキーを返します。
    ///
    /// 責務: 制限内・超過・指定なしのキーと、判定できない時の理由のキーを選びます。
    /// - Parameter verdict: 判定。
    /// - Returns: ローカライズキー。
    func key(for verdict: SpeedLimitVerdict) -> String {
        switch verdict {
        case .withinLimit: Self.verdictKey("speed_limit", "within_limit")
        case .exceeded: Self.verdictKey("speed_limit", "exceeded")
        case .unregulated: Self.verdictKey("speed_limit", "unregulated")
        case .undeterminable(let reason): key(for: reason)
        }
    }

    /// 一時停止の判定のキーを返します。
    ///
    /// 責務: 停止・停止していないのキーと、判定できない時の理由のキーを選びます。
    /// - Parameter verdict: 判定。
    /// - Returns: ローカライズキー。
    func key(for verdict: StopVerdict) -> String {
        switch verdict {
        case .stopped: Self.verdictKey("stop", "stopped")
        case .notStopped: Self.verdictKey("stop", "not_stopped")
        case .undeterminable(let reason): key(for: reason)
        }
    }

    /// 一方通行の判定のキーを返します。
    ///
    /// 責務: 向きどおり・逆走の可能性のキーと、判定できない時の理由のキーを選びます。
    /// - Parameter verdict: 判定。
    /// - Returns: ローカライズキー。
    func key(for verdict: OneWayVerdict) -> String {
        switch verdict {
        case .followedDirection: Self.verdictKey("one_way", "followed_direction")
        case .possibleWrongWay: Self.verdictKey("one_way", "possible_wrong_way")
        case .undeterminable(let reason): key(for: reason)
        }
    }

    /// 徐行の判定のキーを返します。
    ///
    /// 責務: 観測した速さのキーと、判定できない時の理由のキーを選びます。
    /// - Parameter verdict: 判定。
    /// - Returns: ローカライズキー。
    func key(for verdict: SlowDownVerdict) -> String {
        switch verdict {
        case .observed: Self.verdictKey("slow_down", "observed")
        case .undeterminable(let reason): key(for: reason)
        }
    }

    /// 判定できない理由のキーを返します。
    ///
    /// 責務: `road_regulation.undetermined.<case 名の snake_case>` を作ります。
    /// - Parameter reason: 理由。
    /// - Returns: ローカライズキー。
    func key(for reason: RoadRegulationUndeterminedReason) -> String {
        "\(Self.prefix).undetermined.\(Self.snakeCase(reason.rawValue))"
    }

    /// 規制の種類のキーを返します。
    ///
    /// 責務: 最高速度(区間・可変区間・区域)・一時停止・一方通行・徐行の4つのキーへ対応付けます。
    /// - Parameter kind: 規制の種別。
    /// - Returns: ローカライズキー。
    func kindKey(for kind: RoadRegulationKind) -> String {
        let name = switch kind {
        case .speedLimitSection, .speedLimitVariableSection, .speedLimitZone: "speed_limit"
        case .stop: "stop"
        case .oneWay: "one_way"
        case .slowDown: "slow_down"
        }
        return "\(Self.prefix).kind.\(name)"
    }

    /// 判定のキーを作ります。
    ///
    /// 責務: `road_regulation.verdict.<種類>.<判定>` を作ります。
    /// - Parameters:
    ///   - kind: 種類の部分。
    ///   - verdict: 判定の部分。
    /// - Returns: ローカライズキー。
    private static func verdictKey(_ kind: String, _ verdict: String) -> String {
        "\(prefix).verdict.\(kind).\(verdict)"
    }

    /// lowerCamelCase の名前を snake_case にします。
    ///
    /// 責務: 大文字の前に `_` を入れて小文字にします。
    /// - Parameter name: 名前。
    /// - Returns: snake_case の名前。
    private static func snakeCase(_ name: String) -> String {
        name.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }
}
