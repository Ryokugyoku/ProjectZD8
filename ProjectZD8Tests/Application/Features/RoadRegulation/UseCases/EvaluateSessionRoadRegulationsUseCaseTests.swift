import XCTest
@testable import ProjectZD8

/// `EvaluateSessionRoadRegulationsUseCase` が、位置・版・Raw ログ・規制を読んで1セッションの結果を返すことを検証します
/// (設計書 §3.7「判定」、TB9)。失敗の扱いは `EvaluateSessionRoadRegulationsUseCaseFailureTests` を参照してください。
///
/// 場面: 東西の道(最高速度 40)の上を、原点から東へ 10 m ごと・1 秒ごとに 41 点走ります。結果は期限(2秒)つきで待ちます。
@MainActor
final class EvaluateSessionRoadRegulationsUseCaseTests: XCTestCase {
    private typealias Harness = RoadRegulationEvaluationUseCaseHarness
    private var harness: Harness!

    override func setUp() async throws {
        try await super.setUp()
        harness = Harness()
        harness.regulations.replaceRegulations([Harness.eastRoad()])
    }

    override func tearDown() async throws {
        harness = nil
        try await super.tearDown()
    }

    /// 責務: 範囲が北海道(北緯43〜43.5度・東経141〜141.5度)の有効な版を作ります(軌跡の点は入らない)。
    private static func hokkaidoDataset() -> RoadRegulationDataset {
        let prefecture = RoadRegulationTestValues.prefecture(1)
        return RoadRegulationDataset(
            id: RoadRegulationDatasetID(rawValue: UUID()), prefecture: prefecture, state: .active,
            dataMonth: RoadRegulationTestValues.month(2026, 8), publicationStamp: "202610010000",
            sourceURL: RoadRegulationTestValues.archiveURL(prefecture),
            downloadedAt: RoadRegulationTestValues.fixedNow, activatedAt: RoadRegulationTestValues.fixedNow, formatVersion: "k_2.1",
            counts: RoadRegulationTestValues.counts(),
            coverage: RoadRegulationTestValues.box(minLatitude: 43.0, maxLatitude: 43.5, minLongitude: 141.0, maxLongitude: 141.5)
        )
    }

    /// 責務: ユースケースを動かし、期限内の結果を返します。
    private func execute(pageSize: Int = 1_000) async -> SessionRoadRegulationEvaluationOutcome? {
        await harness.start(harness.makeUseCase(pageSize: pageSize)).value(on: self)
    }

    /// 責務: 位置が無ければ、版があっても無くても `.noTrack` になり、版を読まないことを確かめます。
    func testNoLocationsIsNoTrackWithoutReadingDatasets() async {
        let outcome = await execute()
        XCTAssertEqual(outcome, .noTrack)
        XCTAssertFalse(harness.datasets.log.steps.contains(.activeDatasets))

        harness.seedOkinawaDataset()
        let withDataset = await execute()
        XCTAssertEqual(withDataset, .noTrack)
    }

