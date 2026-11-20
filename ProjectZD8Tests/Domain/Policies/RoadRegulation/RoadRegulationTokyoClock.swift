import Foundation
@testable import ProjectZD8

/// 交通規制の条件のテストで、日本時間の日時を作る補助です。端末のタイムゾーンには依存しません。
enum RoadRegulationTokyoClock {
    /// 西暦・`Asia/Tokyo` の暦です(本番の実装とは独立に、テスト側で組み立てます)。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3_600) ?? .gmt
        return calendar
    }()

    /// 責務: 日本時間の年月日と時刻から `Date` を作ります。作れなければテストを止めます。
    /// - Parameters:
    ///   - year: 西暦年。
    ///   - month: 月。
    ///   - day: 日。
    ///   - hour: 時(0〜23)。
    ///   - minute: 分。
    /// - Returns: その日本時間の時刻を指す `Date`。
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        guard let date = calendar.date(from: components) else {
            fatalError("日本時間の日時を作れません: \(year)-\(month)-\(day) \(hour):\(minute)")
        }
        return date
    }

    /// 2026年11月の水曜(18日)です。
    static func wednesday(_ hour: Int = 12, _ minute: Int = 0) -> Date { date(2026, 11, 18, hour, minute) }
    /// 2026年11月の土曜(21日)です。
    static func saturday(_ hour: Int = 12, _ minute: Int = 0) -> Date { date(2026, 11, 21, hour, minute) }
    /// 2026年11月の日曜(22日)です。
    static func sunday(_ hour: Int = 12, _ minute: Int = 0) -> Date { date(2026, 11, 22, hour, minute) }
}
