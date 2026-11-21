import Foundation

/// 選んだ指標の区分の境界から、地図の凡例の項目を作ります。
///
/// 色だけに頼らないよう、各項目は範囲の数値と単位を文字で持ちます。
/// - 最初の区分は「境界 未満」、間の区分は「下限〜上限」、最後の区分は「境界 以上」です(下限を含み上限を含まない)。
/// - 数値はロケールに合わせ、小数は0〜1桁で表します。単位はローカライズしません。
/// - 「値なし」の項目は、必要な時だけ最後に足します。
nonisolated struct RouteAnalysisLegendBuilder: Sendable {
    /// 最初の区分(境界 未満)の書式キーです。
    private static let belowKey = "analysis.route.legend.below"
    /// 間の区分(下限〜上限)の書式キーです。
    private static let rangeKey = "analysis.route.legend.range"
    /// 最後の区分(境界 以上)の書式キーです。
    private static let atLeastKey = "analysis.route.legend.at_least"
    /// 「値なし」の項目のキーです。
    private static let noValueKey = "analysis.route.legend.no_value"

    /// 数値の書式に使うロケールです。
    private let locale: Locale

    /// 数値の書式に使うロケールを固定して作ります。
    ///
    /// 責務: 凡例の数値の書式のロケールを保持します。
    /// - Parameter locale: 数値の書式のロケール(既定は現在のロケール)。
    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// 指標の区分ごとの凡例の項目を作ります。
    ///
    /// 責務: 区分の番号の順に範囲の文字を作り、includesNoValue が `true` なら「値なし」を最後に足します。
    /// - Parameters:
    ///   - metric: 色分けに使う指標。
    ///   - unit: 数値に付ける単位。空白だけなら指標の既定の単位を使います。
    ///   - includesNoValue: 「値なし」の項目を足すなら `true`。
    /// - Returns: 0 から表示順に番号を振った項目(区分の数、または区分の数 + 1)。
    func legend(metric: RouteAnalysisColorMetric, unit: String, includesNoValue: Bool) -> [RouteAnalysisLegendEntry] {
        let boundaries = metric.bands.boundaries
        let resolvedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? metric.fallbackUnit : unit
        var entries = (0...boundaries.count).map { step in
            RouteAnalysisLegendEntry(id: step, category: .ramp(step: step), text: text(step: step, boundaries: boundaries, unit: resolvedUnit))
        }
        if includesNoValue {
            entries.append(RouteAnalysisLegendEntry(id: entries.count, category: .noValue, text: String(localized: String.LocalizationValue(Self.noValueKey))))
        }
        return entries
    }

    /// 1つの区分の範囲の文字を作ります。
    ///
    /// 責務: 最初の区分は上限だけ、最後の区分は下限だけ、間の区分は下限と上限(単位は上限の後だけ)を書式に入れます。
    /// - Parameters:
    ///   - step: 区分の番号(0...境界の数)。
    ///   - boundaries: 狭義の昇順の境界(1つ以上)。
    ///   - unit: 数値に付ける単位。
    /// - Returns: 範囲の文字。
    private func text(step: Int, boundaries: [Double], unit: String) -> String {
        if step == 0 {
            return formatted(Self.belowKey, measurement(boundaries[0], unit: unit))
        }
        if step == boundaries.count {
            return formatted(Self.atLeastKey, measurement(boundaries[step - 1], unit: unit))
        }
        return formatted(Self.rangeKey, number(boundaries[step - 1]), measurement(boundaries[step], unit: unit))
    }

    /// 書式キーに文字の引数を入れます。
    ///
    /// 責務: キーのローカライズ済みの書式に、ロケールを指定して引数を埋め込みます。
    /// - Parameters:
    ///   - key: 書式のローカライズキー。
    ///   - arguments: 埋め込む文字(`%1$@`、`%2$@` の順)。
    /// - Returns: 埋め込んだ文字。
    private func formatted(_ key: String, _ arguments: String...) -> String {
        String(format: String(localized: String.LocalizationValue(key)), locale: locale, arguments: arguments)
    }

    /// 数値と単位を空白でつないだ文字を作ります。
    ///
    /// 責務: ロケールに合わせた数値の後に単位を付けます。
    /// - Parameters:
    ///   - value: 数値。
    ///   - unit: 単位。
    /// - Returns: 「数値 単位」の文字。
    private func measurement(_ value: Double, unit: String) -> String {
        "\(number(value)) \(unit)"
    }

    /// 数値をロケールに合わせた文字にします。
    ///
    /// 責務: 小数0〜1桁、ロケールの桁区切りで数値を書きます。
    /// - Parameter value: 数値。
    /// - Returns: 数値の文字。
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}
