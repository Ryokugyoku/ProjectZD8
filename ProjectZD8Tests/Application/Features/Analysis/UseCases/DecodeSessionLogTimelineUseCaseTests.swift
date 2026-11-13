import Foundation
import XCTest
@testable import ProjectZD8

/// 保存済みPIDログの時系列変換を検証します。
@MainActor
final class DecodeSessionLogTimelineUseCaseTests: XCTestCase {
    /// 定義済みPIDは数式と単位を適用し、未定義PIDはRawとして保持します。
    ///
    /// 責務: セッション内の全PIDが時系列順と変換来歴を保って表示値になることを確認します。
    func testExecuteDecodesKnownPIDAndRetainsUnknownPIDAsRaw() async throws {
        let sessionID = ConnectionSessionID()
        let entries = [
            ConnectionSessionRawLogEntry(sequence: 1, observedAt: Date(timeIntervalSince1970: 20), batchElapsedNanoseconds: 2, service: 0x01, pid: 0x0C, payload: [0x1A, 0xF8]),
            ConnectionSessionRawLogEntry(sequence: 0, observedAt: Date(timeIntervalSince1970: 10), batchElapsedNanoseconds: 1, service: 0x01, pid: 0xFF, payload: [0x12])
        ]
        let definition = OBDPIDDefinition(service: 0x01, pid: 0x0C, nameKey: "obd.pid.01.0C.name", requiredByteCount: 2, formula: "(A * 256 + B) / 4", unit: "rpm", minimumValue: 0, maximumValue: 16_383.75, sourceURI: "https://example.invalid", revision: 1)
        let useCase = DecodeSessionLogTimelineUseCase(rawLogRepository: RawLogRepositoryFake(entries: entries), definitionRepository: DefinitionRepositoryFake(storedDefinitions: [definition]), batchSize: 1)
        var preparedCount: Int?
        var batches: [[SessionLogAnalysisState.TimelineSample]] = []

        try await useCase.execute(
            sessionID: sessionID,
            prepared: { preparedCount = $0 },
            batchDecoded: { batches.append($0) }
        )
        let result = batches.flatMap { $0 }

        XCTAssertEqual(preparedCount, 2)
        XCTAssertEqual(batches.map(\.count), [1, 1])
        XCTAssertEqual(result.map(\.sequence), [0, 1])
        XCTAssertEqual(result[0].decodingFailure, .missingDefinition)
        XCTAssertEqual(result[0].payload, [0x12])
        XCTAssertEqual(result[1].value, 1_726)
        XCTAssertEqual(result[1].unit, "rpm")
    }

    /// グラフ表示はRaw時系列を保持したまま系列ごとの代表点上限へ縮約します。
    ///
    /// 責務: 大量の解析済みPIDを走行集計と上限内の折れ線および散布図へ変換できることを確認します。
    func testVisualizationBuildDownsamplesChartsWithoutMutatingTimeline() {
        let start = Date(timeIntervalSince1970: 1_000)
        var rpm: [SessionLogAnalysisState.TimelineSample] = []
        var speed: [SessionLogAnalysisState.TimelineSample] = []
        rpm.reserveCapacity(1_000)
        speed.reserveCapacity(1_000)
        for index in 0..<1_000 {
            rpm.append(SessionLogAnalysisState.TimelineSample(
                sequence: Int64(index * 2),
                observedAt: start.addingTimeInterval(Double(index) * 0.1),
                service: 0x01,
                pid: 0x0C,
                nameKey: "obd.pid.01.0C.name",
                value: Double(index),
                unit: "rpm",
                payload: [0x00, 0x00],
                decodingFailure: nil
            ))
            speed.append(SessionLogAnalysisState.TimelineSample(
                sequence: Int64(index * 2 + 1),
                observedAt: start.addingTimeInterval(Double(index) * 0.1 + 0.02),
                service: 0x01,
                pid: 0x0D,
                nameKey: "obd.pid.01.0D.name",
                value: Double(index % 120),
                unit: "km/h",
                payload: [0x00],
                decodingFailure: nil
            ))
        }
        let timeline = (rpm + speed).sorted { $0.sequence < $1.sequence }

        let snapshot = SessionLogVisualizationBuilder.build(from: timeline)
        let totalPointCounts = snapshot.series.map { $0.totalPointCount }

        XCTAssertEqual(timeline.count, 2_000)
        XCTAssertEqual(totalPointCounts, [1_000, 1_000])
        XCTAssertTrue(snapshot.series.allSatisfy { $0.points.count <= 600 })
        XCTAssertEqual(snapshot.relationships.first?.points.count, 600)
        XCTAssertFalse(snapshot.performanceSummary.speedBands.isEmpty)
        XCTAssertFalse(snapshot.performanceSummary.rpmBands.isEmpty)
        XCTAssertNotNil(snapshot.performanceSummary.estimatedDistanceKilometers)
    }

