import Foundation
import XCTest
@testable import ProjectZD8

/// `EvaluateSessionRoadRegulationsUseCase` のテストで、位置・Raw ログ・規制・版の偽物を用意し、ユースケースを作って動かす補助です。
///
/// 位置は原点から東へ 10 m ごと(1 秒ごと)、Raw ログの車速は同じ秒に置きます。実時間 = 基準 + 単調時刻(ずれ一定)なので、
/// 時刻の軸は単調時計になります。
@MainActor
final class RoadRegulationEvaluationUseCaseHarness {
    /// 実時間の基準です。
    static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    /// 単調時刻の始まり(秒)です。
    static let monotonicStartSeconds = 100.0

    /// 判定するセッションです。
    let sessionID = ConnectionSessionID()
    /// 位置の Repository(段階1のスパイ)です。
    let locations = ConnectionSessionLocationRepositorySpy()
    /// Raw ログの Repository の偽物です。
    let rawLogs = RoadRegulationRawLogRepositoryFake()
    /// 規制の検索の偽物です。
    let regulations = RoadRegulationQueryRepositoryFake()
    /// 版の Repository のスパイです。
    let datasets = RoadRegulationDatasetRepositorySpy()

    /// 責務: 最高速度 40 の東西の道(行 ID 1、x = −1,000〜1,000、500 m ごとの点)を作ります。
    static func eastRoad() -> RoadRegulation {
        RoadRegulationMeterRegulationFactory.line(
            id: 1,
            points: [(x: -1_000, y: 0), (x: -500, y: 0), (x: 0, y: 0), (x: 500, y: 0), (x: 1_000, y: 0)]
        )
    }

    /// 責務: 位置を1点保存します。
    /// - Parameters:
    ///   - second: 時刻(始まりからの秒)。
    ///   - x: 東への距離(m)。
    ///   - accuracy: 水平精度(m)。
    func appendFix(second: Double, x: Double, accuracy: Double = 5) throws {
        let coordinate = RoadRegulationMeterRegulationFactory.coordinate((x: x, y: 0))
        let fix = try XCTUnwrap(LocationFix(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeMeters: nil,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: nil,
            speedMetersPerSecond: 10,
            courseDegrees: 90,
            observedAt: Self.baseDate.addingTimeInterval(second),
            monotonicNanoseconds: UInt64((Self.monotonicStartSeconds + second) * 1_000_000_000)
        ))
        try locations.appendSample(fix, for: sessionID)
    }

    /// 責務: 東へ 10 m ごと・1 秒ごとの位置を `count` 点保存します。
    /// - Parameters:
    ///   - count: 点の数。
    ///   - accuracy: 水平精度(m)。
    func seedTrack(count: Int, accuracy: Double = 5) throws {
        for index in 0..<count {
            try appendFix(second: Double(index), x: Double(index) * 10, accuracy: accuracy)
        }
    }

    /// 責務: 0 秒から1秒ごとに Raw ログを `count` 件置きます(連番は添字)。
    /// - Parameters:
    ///   - count: 件数。
    ///   - kph: 車速(km/h)。
    ///   - pid: PID(0x0D が車速)。
    func seedRaw(count: Int, kph: UInt8 = 35, pid: UInt8 = 0x0D) {
        rawLogs.storedEntries = (0..<count).map { index in
            ConnectionSessionRawLogEntry(
                sequence: Int64(index),
                observedAt: Self.baseDate.addingTimeInterval(Double(index)),
                batchElapsedNanoseconds: 0,
                service: 0x01,
                pid: pid,
                payload: [kph],
                monotonicNanoseconds: UInt64((Self.monotonicStartSeconds + Double(index)) * 1_000_000_000)
            )
        }
    }

    /// 責務: 原点を範囲に含む沖縄(47)の有効な版を置き、その参照を返します。
    /// - Returns: 版の参照。
    @discardableResult
    func seedOkinawaDataset() -> RoadRegulationDatasetReference {
        let dataset = RoadRegulationTestValues.dataset(RoadRegulationTestValues.prefecture(47))
        datasets.seedActive(dataset)
        return RoadRegulationDatasetReference(prefecture: dataset.prefecture, dataMonth: dataset.dataMonth)
    }

    /// 責務: 偽物をつないだユースケースを作ります。
    /// - Parameters:
    ///   - pageSize: Raw ログを読む件数の単位。
    ///   - locationRepository: 位置の Repository(既定はスパイ)。
    /// - Returns: ユースケース。
    func makeUseCase(pageSize: Int = 1_000, locationRepository: (any ConnectionSessionLocationRepository)? = nil)
        -> EvaluateSessionRoadRegulationsUseCase {
        EvaluateSessionRoadRegulationsUseCase(
            locations: locationRepository ?? locations,
            rawLogs: rawLogs,
            regulations: regulations,
            datasets: datasets,
            pageSize: pageSize
        )
    }

    /// 責務: ユースケースを期限つきで動かせる形で始めます。
    /// - Parameter useCase: 動かすユースケース。
    /// - Returns: 期限つきの実行。
    func start(_ useCase: EvaluateSessionRoadRegulationsUseCase) -> TestBoundedAsyncRun<SessionRoadRegulationEvaluationOutcome> {
        let sessionID = sessionID
        return TestBoundedAsyncRun { try await useCase.execute(sessionID: sessionID) }
    }

    /// 責務: 結果が `.evaluated` ならその判定の結果を返し、違えば失敗にします。
    /// - Parameter outcome: ユースケースの結果。
    /// - Returns: 判定の結果。`.evaluated` でなければ `nil`。
    static func report(
        _ outcome: SessionRoadRegulationEvaluationOutcome?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SessionRoadRegulationReport? {
        guard case .evaluated(let report) = outcome else {
            XCTFail("判定の結果になりませんでした: \(String(describing: outcome))", file: file, line: line)
            return nil
        }
        return report
    }
}
