import Foundation

/// 記録済みの1回の走行(セッション)を、取得済みの交通規制データと突き合わせて判定するユースケースです。
///
/// 流れ:
/// 1. 位置を読み、空なら `.noTrack`。
/// 2. 有効な版を読み、空なら `.noRegulationData`。使える軌跡の点がどの版の範囲(外接矩形)にも入らない時も `.noRegulationData`。
/// 3. Raw を `pageSize` 件ずつ読み、車速(0x01 / 0x0D)だけを抜き出す。読むたびに `Task.yield` する。
/// 4. メインスレッドの外で、時刻の軸を選び、軌跡と車速の時系列を作り、使える点の周辺の升目だけの規制を引いて索引を作り、判定する。
/// リポジトリのエラーは握りつぶさずにそのまま投げます。位置は端末の外へ送りません。
@MainActor
struct EvaluateSessionRoadRegulationsUseCase {
    /// メインスレッドの外での計算に渡す入力です。
    private struct EvaluationInput: Sendable {
        /// 位置サンプル。
        let samples: [ConnectionSessionLocationSample]
        /// Raw から抜き出した車速。
        let speedObservations: [VehicleSpeedRawObservation]
        /// 有効な版。
        let datasets: [RoadRegulationDataset]
        /// 規制の検索。
        let regulations: any RoadRegulationQueryRepository
        /// 評価器。
        let evaluator: SessionRoadRegulationEvaluator
        /// 升目の計算器。
        let grid: RoadRegulationGrid
    }

    /// 位置の保存先です。
    private let locations: any ConnectionSessionLocationRepository
    /// Raw ログの保存先です(メインスレッドで読みます)。
    private let rawLogs: any ConnectionSessionRawLogRepository
    /// 規制の検索です。
    private let regulations: any RoadRegulationQueryRepository
    /// 版の保存先です。
    private let datasets: any RoadRegulationDatasetRepository
    /// 評価器です。
    private let evaluator: SessionRoadRegulationEvaluator
    /// 升目の計算器です。
    private let grid: RoadRegulationGrid
    /// Raw を1回に読む件数です。
    private let pageSize: Int
    /// 車速の抜き出しです。
    private let speedExtractor = VehicleSpeedSampleExtractor()

    /// 読み取り先と評価器を受け取ります。
    ///
    /// 責務: 判定に使う保存先・評価器・升目・Raw の読み取り件数を保持します(件数は1以上にそろえます)。
    /// - Parameters:
    ///   - locations: 位置の保存先。
    ///   - rawLogs: Raw ログの保存先。
    ///   - regulations: 規制の検索。
    ///   - datasets: 版の保存先。
    ///   - evaluator: 評価器。
    ///   - grid: 升目の計算器。
    ///   - pageSize: Raw を1回に読む件数。
    init(
        locations: any ConnectionSessionLocationRepository,
        rawLogs: any ConnectionSessionRawLogRepository,
        regulations: any RoadRegulationQueryRepository,
        datasets: any RoadRegulationDatasetRepository,
        evaluator: SessionRoadRegulationEvaluator = .init(),
        grid: RoadRegulationGrid = .init(),
        pageSize: Int = 1_000
    ) {
        self.locations = locations
        self.rawLogs = rawLogs
        self.regulations = regulations
        self.datasets = datasets
        self.evaluator = evaluator
        self.grid = grid
        self.pageSize = max(1, pageSize)
    }

    /// 1回の走行を判定します。
    ///
    /// 責務: 位置・版・車速を読み、無いものは該当する結果で返し、そろえばメインスレッドの外で判定します。
    /// - Parameter sessionID: 判定するセッション。
    /// - Returns: 判定の結果。
    /// - Throws: リポジトリのエラー(そのまま)、または `CancellationError`。
    func execute(sessionID: ConnectionSessionID) async throws -> SessionRoadRegulationEvaluationOutcome {
        try Task.checkCancellation()
        let samples = try await Self.loadSamples(from: locations, sessionID: sessionID)
        guard !samples.isEmpty else { return .noTrack }
        try Task.checkCancellation()
        let active = try await Self.loadActiveDatasets(from: datasets)
        guard !active.isEmpty else { return .noRegulationData }
        let observations = try await readSpeedObservations(sessionID: sessionID)
        try Task.checkCancellation()
        let input = EvaluationInput(
            samples: samples,
            speedObservations: observations,
            datasets: active,
            regulations: regulations,
            evaluator: evaluator,
            grid: grid
        )
        let report = try await Self.evaluate(input)
        try Task.checkCancellation()
        guard let report else { return .noRegulationData }
        return .evaluated(report)
    }

