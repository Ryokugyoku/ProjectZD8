import Foundation

/// JARTIC の規制曜日コードが、ある日(日本時間)に当てはまるかを判定します。
///
/// 暦は西暦(gregorian)・`Asia/Tokyo` に固定し、端末のタイムゾーンには依存しません。
/// 祝日の表は持たないため、祝日に依存して決まる日は `unknown` にします。
nonisolated struct RegulationDayRule: Sendable {
    /// 条件の判定に使う暦(西暦・日本時間)です。時間帯と期間の判定でも共有します。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: japanStandardOffsetSeconds) ?? .gmt
        return calendar
    }()

    /// 日本標準時の UTC からのずれ(秒)。`Asia/Tokyo` を引けない環境での代わりに使います(日本に夏時間は無い)。
    private static let japanStandardOffsetSeconds = 9 * 3_600

    /// 曜日コードごとの、土曜・日曜・平日それぞれの判定の表です(仕様書の共通コード表「曜日コード」)。
    ///
    /// 2(土日休)と3(日休)の平日、3の土曜、6(休日)は祝日か分からないため `unknown` です。
    private static let applicabilityByCode: [Int: DayApplicability] = [
        1: DayApplicability(saturday: .applies, sunday: .applies, weekday: .doesNotApply),
        2: DayApplicability(saturday: .applies, sunday: .applies, weekday: .unknown),
        3: DayApplicability(saturday: .unknown, sunday: .applies, weekday: .unknown),
        4: DayApplicability(saturday: .applies, sunday: .doesNotApply, weekday: .doesNotApply),
        5: DayApplicability(saturday: .doesNotApply, sunday: .applies, weekday: .doesNotApply),
        6: DayApplicability(saturday: .unknown, sunday: .unknown, weekday: .unknown),
    ]

    /// `Calendar` の曜日番号で日曜を表す値です。
    private static let sundayWeekday = 1
    /// `Calendar` の曜日番号で土曜を表す値です。
    private static let saturdayWeekday = 7

    /// 判定の規則を作ります。
    ///
    /// 責務: 状態を持たない規則を用意します。
    init() {}

    /// 曜日コードが指定の日に当てはまるかを返します。
    ///
    /// 責務: 日本時間でその時刻が属する日の曜日を求め、コードの表から3値を引きます。
    /// - Parameters:
    ///   - dayCode: 規制曜日コード。`nil` なら曜日の制約なし。
    ///   - date: 判定する時刻(その時刻が属する日本時間の日で判定します)。
    /// - Returns: コードが無ければ `applies`。表に無いコード(99 を含む)や数字でない値は `unknown`。
    func evaluate(dayCode: String?, on date: Date) -> RegulationApplicability {
        guard let dayCode else { return .applies }
        guard let code = Int(dayCode), let row = Self.applicabilityByCode[code] else { return .unknown }
        return row.applicability(weekday: Self.calendar.component(.weekday, from: date))
    }

    /// 1つの曜日コードの、土曜・日曜・平日ごとの判定です。
    private struct DayApplicability: Sendable {
        /// 土曜の判定。
        let saturday: RegulationApplicability
        /// 日曜の判定。
        let sunday: RegulationApplicability
        /// 月〜金の判定。
        let weekday: RegulationApplicability

        /// 曜日番号に対応する判定を返します。
        ///
        /// 責務: `Calendar` の曜日番号(1 = 日曜、7 = 土曜)を土曜・日曜・平日に分けます。
        /// - Parameter weekday: `Calendar` の曜日番号。
        /// - Returns: その曜日の判定。
        func applicability(weekday: Int) -> RegulationApplicability {
            switch weekday {
            case RegulationDayRule.sundayWeekday: sunday
            case RegulationDayRule.saturdayWeekday: saturday
            default: self.weekday
            }
        }
    }
}
