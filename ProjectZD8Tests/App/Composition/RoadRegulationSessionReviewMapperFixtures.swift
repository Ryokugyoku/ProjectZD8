import Foundation
@testable import ProjectZD8

/// 交通規制の照合結果の写し(Mapper・アダプター)のテストで、判定の報告と期待する entry を組み立てる補助です。
///
/// 区間と一時停止の通過は `RoadRegulationJudgementFixtures` で作ります(印の `observedAt` は基準時刻 + 時刻軸の秒)。
enum RoadRegulationSessionReviewMapperFixtures {
    /// 配布ページの URL(テスト用の固定値)です。
    static let sourceURL = URL(string: "https://example.com/road-regulation/source")!
    /// 利用日に使う固定の時刻です。
    static let usedOn = Date(timeIntervalSince1970: 1_790_000_000)

    /// 責務: 件数0の集計を作ります(Mapper は集計を使わないため、どの種類にも同じ値を入れます)。
    static var emptyTally: RoadRegulationKindTally {
        RoadRegulationKindTally(total: 0, verdictCounts: [:], undetermined: 0, undeterminedByReason: [:])
    }

    /// 責務: 都道府県コードと基準月から、判定に使った版の参照を作ります。
    /// - Parameters:
    ///   - prefecture: 都道府県コードの番号(1...47)。
    ///   - year: 基準月の年。
    ///   - month: 基準月の月。
    /// - Returns: 版の参照。
    static func reference(_ prefecture: Int, _ year: Int, _ month: Int) -> RoadRegulationDatasetReference {
        RoadRegulationDatasetReference(
            prefecture: RoadRegulationTestValues.prefecture(prefecture),
            dataMonth: RoadRegulationTestValues.month(year, month)
        )
    }

    /// 責務: 4種類の判定の配列と範囲の値から、判定の報告を作ります。
    /// - Parameters:
    ///   - speedLimit: 最高速度の判定。
    ///   - stops: 一時停止の判定。
    ///   - oneWay: 一方通行の判定。
    ///   - slowDown: 徐行の判定。
    ///   - hasVehicleSpeed: 車速があったか。
    ///   - datasets: 判定に使った版。
    /// - Returns: 判定の報告。
    static func report(
        speedLimit: [SpeedLimitJudgement] = [],
        stops: [StopJudgement] = [],
        oneWay: [OneWayJudgement] = [],
        slowDown: [SlowDownJudgement] = [],
        hasVehicleSpeed: Bool = true,
        datasets: [RoadRegulationDatasetReference] = [reference(47, 2026, 9)]
    ) -> SessionRoadRegulationReport {
        let coverage = RoadRegulationEvaluationCoverage(
            timeAxis: .wallClock, trackPointCount: 20, droppedPointCount: 1, hasVehicleSpeed: hasVehicleSpeed, datasets: datasets
        )
        return SessionRoadRegulationReport(
            speedLimit: speedLimit, stops: stops, oneWay: oneWay, slowDown: slowDown,
            speedLimitTally: emptyTally, stopTally: emptyTally, oneWayTally: emptyTally, slowDownTally: emptyTally,
            coverage: coverage
        )
    }

    /// 責務: 最高速度の区間(時刻 `from`〜`to`、連番 `sequences`)を作ります。
    /// - Parameters:
    ///   - from: 区間の最初の時刻。
    ///   - to: 区間の最後の時刻。
    ///   - sequences: 区間の最初と最後の連番。
    /// - Returns: 区間の通過。
    static func speedLimitTraversal(from: TimeInterval, to: TimeInterval, sequences: ClosedRange<Int64>) -> RoadRegulationTraversal {
        RoadRegulationJudgementFixtures.traversal(
            .speedLimit(.regulated(RoadRegulationJudgementFixtures.regulationID, limitKph: 40)), from: from, to: to, sequences: sequences
        )
    }

    /// 責務: 一方通行の区間(時刻 `from`〜`to`、連番 `sequences`)を作ります。
    /// - Parameters:
    ///   - from: 区間の最初の時刻。
    ///   - to: 区間の最後の時刻。
    ///   - sequences: 区間の最初と最後の連番。
    /// - Returns: 区間の通過。
    static func oneWayTraversal(from: TimeInterval, to: TimeInterval, sequences: ClosedRange<Int64>) -> RoadRegulationTraversal {
        RoadRegulationJudgementFixtures.traversal(
            .oneWay(.on(RoadRegulationJudgementFixtures.regulationID, .permitted)), from: from, to: to, sequences: sequences
        )
    }

    /// 責務: 徐行の区間(時刻 `from`〜`to`、連番 `sequences`)を作ります。
    /// - Parameters:
    ///   - from: 区間の最初の時刻。
    ///   - to: 区間の最後の時刻。
    ///   - sequences: 区間の最初と最後の連番。
    /// - Returns: 区間の通過。
    static func slowDownTraversal(from: TimeInterval, to: TimeInterval, sequences: ClosedRange<Int64>) -> RoadRegulationTraversal {
        RoadRegulationJudgementFixtures.traversal(
            .slowDown(.on(RoadRegulationJudgementFixtures.regulationID)), from: from, to: to, sequences: sequences
        )
    }

    /// 責務: 期待する entry を作ります(理由・数値は省略で nil)。
    /// - Parameters:
    ///   - kind: 種類。
    ///   - outcome: 結果の分類。
    ///   - key: 判定の文言キー(文字列リテラルで渡す)。
    ///   - reason: 判定できない理由。
    ///   - start: 開始の印。
    ///   - end: 終了の印。
    ///   - figures: 数値。
    /// - Returns: 期待する entry。
    static func entry(
        _ kind: SessionRoadRegulationReviewKind,
        _ outcome: SessionRoadRegulationReviewOutcome,
        key: String,
        reason: RoadRegulationUndeterminedReason? = nil,
        start: RoadRegulationTransitionMark,
        end: RoadRegulationTransitionMark,
        figures: SessionRoadRegulationReviewFigures = .init()
    ) -> SessionRoadRegulationReviewEntry {
        SessionRoadRegulationReviewEntry(
            kind: kind, outcome: outcome, verdictKey: key, undeterminedReason: reason, start: start, end: end, figures: figures
        )
    }
}
