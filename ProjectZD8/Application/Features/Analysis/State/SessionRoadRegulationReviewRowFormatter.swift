import Foundation

/// 交通規制の照合の行に出す時刻と数値の文字列を作ります。
///
/// - 時刻は 24 時間制の `HH:mm:ss`(西暦の暦・指定のタイムゾーン)です。開始と終了が同じ秒なら1つ、違えば `開始–終了`(U+2013、空白なし)です。
/// - 数値はロケールの小数点・桁区切りで、速度と時間は小数 0〜1 桁、距離は小数 0 桁です。単位(km/h・m)はローカライズしません。
/// - 有限でない値と、その種類で使わない項目は出しません。
nonisolated struct SessionRoadRegulationReviewRowFormatter: Sendable {
    /// 書式のキーの共通の接頭辞です。
    private static let keyPrefix = "analysis.road_regulation."
    /// 時刻の範囲の区切り(U+2013)です。
    private static let rangeSeparator = "\u{2013}"

    /// 数値と時刻の書式に使うロケールです。
    private let locale: Locale
    /// 時刻に使うタイムゾーンです。
    private let timeZone: TimeZone
    /// ローカライズキーを書式の文字列へ解決する関数です。
    private let localize: @Sendable (String) -> String

    /// 書式のロケール・タイムゾーン・キーの解決方法を固定して作ります。
    ///
    /// 責務: 時刻と数値の書式に使う設定を保持します。
    /// - Parameters:
    ///   - locale: 数値と時刻の書式のロケール(既定は現在のロケール)。
    ///   - timeZone: 時刻のタイムゾーン(既定は現在のタイムゾーン)。
    ///   - localize: キーを書式の文字列へ解決する関数(既定はアプリの文字列表)。
    init(
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        localize: @escaping @Sendable (String) -> String = { String(localized: String.LocalizationValue($0)) }
    ) {
        self.locale = locale
        self.timeZone = timeZone
        self.localize = localize
    }

    /// 区間の時刻の文字列を作ります。
    ///
    /// 責務: 開始と終了を `HH:mm:ss` にし、同じ秒なら1つ、違えば区切りでつなぎます。
    /// - Parameter range: 区間の時刻の範囲。
    /// - Returns: 時刻の文字列(例 `10:21:05–10:21:40`)。
    func timeText(_ range: ClosedRange<Date>) -> String {
        let start = clockText(range.lowerBound)
        let end = clockText(range.upperBound)
        return start == end ? start : "\(start)\(Self.rangeSeparator)\(end)"
    }

    /// 種類ごとに決まった順で、数値の文字列を作ります。
    ///
    /// 責務: その種類で使う項目のうち、値があり有限なものだけを書式のキーに入れて並べます。
    /// - Parameters:
    ///   - figures: 判定に添える数値。
    ///   - kind: 規制の種類。
    /// - Returns: 解決済みの文字列(該当が無ければ空)。
    func figureTexts(_ figures: SessionRoadRegulationReviewFigures, kind: SessionRoadRegulationReviewKind) -> [String] {
        figureParts(figures, kind: kind).compactMap { key, value in
            value.map { formatted(key, $0) }
        }
    }

    /// 種類ごとの項目の書式のキーと値の文字列を、表示の順に返します。
    ///
    /// 責務: 種類で使う項目だけを選び、値を単位つきの文字列にします(値が無い・有限でない時は `nil`)。
    /// - Parameters:
    ///   - figures: 判定に添える数値。
    ///   - kind: 規制の種類。
    /// - Returns: 書式のキー(接頭辞なし)と値の文字列の組。
    private func figureParts(_ figures: SessionRoadRegulationReviewFigures, kind: SessionRoadRegulationReviewKind) -> [(String, String?)] {
        switch kind {
        case .speedLimit:
            [
                ("figure.limit", speed(figures.limitKph.map(Double.init))),
                ("figure.maximum", speed(figures.maximumKph)),
                ("figure.exceeded_duration", decimal(figures.exceededSeconds)),
            ]
        case .stop:
            [("figure.minimum", speed(figures.minimumKph))]
        case .oneWay:
            [("figure.wrong_way_distance", distance(figures.wrongWayDistanceMeters))]
        case .slowDown:
            [("figure.maximum", speed(figures.maximumKph)), ("figure.reference", speed(figures.referenceKph))]
        }
    }

    /// 書式のキーに値の文字列を入れます。
    ///
    /// 責務: 接頭辞を付けたキーを解決し、ロケールを指定して値を埋め込みます。
    /// - Parameters:
    ///   - key: 接頭辞を除いた書式のキー。
    ///   - value: 埋め込む文字列。
    /// - Returns: 埋め込んだ文字列。
    private func formatted(_ key: String, _ value: String) -> String {
        String(format: localize(Self.keyPrefix + key), locale: locale, value)
    }

    /// 速さを「数値 km/h」にします。
    ///
    /// 責務: 有限な値だけを小数 0〜1 桁の数値と単位にします。
    /// - Parameter value: 速さ(km/h)。
    /// - Returns: 文字列。値が無い・有限でない時は `nil`。
    private func speed(_ value: Double?) -> String? {
        decimal(value).map { "\($0) km/h" }
    }

    /// 距離を「数値 m」にします。
    ///
    /// 責務: 有限な値だけを小数 0 桁の数値と単位にします。
    /// - Parameter value: 距離(m)。
    /// - Returns: 文字列。値が無い・有限でない時は `nil`。
    private func distance(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return "\(value.formatted(.number.precision(.fractionLength(0)).locale(locale))) m"
    }

    /// 数値を小数 0〜1 桁の文字列にします。
    ///
    /// 責務: 有限な値だけをロケールの小数点・桁区切りで書きます。
    /// - Parameter value: 数値。
    /// - Returns: 文字列。値が無い・有限でない時は `nil`。
    private func decimal(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// 時刻を 24 時間制の `HH:mm:ss` にします。
    ///
    /// 責務: 西暦の暦とタイムゾーンを固定して時・分・秒を2桁で書きます。
    /// - Parameter date: 時刻。
    /// - Returns: `HH:mm:ss` の文字列。
    private func clockText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
        return date.formatted(style)
    }
}