    /// 速度と回転数の観測間隔は指定幅の滞在時間ランキングへ変換されます。
    ///
    /// 責務: 10 km/h速度帯と500 rpm回転域を長い欠測を除外して時間順に集計することを確認します。
    func testVisualizationBuildRanksObservedSpeedAndRPMDuration() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let timeline = [
            sample(sequence: 0, date: start, pid: 0x0D, value: 23, unit: "km/h"),
            sample(sequence: 1, date: start.addingTimeInterval(1), pid: 0x0D, value: 27, unit: "km/h"),
            sample(sequence: 2, date: start.addingTimeInterval(2), pid: 0x0D, value: 41, unit: "km/h"),
            sample(sequence: 3, date: start.addingTimeInterval(20), pid: 0x0D, value: 90, unit: "km/h"),
            sample(sequence: 4, date: start, pid: 0x0C, value: 1_200, unit: "rpm"),
            sample(sequence: 5, date: start.addingTimeInterval(1), pid: 0x0C, value: 1_450, unit: "rpm"),
            sample(sequence: 6, date: start.addingTimeInterval(2), pid: 0x0C, value: 2_100, unit: "rpm")
        ]

        let summary = SessionLogVisualizationBuilder.build(from: timeline).performanceSummary

        let speedBand = try XCTUnwrap(summary.speedBands.first)
        XCTAssertEqual(speedBand.lowerBound, 20)
        XCTAssertEqual(speedBand.duration, 2, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedMovingDuration, 2)
        let rpmBand = try XCTUnwrap(summary.rpmBands.first)
        XCTAssertEqual(rpmBand.lowerBound, 1_000)
        XCTAssertEqual(rpmBand.duration, 2, accuracy: 0.001)
    }

    /// 故障コード消去後の走行距離は診断履歴として最新値を保持します。
    ///
    /// 責務: Service 01 PID 31をセッション距離と混同しない診断系観察候補へ変換することを確認します。
    func testVisualizationBuildExposesDistanceSinceCodesClearedAsDiagnosticHistory() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let timeline = [
            sample(sequence: 0, date: start, pid: 0x31, value: 120, unit: "km"),
            sample(sequence: 1, date: start.addingTimeInterval(1), pid: 0x31, value: 121, unit: "km")
        ]

        let insight = try XCTUnwrap(SessionLogVisualizationBuilder.build(from: timeline).componentInsights.first)

        XCTAssertEqual(insight.component, .diagnostics)
        XCTAssertEqual(insight.series.id, OBDPIDRequest(service: 0x01, pid: 0x31))
        XCTAssertEqual(insight.series.latestValue, 121)
        XCTAssertEqual(insight.series.interpretationKey, "analysis.trend.guide.codes_cleared_distance")
    }

    /// ZD8のAT油温を車速との散布図および温度系観察へ追加します。
    ///
    /// 責務: 専用PIDの型式表示情報を維持したまま車速とAT油温を相関表示へ変換することを確認します。
    func testVisualizationBuildAddsZD8ATFRelationshipAndBadgeScope() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let timeline = [
            sample(sequence: 0, date: start, pid: 0x0D, value: 40, unit: "km/h"),
            sample(sequence: 1, date: start.addingTimeInterval(0.1), service: 0x21, pid: 0x17, value: 72, unit: "°C", vehicleModelCode: "ZD8"),
            sample(sequence: 2, date: start.addingTimeInterval(1), pid: 0x0D, value: 60, unit: "km/h"),
            sample(sequence: 3, date: start.addingTimeInterval(1.1), service: 0x21, pid: 0x17, value: 78, unit: "°C", vehicleModelCode: "ZD8")
        ]

        let snapshot = SessionLogVisualizationBuilder.build(from: timeline)
        let relationship = try XCTUnwrap(snapshot.relationships.first { $0.ySeries.id == OBDPIDRequest(service: 0x21, pid: 0x17) })
        let thermal = try XCTUnwrap(snapshot.componentInsights.first { $0.series.id == OBDPIDRequest(service: 0x21, pid: 0x17) })

        XCTAssertEqual(relationship.points.count, 2)
        XCTAssertEqual(relationship.ySeries.vehicleModelCode, "ZD8")
        XCTAssertEqual(relationship.ySeries.interpretationKey, "analysis.trend.guide.zd8_atf")
        XCTAssertEqual(thermal.component, .thermal)
        XCTAssertEqual(thermal.series.vehicleModelCode, "ZD8")
    }

    /// テスト用の数値化済み観測を生成します。
    ///
    /// 責務: 1件の時刻、PID、値を走行集計テスト用サンプルへ変換します。
    /// - Parameters:
    ///   - sequence: Rawログ順序。
    ///   - date: 観測時刻。
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    ///   - value: 数式変換後の値。
    ///   - unit: 定義済み単位。
    ///   - vehicleModelCode: 車種専用PIDの場合の適用型式。
    /// - Returns: 数値化済みタイムラインサンプル。
    private func sample(sequence: Int64, date: Date, service: UInt8 = 0x01, pid: UInt8, value: Double, unit: String, vehicleModelCode: String? = nil) -> SessionLogAnalysisState.TimelineSample {
        SessionLogAnalysisState.TimelineSample(
            sequence: sequence,
            observedAt: date,
            service: service,
            pid: pid,
            nameKey: nil,
            value: value,
            unit: unit,
            vehicleModelCode: vehicleModelCode,
            payload: [],
            decodingFailure: nil
        )
    }
}

