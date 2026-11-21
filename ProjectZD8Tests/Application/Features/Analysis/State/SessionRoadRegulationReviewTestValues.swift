import Foundation
@testable import ProjectZD8

/// 交通規制の照合結果を解析画面に出す純粋型(段階5c の C1a・C1b)のテストが共有する値です。
///
/// 時刻は `base`(2027-01-15 17:00:00 JST = 1_800_000_000)からの秒で表し、区間の印・行はこの秒と連番から作ります。
/// 文言は言語設定に依存させないため、キーをそのまま包んで返す `localize` を注入します。
enum SessionRoadRegulationReviewTestValues {
    /// 時刻の基準(2027-01-15 08:00:00 UTC = 17:00:00 JST)です。
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    /// 日本時間です。
    static let tokyo = tokyoTimeZone()
    /// 配布ページの URL です。
    static let sourceURL = sourceURLValue()
    /// キーを `<キー>` に包んで返す文言の解決です。
    static let bracketLocalize: @Sendable (String) -> String = { "<\($0)>" }

    /// 日本時間のタイムゾーンを返します。
    ///
    /// 責務: 識別子から作れない環境ではテストの前提が崩れるため、そこで止めます。
    /// - Returns: Asia/Tokyo。
    private static func tokyoTimeZone() -> TimeZone {
        guard let zone = TimeZone(identifier: "Asia/Tokyo") else {
            preconditionFailure("Asia/Tokyo を作れません")
        }
        return zone
    }

    /// 配布ページの URL を返します。
    ///
    /// 責務: テストで受け渡しを確かめる固定の URL を作ります。
    /// - Returns: URL。
    private static func sourceURLValue() -> URL {
        guard let url = URL(string: "https://example.com/road-regulation") else {
            preconditionFailure("URL を作れません")
        }
        return url
    }

    /// 基準から `seconds` 秒後の時刻を返します。
    ///
    /// 責務: 秒の差から時刻を作ります。
    /// - Parameter seconds: 基準からの秒。
    /// - Returns: 時刻。
    static func date(_ seconds: TimeInterval) -> Date {
        base.addingTimeInterval(seconds)
    }

    /// 区間の端の印を作ります。
    ///
    /// 責務: 軸の秒と観測時刻を同じ秒にそろえた印を返します。
    /// - Parameters:
    ///   - seconds: 基準からの秒。
    ///   - sequence: 位置サンプルの連番。
    /// - Returns: 印。
    static func mark(_ seconds: TimeInterval, sequence: Int64) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: seconds, sequence: sequence, observedAt: date(seconds))
    }

    /// 照合結果の1件を作ります。
    ///
    /// 責務: 種類・結果・区間・数値を指定した entry を返します。
    /// - Parameters:
    ///   - kind: 種類。
    ///   - outcome: 結果。
    ///   - verdictKey: 判定の文言キー。
    ///   - reason: 判定できない理由。
    ///   - start: 開始の印。
    ///   - end: 終了の印。
    ///   - figures: 数値。
    /// - Returns: entry。
    static func entry(
        kind: SessionRoadRegulationReviewKind,
        outcome: SessionRoadRegulationReviewOutcome,
        verdictKey: String = "verdict",
        reason: RoadRegulationUndeterminedReason? = nil,
        start: RoadRegulationTransitionMark,
        end: RoadRegulationTransitionMark,
        figures: SessionRoadRegulationReviewFigures = .init()
    ) -> SessionRoadRegulationReviewEntry {
        SessionRoadRegulationReviewEntry(
            kind: kind,
            outcome: outcome,
            verdictKey: verdictKey,
            undeterminedReason: reason,
            start: start,
            end: end,
            figures: figures
        )
    }

    /// 設計書 §3.3 の表どおりの、結果ごとの色の分類を返します。
    ///
    /// 責務: 期待値を製品の表引きに頼らず手で書いた表から返します。
    /// - Parameter outcome: 結果。
    /// - Returns: 色の分類。
    static func category(for outcome: SessionRoadRegulationReviewOutcome) -> RouteAnalysisColorCategory {
        switch outcome {
        case .possibleIssue: .tone(.caution)
        case .undeterminable: .tone(.unknown)
        case .compliant: .tone(.positive)
        case .observedOnly, .unregulated: .tone(.neutral)
        }
    }

    /// 一覧の行を直接作ります(builder を通さない入力)。
    ///
    /// 責務: id・種類・結果・区間の秒と連番を指定した行を返します。色は `category` を省くと表どおりにします。
    /// - Parameters:
    ///   - id: 行の id。
    ///   - kind: 種類。
    ///   - outcome: 結果。
    ///   - seconds: 基準からの秒の範囲。
    ///   - sequences: 連番の範囲。
    ///   - reason: 判定できない理由。
    ///   - category: 色の分類。nil なら表どおり。
    /// - Returns: 行。
    static func row(
        id: Int,
        kind: SessionRoadRegulationReviewKind,
        outcome: SessionRoadRegulationReviewOutcome,
        seconds: ClosedRange<TimeInterval> = 0...10,
        sequences: ClosedRange<Int64> = 0...10,
        reason: RoadRegulationUndeterminedReason? = nil,
        category: RouteAnalysisColorCategory? = nil
    ) -> SessionRoadRegulationReviewRow {
        SessionRoadRegulationReviewRow(
            id: id,
            kind: kind,
            outcome: outcome,
            category: category ?? Self.category(for: outcome),
            titleKey: "title.\(id)",
            systemImage: "image.\(id)",
            timeText: "time.\(id)",
            figureTexts: [],
            timeRange: date(seconds.lowerBound)...date(seconds.upperBound),
            sequenceRange: sequences,
            undeterminedReason: reason,
            overlayID: "overlay.\(kind.rawValue)"
        )
    }

    /// 都道府県と基準月から版の参照を作ります。
    ///
    /// 責務: 範囲外の値ではテストの前提が崩れるため、そこで止めます。
    /// - Parameters:
    ///   - code: 都道府県コード(1...47)。
    ///   - year: 年。
    ///   - month: 月。
    /// - Returns: 版の参照。
    static func reference(_ code: Int, _ year: Int, _ month: Int) -> RoadRegulationDatasetReference {
        guard let prefecture = JapanesePrefectureCode(code),
              let dataMonth = RoadRegulationDataMonth(year: year, month: month) else {
            preconditionFailure("版の参照を作れません")
        }
        return RoadRegulationDatasetReference(prefecture: prefecture, dataMonth: dataMonth)
    }

    /// 照合結果全体を作ります。
    ///
    /// 責務: entry・車速の有無・版・利用日を指定した結果を、固定の URL で返します。
    /// - Parameters:
    ///   - entries: entry。
    ///   - hasVehicleSpeed: 車速の記録があるか。
    ///   - datasets: 判定に使った版。
    ///   - usedOn: 利用日。
    /// - Returns: 照合結果。
    static func review(
        entries: [SessionRoadRegulationReviewEntry] = [],
        hasVehicleSpeed: Bool = true,
        datasets: [RoadRegulationDatasetReference] = [SessionRoadRegulationReviewTestValues.reference(47, 2026, 9)],
        usedOn: Date? = nil
    ) -> SessionRoadRegulationReview {
        SessionRoadRegulationReview(
            entries: entries,
            hasVehicleSpeed: hasVehicleSpeed,
            datasets: datasets,
            usedOn: usedOn,
            sourceURL: sourceURL
        )
    }
}
