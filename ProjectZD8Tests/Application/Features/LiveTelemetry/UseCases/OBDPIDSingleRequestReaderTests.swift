import Foundation
import XCTest
@testable import ProjectZD8

/// 1件要求の読取が取得境界の結果・エラーを排他的なTransport観測へ分類することを検証します。
@MainActor
final class OBDPIDSingleRequestReaderTests: XCTestCase {
    /// 標準PIDは1要求だけを送り、観測の結果をそのまま返します。
    ///
    /// 責務: 正応答・タイムアウト・非対応・取消・通信失敗・未分類の各観測が変換されずに返ることを確認します。
    func testStandardPIDReturnsObservedOutcomeForSingleRequest() async {
        let outcomes: [OBDPIDRequestTransportOutcome] = [
            .responded([1, 2]), .timedOut, .unsupported, .cancelled, .transportFailure, .unclassifiedResponse
        ]
        for outcome in outcomes {
            let telemetry = ScriptedOBDPIDTelemetryFake()
            telemetry.observationsResult = .success([.init(request: request, outcome: outcome)])

            let result = await OBDPIDSingleRequestReader(telemetry: telemetry).read(definition, using: endpoint)

            XCTAssertEqual(result, outcome)
            XCTAssertEqual(telemetry.observationRequests, [[request]])
            XCTAssertEqual(telemetry.vehicleSpecificDefinitions, [])
        }
    }

    /// 観測の件数や要求が送った1件と一致しなければ未分類として返します。
    ///
    /// 責務: 0件・2件・別要求の観測を非対応や正応答と推測しないことを確認します。
    func testMismatchedObservationsBecomeUnclassified() async {
        let other = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let cases: [[OBDPIDRequestTransportObservation]] = [
            [],
            [.init(request: request, outcome: .responded([1])), .init(request: request, outcome: .responded([2]))],
            [.init(request: other, outcome: .responded([1]))]
        ]
        for observations in cases {
            let telemetry = ScriptedOBDPIDTelemetryFake()
            telemetry.observationsResult = .success(observations)

            let result = await OBDPIDSingleRequestReader(telemetry: telemetry).read(definition, using: endpoint)

            XCTAssertEqual(result, .unclassifiedResponse, "\(observations)")
        }
    }

    /// 取得境界のエラーを、通信境界の喪失だけ通信失敗、取消は取消、他は未分類へ分類します。
    ///
    /// 責務: `OBDPIDTelemetryError` の全caseと取消・その他エラーの分類を確認します。
    func testThrownErrorsAreClassified() async {
        let cases: [(any Error, OBDPIDRequestTransportOutcome)] = [
            (CancellationError(), .cancelled),
            (OBDPIDTelemetryError.connectionLost, .transportFailure),
            (OBDPIDTelemetryError.unavailable, .transportFailure),
            (OBDPIDTelemetryError.definitionCatalogUnavailable, .unclassifiedResponse),
            (OBDPIDTelemetryError.unsupportedPID, .unclassifiedResponse),
            (OBDPIDTelemetryError.commandRejected, .unclassifiedResponse),
            (OBDPIDTelemetryError.malformedResponse, .unclassifiedResponse),
            (OBDPIDTelemetryError.incompleteResponse, .unclassifiedResponse),
            (OBDPIDTelemetryError.noVehicleResponse, .unclassifiedResponse),
            (StubOBDPIDDefinitionRepository.ReadError(), .unclassifiedResponse)
        ]
        for (error, expected) in cases {
            let telemetry = ScriptedOBDPIDTelemetryFake()
            telemetry.observationsResult = .failure(error)

            let result = await OBDPIDSingleRequestReader(telemetry: telemetry).read(definition, using: endpoint)

            XCTAssertEqual(result, expected, "\(error)")
        }
    }

    /// 車種専用PIDは専用経路で送り、応答があれば正応答、無ければ未分類を返します。
    ///
    /// 責務: 車種専用定義が標準経路を使わず、応答の有無とエラーが分類されることを確認します。
    func testVehicleSpecificPIDUsesDedicatedPath() async {
        let specific = vehicleSpecificDefinition
        let specificRequest = OBDPIDRequest(service: specific.service, pid: specific.pid)
        let cases: [(Result<[OBDPIDRequest: [UInt8]], any Error>, OBDPIDRequestTransportOutcome)] = [
            (.success([specificRequest: [9, 8, 7, 6]]), .responded([9, 8, 7, 6])),
            (.success([:]), .unclassifiedResponse),
            (.failure(OBDPIDTelemetryError.connectionLost), .transportFailure),
            (.failure(CancellationError()), .cancelled)
        ]
        for (response, expected) in cases {
            let telemetry = ScriptedOBDPIDTelemetryFake()
            telemetry.vehicleSpecificResult = response

            let result = await OBDPIDSingleRequestReader(telemetry: telemetry).read(specific, using: endpoint)

            XCTAssertEqual(result, expected)
            XCTAssertEqual(telemetry.vehicleSpecificDefinitions, [[specific]])
            XCTAssertEqual(telemetry.observationRequests, [])
        }
    }

    /// テスト対象の標準PID定義です。
    private var definition: OBDPIDDefinition { LiveTelemetryTestDefinitions.standard(0x0C) }

    /// テスト対象の標準PID要求です。
    private var request: OBDPIDRequest { LiveTelemetryTestDefinitions.request(0x0C) }

    /// テスト用OBD接続終端です。
    private var endpoint: OBDConnectionEndpoint { LiveTelemetryTestDefinitions.endpoint }

    /// ヘッダーと型式コードを持つ車種専用定義です。
    private var vehicleSpecificDefinition: OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x21, pid: 0x02, header: 0x7E0, vehicleModelCode: "ZD8", nameKey: "test.zd8",
            requiredByteCount: 4, formula: "A", unit: "km", minimumValue: nil, maximumValue: nil,
            sourceURI: "test://zd8", revision: 1
        )
    }
}
