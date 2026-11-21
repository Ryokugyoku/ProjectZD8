import Foundation
@testable import ProjectZD8

/// 交通規制の照合のモデルのテストが共有する入力(照合結果)と、仕様(設計書 §3.3・§3.4)から手で書いた期待値です。
///
/// 時刻は基準時刻 `1_800_000_000`(Asia/Tokyo で 2027-01-15 17:00:00)からの秒で表し、連番は秒と同じ値にします。
/// 標準の照合結果の entry は、入力の順と並べた後の順が違うように置いています(並べた後: 指定なし → 超過 → 停止 → 判定できない)。
enum SessionRoadRegulationReviewModelTestValues {
    /// 時刻の基準です。
    static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    /// 配布ページの URL です。
    static let sourceURL = URL(string: "https://example.com/road-regulation/source")!
    /// 使った版の取得日時の最大です。
    static let usedOn = Date(timeIntervalSince1970: 1_790_000_000)
    /// 判定に使った版(沖縄県・2026年9月)です。
    static let okinawaReference = RoadRegulationDatasetReference(
        prefecture: RoadRegulationTestValues.prefecture(47), dataMonth: RoadRegulationTestValues.month(2026, 9)
    )
    /// 凡例の最後に必ず足す「該当する規制なし」です(`localize` は `<キー>` を返す)。
    static let notApplicableLegendText = "<analysis.road_regulation.legend.not_applicable>"

    /// 責務: 基準時刻から `seconds` 秒後の時刻を返します。
    static func date(_ seconds: TimeInterval) -> Date {
        baseDate.addingTimeInterval(seconds)
    }

