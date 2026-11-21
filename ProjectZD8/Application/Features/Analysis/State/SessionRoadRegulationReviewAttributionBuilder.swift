import Foundation

/// 照合の結果から、出典に添える「使用したデータ」と利用日の文字列を作ります。
///
/// 版は都道府県コードの昇順、同じコードは基準月の昇順に並べ、同じ県と月の重複は1つにします。
nonisolated struct SessionRoadRegulationReviewAttributionBuilder: Sendable {
    /// 版1つの書式のキーです(`%1$@` 県名、`%2$@` 基準月)。
    private static let datasetKey = "analysis.road_regulation.attribution.dataset"
    /// 基準月の書式のキーです(`%1$lld` 年、`%2$lld` 月)。
    private static let dataMonthKey = "analysis.road_regulation.attribution.data_month"
    /// 利用日の書式のキーです(`%@` 日付)。
    private static let usedOnKey = "road_regulation.attribution.used_on"
    /// 都道府県名のキーの接頭辞です(後に2桁のコード)。
    private static let prefectureKeyPrefix = "road_regulation.prefecture."

    /// 書式に使うロケールです。
    private let locale: Locale
    /// 利用日に使うタイムゾーンです。
    private let timeZone: TimeZone
    /// ローカライズキーを書式の文字列へ解決する関数です。
    private let localize: @Sendable (String) -> String

    /// 書式のロケール・タイムゾーン・キーの解決方法を固定して作ります。
    ///
    /// 責務: 版と利用日の書式に使う設定を保持します。
    /// - Parameters:
    ///   - locale: 書式のロケール(既定は現在のロケール)。
    ///   - timeZone: 利用日のタイムゾーン(既定は現在のタイムゾーン)。
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

    /// 照合の結果の出典の内容を作ります。
    ///
    /// 責務: 版を並べて重複を除いた文字列、利用日の文字列、配布ページの URL をまとめます。
    /// - Parameter review: 照合の結果。
    /// - Returns: 出典の内容。
    func attribution(for review: SessionRoadRegulationReview) -> SessionRoadRegulationReviewAttribution {
        SessionRoadRegulationReviewAttribution(
            datasetTexts: Self.orderedUnique(review.datasets).map(datasetText),
            usedOnText: review.usedOn.map(usedOnText),
            sourceURL: review.sourceURL
        )
    }

    /// 版を並べ、同じ県と月の重複を除きます。
    ///
    /// 責務: 都道府県コード → 基準月の昇順に並べ、隣り合う同じ版を1つにします。
    /// - Parameter datasets: 判定に使った版。
    /// - Returns: 並べて重複を除いた版。
    private static func orderedUnique(_ datasets: [RoadRegulationDatasetReference]) -> [RoadRegulationDatasetReference] {
        let sorted = datasets.sorted { ($0.prefecture, $0.dataMonth) < ($1.prefecture, $1.dataMonth) }
        return sorted.reduce(into: []) { unique, dataset in
            if unique.last != dataset { unique.append(dataset) }
        }
    }

    /// 版1つの文字列を作ります。
    ///
    /// 責務: 県名と基準月を版の書式に入れます。基準月の年と月は、ロケールの桁区切りを入れない数字にします。
    /// - Parameter dataset: 版。
    /// - Returns: 「沖縄県(基準月 2026年9月)」などの文字列。
    private func datasetText(_ dataset: RoadRegulationDatasetReference) -> String {
        let prefecture = localize(Self.prefectureKeyPrefix + dataset.prefecture.twoDigitText)
        // locale を渡すと `%lld` に桁区切りが入る(2,026)ため、年と月の整形にはロケールを渡さない。
        let month = String(format: localize(Self.dataMonthKey), dataset.dataMonth.year, dataset.dataMonth.month)
        return String(format: localize(Self.datasetKey), locale: locale, prefecture, month)
    }

    /// 利用日の文字列を作ります。
    ///
    /// 責務: 日付を西暦・数字の形式で書き、利用日の書式に入れます。
    /// - Parameter usedOn: 利用日時。
    /// - Returns: 「利用日: 2026/11/21」などの文字列。
    private func usedOnText(_ usedOn: Date) -> String {
        let style = Date.FormatStyle(
            date: .numeric,
            time: .omitted,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        return String(format: localize(Self.usedOnKey), locale: locale, usedOn.formatted(style))
    }
}
