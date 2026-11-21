import Foundation

/// 解析の交通規制の照合(`SessionRoadRegulationReviewPort`)を、RoadRegulation の判定と版の一覧で実装します。
///
/// Analysis が RoadRegulation の具象型に依存しないよう、App 層に置きます。
/// - 位置が無い・規制データが無いは、そのまま照合結果の同名の値へ写します。
/// - 判定できた時だけ版の一覧を読み、判定に使った版(県と基準月が一致するもの)の取得日時の最大を利用日にします。
/// - 判定と版の一覧のエラー(`CancellationError` を含む)は握りつぶさず、そのまま投げます。
@MainActor final class RoadRegulationSessionReviewAdapter: SessionRoadRegulationReviewPort {
    /// 1回の走行を判定する処理です(`EvaluateSessionRoadRegulationsUseCase` を包んだもの)。
    private let evaluate: @MainActor (ConnectionSessionID) async throws -> SessionRoadRegulationEvaluationOutcome
    /// 有効な版の一覧を読む処理です(`ListRoadRegulationDatasetsUseCase` を包んだもの)。
    private let listDatasets: @MainActor () throws -> [RoadRegulationDataset]
    /// 判定の報告を照合結果へ写す部品です。
    private let mapper: RoadRegulationSessionReviewMapper
    /// 配布ページです。
    private let sourceURL: URL

    /// 判定・版の一覧の処理と写しの部品・配布ページを固定して生成します。
    ///
    /// 責務: 判定と版の一覧の closure、写しの部品、配布ページの URL を保持します。
    /// - Parameters:
    ///   - evaluate: 1回の走行を判定する処理。
    ///   - listDatasets: 有効な版の一覧を読む処理。
    ///   - mapper: 判定の報告を照合結果へ写す部品。
    ///   - sourceURL: 配布ページ(組み立てで `RoadRegulationAttribution.sourceURLString` から作る)。
    init(
        evaluate: @escaping @MainActor (ConnectionSessionID) async throws -> SessionRoadRegulationEvaluationOutcome,
        listDatasets: @escaping @MainActor () throws -> [RoadRegulationDataset],
        mapper: RoadRegulationSessionReviewMapper = .init(),
        sourceURL: URL
    ) {
        self.evaluate = evaluate
        self.listDatasets = listDatasets
        self.mapper = mapper
        self.sourceURL = sourceURL
    }

    /// 1回の走行を交通規制と照合します。
    ///
    /// 責務: 判定し、位置・規制データが無い時はそのまま返し、判定できた時は利用日を求めて照合結果へ写します。
    /// - Parameter sessionID: 照合するセッションの ID。
    /// - Returns: 照合結果。
    /// - Throws: 判定または版の一覧のエラー(`CancellationError` を含む)をそのまま投げます。
    func review(sessionID: ConnectionSessionID) async throws -> SessionRoadRegulationReviewResult {
        switch try await evaluate(sessionID) {
        case .noTrack:
            return .noTrack
        case .noRegulationData:
            return .noRegulationData
        case .evaluated(let report):
            let usedOn = try usedOn(for: report.coverage.datasets)
            return .reviewed(mapper.review(from: report, usedOn: usedOn, sourceURL: sourceURL))
        }
    }

    /// 判定に使った版の取得日時の最大を求めます。
    ///
    /// 責務: 有効な版の一覧を読み、県と基準月が判定に使った版のどれかと一致する版の取得日時の最大を返します。
    /// - Parameter references: 判定に使った版。
    /// - Returns: 一致する版の取得日時の最大。一致が無ければ nil。
    /// - Throws: 版の一覧のエラーをそのまま投げます。
    private func usedOn(for references: [RoadRegulationDatasetReference]) throws -> Date? {
        try listDatasets()
            .filter { dataset in references.contains { Self.matches(dataset, $0) } }
            .map(\.downloadedAt)
            .max()
    }

    /// 版が判定に使った版と同じかを判定します。
    ///
    /// 責務: 県と基準月の両方が一致する時だけ true を返します。
    /// - Parameters:
    ///   - dataset: 版の一覧の1件。
    ///   - reference: 判定に使った版。
    /// - Returns: 一致すれば true。
    private static func matches(_ dataset: RoadRegulationDataset, _ reference: RoadRegulationDatasetReference) -> Bool {
        dataset.prefecture == reference.prefecture && dataset.dataMonth == reference.dataMonth
    }
}