    /// 責務: 基準時刻から `seconds` 秒後・連番 `seconds` の印を作ります。
    static func mark(_ seconds: TimeInterval) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: seconds, sequence: Int64(seconds), observedAt: date(seconds))
    }

    /// 責務: 照合結果の entry を作ります。
    /// - Parameters:
    ///   - kind: 種類。
    ///   - outcome: 結果の分類。
    ///   - key: 判定の文言キー。
    ///   - from: 開始の秒。
    ///   - to: 終了の秒。
    ///   - reason: 判定できない理由。
    ///   - figures: 数値。
    /// - Returns: entry。
    static func entry(
        _ kind: SessionRoadRegulationReviewKind,
        _ outcome: SessionRoadRegulationReviewOutcome,
        key: String,
        from: TimeInterval,
        to: TimeInterval,
        reason: RoadRegulationUndeterminedReason? = nil,
        figures: SessionRoadRegulationReviewFigures = .init()
    ) -> SessionRoadRegulationReviewEntry {
        SessionRoadRegulationReviewEntry(
            kind: kind, outcome: outcome, verdictKey: key, undeterminedReason: reason,
            start: mark(from), end: mark(to), figures: figures
        )
    }

    /// 責務: 標準の照合結果(超過・停止・指定なし・判定できない一方通行の4件、徐行なし)を作ります。
    /// - Parameters:
    ///   - hasVehicleSpeed: 車速があったか。
    ///   - datasets: 判定に使った版。
    /// - Returns: 照合結果。
    static func standardReview(
        hasVehicleSpeed: Bool = true,
        datasets: [RoadRegulationDatasetReference] = [okinawaReference]
    ) -> SessionRoadRegulationReview {
        let exceededFigures = SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: 52, exceededSeconds: 6)
        let entries: [SessionRoadRegulationReviewEntry] = [
            entry(.speedLimit, .possibleIssue, key: "road_regulation.verdict.speed_limit.exceeded", from: 10, to: 40, figures: exceededFigures),
            entry(.stop, .compliant, key: "road_regulation.verdict.stop.stopped", from: 50, to: 55),
            entry(.speedLimit, .unregulated, key: "road_regulation.verdict.speed_limit.unregulated", from: 0, to: 9),
            entry(.oneWay, .undeterminable, key: "road_regulation.undetermined.heading_unknown", from: 60, to: 70, reason: .headingUnknown),
        ]
        return SessionRoadRegulationReview(
            entries: entries, hasVehicleSpeed: hasVehicleSpeed, datasets: datasets, usedOn: usedOn, sourceURL: sourceURL
        )
    }

    /// 責務: 一時停止の「停止していない可能性」1件だけの照合結果を作ります(別のセッション・別の呼び出しの結果に使う)。
    static func stopOnlyReview() -> SessionRoadRegulationReview {
        let figures = SessionRoadRegulationReviewFigures(minimumKph: 8)
        let entries = [entry(.stop, .possibleIssue, key: "road_regulation.verdict.stop.not_stopped", from: 100, to: 105, figures: figures)]
        return SessionRoadRegulationReview(entries: entries, hasVehicleSpeed: true, datasets: [okinawaReference], usedOn: nil, sourceURL: sourceURL)
    }

    /// 標準の照合結果から作られるはずの行(並べた後の順。id は位置)です。
    static var standardRows: [SessionRoadRegulationReviewRow] {
        [
            row(0, .speedLimit, .unregulated, key: "road_regulation.verdict.speed_limit.unregulated", from: 0, to: 9,
                timeText: "17:00:00–17:00:09"),
            row(1, .speedLimit, .possibleIssue, key: "road_regulation.verdict.speed_limit.exceeded", from: 10, to: 40,
                timeText: "17:00:10–17:00:40", figureTexts: ["L=40 km/h", "M=52 km/h", "E=6"]),
            row(2, .stop, .compliant, key: "road_regulation.verdict.stop.stopped", from: 50, to: 55, timeText: "17:00:50–17:00:55"),
            row(3, .oneWay, .undeterminable, key: "road_regulation.undetermined.heading_unknown", from: 60, to: 70,
                timeText: "17:01:00–17:01:10", reason: .headingUnknown),
        ]
    }

    /// 責務: 仕様の表(§3.3)の分類・記号・重ね合わせの ID を当てた、期待する行を作ります。
    static func row(
        _ id: Int,
        _ kind: SessionRoadRegulationReviewKind,
        _ outcome: SessionRoadRegulationReviewOutcome,
        key: String,
        from: TimeInterval,
        to: TimeInterval,
        timeText: String,
        figureTexts: [String] = [],
        reason: RoadRegulationUndeterminedReason? = nil
    ) -> SessionRoadRegulationReviewRow {
        SessionRoadRegulationReviewRow(
            id: id, kind: kind, outcome: outcome, category: category(outcome), titleKey: key, systemImage: systemImage(outcome),
            timeText: timeText, figureTexts: figureTexts, timeRange: date(from)...date(to),
            sequenceRange: Int64(from)...Int64(to), undeterminedReason: reason, overlayID: "road_regulation.\(snakeName(kind))"
        )
    }

    /// 責務: 仕様の表(§3.3)の結果ごとの色の分類を返します。
    static func category(_ outcome: SessionRoadRegulationReviewOutcome) -> RouteAnalysisColorCategory {
        let table: [SessionRoadRegulationReviewOutcome: RouteAnalysisColorCategory] = [
            .possibleIssue: .tone(.caution), .undeterminable: .tone(.unknown), .compliant: .tone(.positive),
            .observedOnly: .tone(.neutral), .unregulated: .tone(.neutral),
        ]
        return table[outcome] ?? .base
    }

    /// 責務: 仕様の表(§3.3)の結果ごとの記号を返します。
    static func systemImage(_ outcome: SessionRoadRegulationReviewOutcome) -> String {
        let table: [SessionRoadRegulationReviewOutcome: String] = [
            .possibleIssue: "exclamationmark.triangle.fill", .undeterminable: "questionmark.circle", .compliant: "checkmark.circle",
            .observedOnly: "gauge.with.dots.needle.33percent", .unregulated: "minus.circle",
        ]
        return table[outcome] ?? ""
    }

    /// 責務: 種類のキーの名前(snake_case)を返します。
    static func snakeName(_ kind: SessionRoadRegulationReviewKind) -> String {
        let table: [SessionRoadRegulationReviewKind: String] = [
            .speedLimit: "speed_limit", .stop: "stop", .oneWay: "one_way", .slowDown: "slow_down",
        ]
        return table[kind] ?? ""
    }

    /// 責務: 期待する重ね合わせを作ります。凡例は渡した組の後に「該当する規制なし」を足し、id を 0 からの連番にします。
    /// - Parameters:
    ///   - kind: 種類。
    ///   - runs: 色分けの区間(優先の順)。
    ///   - legend: 凡例の (分類, 文字) の組。
    ///   - highlights: 強調する時刻の範囲(秒)。
    /// - Returns: 重ね合わせ。
    static func overlay(
        _ kind: SessionRoadRegulationReviewKind,
        runs: [RouteAnalysisColorRun],
        legend: [(RouteAnalysisColorCategory, String)],
        highlights: [ClosedRange<TimeInterval>] = []
    ) -> RouteAnalysisOverlay {
        let pairs = legend + [(RouteAnalysisColorCategory.base, notApplicableLegendText)]
        let entries = pairs.enumerated().map { RouteAnalysisLegendEntry(id: $0.offset, category: $0.element.0, text: $0.element.1) }
        let ranges = highlights.map { date($0.lowerBound)...date($0.upperBound) }
        return RouteAnalysisOverlay(
            id: "road_regulation.\(snakeName(kind))", titleKey: "analysis.road_regulation.overlay.\(snakeName(kind))",
            runs: runs, legend: entries, highlightedTimeRanges: ranges
        )
    }

    /// 責務: 標準の照合結果の重ね合わせ(最高速度・一時停止・一方通行。徐行は行が無いので作らない)を、強調を指定して作ります。
    /// - Parameters:
    ///   - speedLimitHighlights: 最高速度の強調(既定は possibleIssue の行 10〜40 秒を前後 0.5 秒広げた範囲)。
    ///   - oneWayHighlights: 一方通行の強調(既定は possibleIssue が無いので空)。
    /// - Returns: 重ね合わせ。
    static func standardOverlays(
        speedLimitHighlights: [ClosedRange<TimeInterval>] = [9.5...40.5],
        oneWayHighlights: [ClosedRange<TimeInterval>] = []
    ) -> [RouteAnalysisOverlay] {
        let speedRuns = [RouteAnalysisColorRun(sequenceRange: 10...40, category: .tone(.caution)),
                         RouteAnalysisColorRun(sequenceRange: 0...9, category: .tone(.neutral))]
        let speedLegend: [(RouteAnalysisColorCategory, String)] = [
            (.tone(.caution), "<road_regulation.verdict.speed_limit.exceeded>"),
            (.tone(.neutral), "<road_regulation.verdict.speed_limit.unregulated>"),
        ]
        return [
            overlay(.speedLimit, runs: speedRuns, legend: speedLegend, highlights: speedLimitHighlights),
            overlay(.stop, runs: [RouteAnalysisColorRun(sequenceRange: 50...55, category: .tone(.positive))],
                    legend: [(.tone(.positive), "<road_regulation.verdict.stop.stopped>")]),
            overlay(.oneWay, runs: [RouteAnalysisColorRun(sequenceRange: 60...70, category: .tone(.unknown))],
                    legend: [(.tone(.unknown), "<analysis.road_regulation.outcome.undetermined>")], highlights: oneWayHighlights),
        ]
    }
}