/// テスト用の固定Rawログを返すリポジトリです。
private struct RawLogRepositoryFake: ConnectionSessionRawLogRepository {
    /// テストで返すRawログです。
    let entries: [ConnectionSessionRawLogEntry]
    /// このテストでは使用しない追記要求を受理します。
    ///
    /// 責務: 解析読取テストで不要なRaw追記を副作用なく受理します。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {}
    /// 固定Rawログを返します。
    ///
    /// 責務: 任意のセッション読取要求へ固定Rawログを返します。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] { entries }
    /// このテストでは使用しない車両別Rawログを返します。
    ///
    /// 責務: 解析読取テストで不要な車両別照会へ空配列を返します。
    func entries(for vehicleID: VehicleID, accountIdentifier: String) throws -> [VehicleConnectionSessionRawLogEntry] { [] }
    /// このテストでは使用しないCloudKit保存結果を受理します。
    ///
    /// 責務: 解析読取テストで不要なCloudKit保存結果を副作用なく受理します。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}
    /// このテストでは使用しないCloudKit失敗を受理します。
    ///
    /// 責務: 解析読取テストで不要なCloudKit失敗を副作用なく受理します。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}
    /// このテストでは使用しないMac取込結果を受理します。
    ///
    /// 責務: 解析読取テストで不要なMac取込結果を副作用なく受理します。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {}
    /// このテストでは使用しない転送取込を受理します。
    ///
    /// 責務: 解析読取テストで不要な転送取込を副作用なく受理します。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {}
    /// このテストでは使用しないローカル除去を受理します。
    ///
    /// 責務: 解析読取テストで不要なローカル除去を副作用なく受理します。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}
}

/// テスト用の固定PID定義を返すリポジトリです。
private struct DefinitionRepositoryFake: OBDPIDDefinitionRepository {
    /// テストで返すPID定義です。
    let storedDefinitions: [OBDPIDDefinition]
    /// 固定PID定義を返します。
    ///
    /// 責務: 定義一覧要求へ固定PID定義を返します。
    func definitions() throws -> [OBDPIDDefinition] { storedDefinitions }
    /// このテストでは使用しない保存要求を受理します。
    ///
    /// 責務: 解析読取テストで不要な定義保存を副作用なく受理します。
    func upsert(_ definition: OBDPIDDefinition) throws {}
    /// 対応する固定定義を返します。
    ///
    /// 責務: Service/PID検索を対応する固定定義へ変換します。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { storedDefinitions.first { $0.service == service && $0.pid == pid } }
}
