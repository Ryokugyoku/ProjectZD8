import Foundation

/// JARTIC の規制期間(MMDD、先頭0なし)が、ある時刻(日本時間)の日に当てはまるかを判定します。
///
/// 両端を含みます。開始 > 終了なら年をまたぐ期間です(例: 1201〜228 は 12月1日〜2月28日)。
nonisolated struct RegulationPeriodRule: Sendable {
    /// MMDD の最小・最大の桁数(1月1日 = "101"、12月31日 = "1231")。
    private static let digitCountRange = 3...4
    /// ASCII の数字(`0`〜`9`)のバイトの範囲。
    private static let asciiDigits: ClosedRange<UInt8> = 0x30...0x39
    /// 月ごとの最大の日(2月は閏年の 29 日まで受け付ける)。
    private static let maximumDayByMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// 判定の規則を作ります。
    ///
    /// 責務: 状態を持たない規則を用意します。
    init() {}

    /// 期間が、指定の時刻が属する日に当てはまるかを返します。
    ///
    /// 責務: 開始・終了を月日に直し、日本時間の月日が期間(両端を含み、年をまたぐ場合を含む)の中かを判定します。
    /// - Parameters:
    ///   - start: 期間の開始(MMDD)。
    ///   - end: 期間の終了(MMDD)。
    ///   - date: 判定する時刻。
    /// - Returns: 両方とも無ければ `applies`。片方だけ、または解釈できない値なら `unknown`。
    func evaluate(start: String?, end: String?, at date: Date) -> RegulationApplicability {
        if start == nil, end == nil { return .applies }
        guard let startDay = start.flatMap(Self.monthDay), let endDay = end.flatMap(Self.monthDay) else { return .unknown }
        let parts = RegulationDayRule.calendar.dateComponents([.month, .day], from: date)
        let today = (parts.month ?? 0) * 100 + (parts.day ?? 0)
        let isInside = startDay <= endDay
            ? (startDay...endDay).contains(today)
            : today >= startDay || today <= endDay
        return isInside ? .applies : .doesNotApply
    }

    /// MMDD の文字列を `月 × 100 + 日` に直します。
    ///
    /// 責務: 3〜4桁の ASCII 数字だけを受け付け、月 1...12 と、その月にあり得る日だけを通します。
    /// - Parameter text: MMDD(先頭0なし)。
    /// - Returns: `月 × 100 + 日`。解釈できなければ `nil`。
    private static func monthDay(_ text: String) -> Int? {
        guard digitCountRange.contains(text.count), text.utf8.allSatisfy(asciiDigits.contains), let value = Int(text) else {
            return nil
        }
        let month = value / 100
        let day = value % 100
        guard (1...12).contains(month), (1...maximumDayByMonth[month - 1]).contains(day) else { return nil }
        return value
    }
}
