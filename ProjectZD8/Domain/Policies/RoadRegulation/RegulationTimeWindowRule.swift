import Foundation

/// JARTIC の規制時間(hhmm、先頭0なし)と曜日コードの組が、ある時刻(日本時間)に当てはまるかを判定します。
///
/// 開始 < 終了なら [開始, 終了)。開始 > 終了なら日付をまたぐ時間帯で、終了より前の時刻は前日の曜日で判定します
/// (仕様書: 曜日コードは規制の開始時間における曜日)。開始 = 終了と「0〜2400」は終日です。
nonisolated struct RegulationTimeWindowRule: Sendable {
    /// 1日の分数(24:00 を表す値)。
    private static let minutesPerDay = 1_440
    /// hhmm の時の部分の上限(24:00 の 24)。
    private static let maximumHour = 24
    /// hhmm の分の部分の数(分は 0...59)。
    private static let minutesPerHour = 60
    /// hhmm の最大の桁数。
    private static let maximumDigits = 4
    /// ASCII の数字(`0`〜`9`)のバイトの範囲。
    private static let asciiDigits: ClosedRange<UInt8> = 0x30...0x39

    /// 判定の規則を作ります。
    ///
    /// 責務: 状態を持たない規則を用意します。
    init() {}

    /// 時間帯と曜日の組が、指定の時刻に当てはまるかを返します。
    ///
    /// 責務: 時間帯の種類(終日・同じ日の中・日付をまたぐ)を決め、時間帯の中なら曜日を該当する日で判定します。
    /// - Parameters:
    ///   - start: 規制時間の開始(hhmm)。
    ///   - end: 規制時間の終了(hhmm)。
    ///   - dayCode: 規制曜日コード。
    ///   - date: 判定する時刻。
    ///   - dayRule: 曜日の判定に使う規則。
    /// - Returns: 時間帯の外なら `doesNotApply`。開始・終了の片方だけがある、または解釈できない値なら `unknown`。
    func evaluate(start: String?, end: String?, dayCode: String?, at date: Date, dayRule: RegulationDayRule) -> RegulationApplicability {
        if start == nil, end == nil {
            return dayRule.evaluate(dayCode: dayCode, on: date)
        }
        guard let startMinute = start.flatMap(Self.minuteOfDay), let endMinute = end.flatMap(Self.minuteOfDay) else {
            return .unknown
        }
        guard let dayOfWindow = Self.dayOfWindow(containing: date, startMinute: startMinute, endMinute: endMinute) else {
            return .doesNotApply
        }
        return dayRule.evaluate(dayCode: dayCode, on: dayOfWindow)
    }

    /// 時刻が時間帯の中にあれば、曜日を判定する日の時刻を返します。
    ///
    /// 責務: 終日・同じ日の中・日付をまたぐ時間帯ごとに、時刻が中にあるかと、曜日を見る日(当日か前日)を決めます。
    /// - Parameters:
    ///   - date: 判定する時刻。
    ///   - startMinute: 開始(0 時からの分)。
    ///   - endMinute: 終了(0 時からの分)。
    /// - Returns: 時間帯の外なら `nil`。日付をまたぐ時間帯の終了前なら前日の同じ時刻。
    private static func dayOfWindow(containing date: Date, startMinute: Int, endMinute: Int) -> Date? {
        let startSecond = startMinute * 60
        let endSecond = endMinute * 60
        let second = secondOfDay(date)
        if startMinute == endMinute { return date }
        if startMinute < endMinute {
            return (startSecond..<endSecond).contains(second) ? date : nil
        }
        if second >= startSecond { return date }
        return second < endSecond ? previousDay(of: date) : nil
    }

    /// hhmm の文字列を 0 時からの分に直します。
    ///
    /// 責務: 1〜4桁の ASCII 数字だけを受け付け、分が 60 以上・2400 超を拒みます。
    /// - Parameter text: hhmm(先頭0なし)。
    /// - Returns: 0...1440 の分。解釈できなければ `nil`。
    private static func minuteOfDay(_ text: String) -> Int? {
        guard (1...maximumDigits).contains(text.count), text.utf8.allSatisfy(Self.asciiDigits.contains), let value = Int(text) else { return nil }
        let hour = value / 100
        let minute = value % 100
        guard minute < minutesPerHour, hour <= maximumHour else { return nil }
        let total = hour * minutesPerHour + minute
        return total <= minutesPerDay ? total : nil
    }

    /// 日本時間での 0 時からの経過秒を返します。
    ///
    /// 責務: 固定の暦で時・分・秒を取り出し、秒に直します。
    /// - Parameter date: 時刻。
    /// - Returns: 0..<86400 の秒。
    private static func secondOfDay(_ date: Date) -> Int {
        let parts = RegulationDayRule.calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3_600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// 前日の同じ時刻を返します。
    ///
    /// 責務: 固定の暦で1日戻します(日本に夏時間は無いため、求められない時は 24 時間戻します)。
    /// - Parameter date: 時刻。
    /// - Returns: 前日の同じ時刻。
    private static func previousDay(of date: Date) -> Date {
        RegulationDayRule.calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
    }
}