    /// Raw ログを小分けに読み、車速だけを抜き出します。
    ///
    /// 責務: 空のページが返るまで `pageSize` 件ずつ読み、読むたびに取り消しを確かめて `Task.yield` します。
    /// 連番が進まないページが返ったら、そこで読むのを止めます。
    /// - Parameter sessionID: 読むセッション。
    /// - Returns: 車速の観測(記録順)。
    /// - Throws: Raw のリポジトリのエラー、または `CancellationError`。
    private func readSpeedObservations(sessionID: ConnectionSessionID) async throws -> [VehicleSpeedRawObservation] {
        var observations: [VehicleSpeedRawObservation] = []
        var lastSequence: Int64?
        while true {
            try Task.checkCancellation()
            let page = try rawLogs.entries(for: sessionID, after: lastSequence, limit: pageSize)
            guard let last = page.last?.sequence else { break }
            observations += page.compactMap { speedExtractor.observation(from: $0) }
            if let lastSequence, last <= lastSequence { break }
            lastSequence = last
            await Task.yield()
        }
        return observations
    }

    /// 位置サンプルをメインスレッドの外で読みます。
    ///
    /// 責務: 位置の保存先からセッションの全位置を読みます。
    /// - Parameters:
    ///   - locations: 位置の保存先。
    ///   - sessionID: 読むセッション。
    /// - Returns: 位置サンプル(連番の昇順)。
    /// - Throws: 位置のリポジトリのエラー。
    @concurrent
    private static func loadSamples(
        from locations: any ConnectionSessionLocationRepository,
        sessionID: ConnectionSessionID
    ) async throws -> [ConnectionSessionLocationSample] {
        try locations.samples(for: sessionID)
    }

    /// 有効な版をメインスレッドの外で読みます。
    ///
    /// 責務: 版の保存先から有効な版を読みます。
    /// - Parameter datasets: 版の保存先。
    /// - Returns: 有効な版。
    /// - Throws: 版のリポジトリのエラー。
    @concurrent
    private static func loadActiveDatasets(from datasets: any RoadRegulationDatasetRepository) async throws -> [RoadRegulationDataset] {
        try datasets.activeDatasets()
    }

    /// メインスレッドの外で、軌跡と車速を作り、周辺の規制を引いて判定します。
    ///
    /// 責務: 時刻の軸を選び、軌跡・車速の時系列・升目の和集合・索引を作って評価器を動かします。
    /// - Parameter input: 計算の入力。
    /// 使える点があり、そのどれも版の範囲に入らない時は、規制を引かずに `nil` を返します
    /// (使える点が無い時は、捨てた点の数を伝えるため空の判定結果を返します)。
    /// - Returns: 走行の判定結果。軌跡が取得済みの版の範囲に入らなければ `nil`。
    /// - Throws: 規制の検索のエラー、または `CancellationError`。
    @concurrent
    private static func evaluate(_ input: EvaluationInput) async throws -> SessionRoadRegulationReport? {
        let thresholds = input.evaluator.thresholds
        let axis = RoadRegulationTimeAxisPolicy().select(locations: input.samples, speedEntries: input.speedObservations)
        let builder = RoadRegulationTrackBuilder(thresholds: thresholds)
        let track = builder.build(input.samples, axis: axis)
        let speeds = builder.speedTimeline(input.speedObservations, axis: axis)
        let used = usedDatasets(input.datasets, track: track.points)
        guard !used.isEmpty || track.points.isEmpty else { return nil }
        try Task.checkCancellation()
        let cells = track.points.reduce(into: Set<RoadRegulationCellKey>()) { cells, point in
            cells.formUnion(input.grid.cells(around: point.coordinate, radiusMeters: thresholds.searchRadiusMeters))
        }
        let found = cells.isEmpty ? [] : try input.regulations.regulations(inCells: cells)
        try Task.checkCancellation()
        let index = RoadRegulationSpatialIndex(regulations: found, grid: input.grid)
        let coverage = input.datasets.map(\.coverage)
        return input.evaluator.evaluate(
            track: track.points,
            droppedPointCount: track.droppedCount,
            speeds: speeds,
            index: index,
            coverage: coverage,
            timeAxis: axis,
            datasets: used
        )
    }

    /// 軌跡のどれかの点を範囲に含む版を、判定に使った版として返します。
    ///
    /// 責務: 版の範囲(外接矩形)に軌跡の点が1つでも入る版だけを、都道府県と基準月の参照にします。
    /// - Parameters:
    ///   - datasets: 有効な版。
    ///   - track: 軌跡の点。
    /// - Returns: 使った版の参照(有効な版の順)。
    nonisolated private static func usedDatasets(
        _ datasets: [RoadRegulationDataset],
        track: [RoadRegulationTrackPoint]
    ) -> [RoadRegulationDatasetReference] {
        datasets
            .filter { dataset in track.contains { dataset.coverage.contains($0.coordinate) } }
            .map { RoadRegulationDatasetReference(prefecture: $0.prefecture, dataMonth: $0.dataMonth) }
    }
}
