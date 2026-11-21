import Foundation

/// 交通規制データの設定画面・管理画面の、値を差し込む文言を作る純粋型です(SwiftUI に依存しない)。
///
/// - 書式はローカライズキーから引き(既定は String Catalog)、値はロケールに合わせて差し込みます。
/// - 基準月は西暦の年と月(日を含まない)、日付は西暦の年月日(時刻を含まない)で表します。
/// - 進み具合は 0...1 に切り詰めて、小数なしの百分率で表します。
nonisolated struct RoadRegulationSettingsTextFormatter: Sendable {
    /// 基準月の書式キー(`%@` に基準月)。
    static let dataMonthKey = "road_regulation.detail.data_month"
    /// 取得日の書式キー(`%@` に日付)。
    static let downloadedAtKey = "road_regulation.detail.downloaded_at"
    /// 規制の件数の書式キー(`%lld` に件数)。
    static let regulationCountKey = "road_regulation.detail.count"
    /// 捨てた行の件数の書式キー(`%lld` に件数)。
    static let rejectedCountKey = "road_regulation.detail.rejected"

    /// ローカライズキーを書式文字列へ解決する処理。
    private let localizedFormat: @Sendable (String) -> String
    /// 値を差し込む時のロケール。
    private let locale: Locale
    /// 日付を表す時のタイムゾーン。
    private let timeZone: TimeZone

    /// 書式の解決・ロケール・タイムゾーンを固定して作ります。
    ///
    /// 責務: 文言の整形に使うロケール依存の処理を1組にまとめます。
    /// - Parameters:
    ///   - localizedFormat: ローカライズキーを書式文字列へ解決する処理。既定は String Catalog の参照。
    ///   - locale: 値を差し込む時のロケール。
    ///   - timeZone: 日付を表す時のタイムゾーン。
    init(
        localizedFormat: @escaping @Sendable (String) -> String = { String(localized: String.LocalizationValue($0)) },
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.localizedFormat = localizedFormat
        self.locale = locale
        self.timeZone = timeZone
    }

    /// 設定画面のカードのまとめの文言を作ります。
    ///
    /// 責務: 取得済みが無ければ「ありません」を、あれば件数と最も古い基準月を差し込んだ文言を返します。
    /// - Parameter summary: まとめ。
    /// - Returns: まとめの文言。
    func summaryText(_ summary: RoadRegulationSettingsSummary) -> String {
        guard summary.downloadedCount > 0, let month = summary.oldestDataMonth else {
            return localizedFormat("road_regulation.settings.summary.none")
        }
        return String(format: localizedFormat(summary.summaryKey), locale: locale, summary.downloadedCount, dataMonthText(month))
    }

    /// 版の基準月の行の文言を作ります。
    ///
    /// 責務: 基準月を書式へ差し込みます。
    /// - Parameter dataset: 有効な版。
    /// - Returns: 基準月の行の文言。
    func dataMonthLine(_ dataset: RoadRegulationDataset) -> String {
        String(format: localizedFormat(Self.dataMonthKey), locale: locale, dataMonthText(dataset.dataMonth))
    }

    /// 版の取得日の行の文言を作ります。
    ///
    /// 責務: ZIP を受け取った日付を書式へ差し込みます。
    /// - Parameter dataset: 有効な版。
    /// - Returns: 取得日の行の文言。
    func downloadedAtLine(_ dataset: RoadRegulationDataset) -> String {
        String(format: localizedFormat(Self.downloadedAtKey), locale: locale, dateText(dataset.downloadedAt))
    }

    /// 版の規制の件数の行の文言を作ります。
    ///
    /// 責務: 取り込んだ規制の件数を書式へ差し込みます。
    /// - Parameter dataset: 有効な版。
    /// - Returns: 規制の件数の行の文言。
    func regulationCountLine(_ dataset: RoadRegulationDataset) -> String {
        String(format: localizedFormat(Self.regulationCountKey), locale: locale, dataset.counts.importedRegulations)
    }

    /// 版の捨てた行の件数の行の文言を作ります。
    ///
    /// 責務: 解釈できずに捨てた行の件数(理由ごとの合計)を書式へ差し込みます。
    /// - Parameter dataset: 有効な版。
    /// - Returns: 捨てた行の件数の行の文言。
    func rejectedCountLine(_ dataset: RoadRegulationDataset) -> String {
        String(format: localizedFormat(Self.rejectedCountKey), locale: locale, dataset.counts.rejectedRows)
    }

    /// 出典の利用日の文言を作ります。
    ///
    /// 責務: 利用日があれば日付を書式へ差し込みます。
    /// - Parameter attribution: 出典の表示。
    /// - Returns: 利用日の文言。取得済みが無ければ `nil`。
    func usedOnText(_ attribution: RoadRegulationAttribution) -> String? {
        attribution.usedOn.map { String(format: localizedFormat(RoadRegulationAttribution.usedOnKey), locale: locale, dateText($0)) }
    }

    /// 取り込みの進み具合を百分率の文言にします。
    ///
    /// 責務: 0...1 に切り詰め、小数なしの百分率で表します。有限でなければ 0 とみなします。
    /// - Parameter fraction: 進み具合。
    /// - Returns: 百分率の文言。
    func progressPercentText(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// 基準月を年と月の文言にします。
    ///
    /// 責務: 西暦の年と月を、ロケールに合わせた書式で表します。
    /// - Parameter month: 基準月。
    /// - Returns: 基準月の文言。
    func dataMonthText(_ month: RoadRegulationDataMonth) -> String {
        let calendar = gregorianCalendar
        guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return String(format: "%04d-%02d", month.year, month.month)
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).year().month(.wide)
        return date.formatted(style)
    }

    /// 日時を年月日の文言にします。
    ///
    /// 責務: 西暦の年月日を、ロケールに合わせた短めの書式で表します(時刻は出しません)。
    /// - Parameter date: 日時。
    /// - Returns: 日付の文言。
    func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: gregorianCalendar, timeZone: timeZone))
    }

    /// 書式に使う西暦の暦(タイムゾーンを合わせたもの)。
    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