    /// 責務: 有効な版が無ければ `.noRegulationData` になることを確かめます。
    func testNoActiveDatasetIsNoRegulationData() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41)
        let outcome = await execute()
        XCTAssertEqual(outcome, .noRegulationData)
    }

    /// 責務: 有効な版はあるが、軌跡の点が1つも範囲に入らない(北海道の版だけ)時は `.noRegulationData` になることを確かめます。
    func testNoDatasetContainingTrackIsNoRegulationData() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41)
        harness.datasets.seedActive(Self.hokkaidoDataset())
        let outcome = await execute()
        XCTAssertEqual(outcome, .noRegulationData)
    }

    /// 責務: 版の範囲に軌跡が入るが近くに規制が無い時は、`.evaluated` で、最高速度が「指定なし」の区間1件になることを確かめます。
    func testNoRegulationsNearTrackIsEvaluatedAsUnregulated() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41)
        let okinawa = harness.seedOkinawaDataset()
        harness.regulations.replaceRegulations([])
        let outcome = await execute()
        guard let report = Harness.report(outcome) else { return }

        XCTAssertEqual(report.speedLimit.map(\.verdict), [.unregulated])
        XCTAssertEqual(report.speedLimit.first?.traversal.start.sequence, 0)
        XCTAssertEqual(report.speedLimit.first?.traversal.end.sequence, 40)
        XCTAssertEqual(report.stops, [])
        XCTAssertEqual(report.oneWay, [])
        XCTAssertEqual(report.slowDown, [])
        XCTAssertEqual(report.coverage.datasets, [okinawa])
    }

    /// 責務: 結果に、制限内の判定と、時刻の軸(単調時計)・点の数・捨てた点の数・車速の有無・版の参照が入ることを確かめます。
    func testEvaluatedReportCarriesJudgementsAndCoverage() async throws {
        try harness.seedTrack(count: 41)
        try harness.appendFix(second: 41, x: 410, accuracy: 60)
        harness.seedRaw(count: 42)
        let reference = harness.seedOkinawaDataset()
        let outcome = await execute()
        guard let report = Harness.report(outcome) else { return }

        XCTAssertEqual(report.coverage, RoadRegulationEvaluationCoverage(
            timeAxis: .monotonic, trackPointCount: 41, droppedPointCount: 1, hasVehicleSpeed: true, datasets: [reference]
        ))
        let verdicts = report.speedLimit.map(\.verdict)
        XCTAssertEqual(verdicts, [.withinLimit(maxKph: 35)])
    }

    /// 責務: `coverage.datasets` には、範囲に軌跡の点が入る版だけが入ることを確かめます(北海道の版は入らない)。
    func testCoverageListsOnlyDatasetsContainingTrack() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41)
        let okinawa = harness.seedOkinawaDataset()
        let hokkaido = Self.hokkaidoDataset()
        harness.datasets.seedActive(hokkaido)
        let outcome = await execute()
        guard let report = Harness.report(outcome) else { return }
        XCTAssertEqual(report.coverage.datasets, [okinawa])
    }

    /// 責務: Raw ログを pageSize ごとに、前のページの最後の連番の後から、空のページが返るまで読むことを確かめます(5件・2件ずつ)。
    func testRawLogsAreReadPageByPageUntilEmpty() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 5)
        harness.seedOkinawaDataset()
        _ = await execute(pageSize: 2)

        typealias Request = RoadRegulationRawLogRepositoryFake.PageRequest
        XCTAssertEqual(harness.rawLogs.pageRequests, [
            Request(after: nil, limit: 2), Request(after: 1, limit: 2), Request(after: 3, limit: 2), Request(after: 4, limit: 2),
        ])
        XCTAssertEqual(harness.rawLogs.fullReadCount, 0)
    }

    /// 責務: 連番の進まないページを返し続ける Repository でも、2回目で読むのをやめて期限内に終わることを確かめます。
    func testNonAdvancingPageStopsReading() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 5)
        harness.seedOkinawaDataset()
        harness.rawLogs.repeatsFirstPage = true
        let outcome = await execute(pageSize: 2)
        XCTAssertNotNil(outcome)
        XCTAssertEqual(harness.rawLogs.pageRequests.count, 2)
    }

    /// 責務: 車速の PID(0x0D)が無いと `hasVehicleSpeed` が false になり、区間の判定が `speedUnavailable` になることを確かめます。
    func testMissingVehicleSpeedIsSpeedUnavailable() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41, pid: 0x0C)
        harness.seedOkinawaDataset()
        let outcome = await execute()
        guard let report = Harness.report(outcome) else { return }

        XCTAssertFalse(report.coverage.hasVehicleSpeed)
        XCTAssertEqual(report.speedLimit.map(\.verdict), [.undeterminable(.speedUnavailable)])
    }

    /// 責務: 規制の検索へ渡す升目が、使える点の周辺(半径 120 m の升目)だけで、精度の悪い遠い点の升目を含まないことを確かめます。
    func testQueriedCellsStayAroundUsableTrack() async throws {
        try harness.seedTrack(count: 41)
        try harness.appendFix(second: 41, x: 5_000, accuracy: 60)
        harness.seedRaw(count: 41)
        harness.seedOkinawaDataset()
        _ = await execute()

        let grid = RoadRegulationGrid()
        let usable = (0..<41).map { RoadRegulationMeterRegulationFactory.coordinate((x: Double($0) * 10, y: 0)) }
        let neighborhood = usable.reduce(into: Set<RoadRegulationCellKey>()) { cells, coordinate in
            cells.formUnion(grid.cells(around: coordinate, radiusMeters: RoadRegulationMatchingThresholds.standard.searchRadiusMeters))
        }
        let queried = harness.regulations.requests.reduce(into: Set<RoadRegulationCellKey>()) { $0.formUnion($1) }
        let farCell = grid.cell(containing: RoadRegulationMeterRegulationFactory.coordinate((x: 5_000, y: 0)))

        XCTAssertFalse(queried.isEmpty)
        XCTAssertTrue(queried.isSubset(of: neighborhood), "軌跡の周辺の外の升目を引きました")
        XCTAssertTrue(Set(usable.map(grid.cell(containing:))).isSubset(of: queried), "軌跡の点の升目が抜けています")
        XCTAssertFalse(queried.contains(farCell))
    }

    /// 責務: 位置はあるが全点が捨てられた時は、`.noTrack` にせず、捨てた点の数を添えた空の判定になり、検索を呼ばないことを確かめます。
    func testAllDroppedPointsGiveEmptyEvaluatedReport() async throws {
        try harness.seedTrack(count: 5, accuracy: 60)
        harness.seedRaw(count: 5)
        harness.seedOkinawaDataset()
        let outcome = await execute()
        guard let report = Harness.report(outcome) else { return }

        XCTAssertEqual(report.coverage.droppedPointCount, 5)
        XCTAssertEqual(report.coverage.trackPointCount, 0)
        XCTAssertEqual(report.speedLimit, [])
        XCTAssertEqual(report.stops, [])
        XCTAssertTrue(harness.regulations.requests.isEmpty)
    }

    /// 責務: Raw ログを読んでいる途中で取り消すと、`CancellationError` で止まり、残りのページと規制の検索を行わないことを確かめます。
    func testCancellationStopsReading() async throws {
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 10)
        harness.seedOkinawaDataset()
        let run = harness.start(harness.makeUseCase(pageSize: 2))
        harness.rawLogs.onPageRequest = { number in if number == 1 { run.cancel() } }

        let error = await run.failure(on: self)
        XCTAssertTrue(error is CancellationError, "取り消しのエラーになりませんでした: \(String(describing: error))")
        XCTAssertLessThan(harness.rawLogs.pageRequests.count, 6)
        XCTAssertTrue(harness.regulations.requests.isEmpty)
    }
}
