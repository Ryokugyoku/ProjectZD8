import XCTest
@testable import ProjectZD8

/// デモOBD識別とPID応答が通常境界と同じ型で返ることを検証します。
@MainActor
final class DemoOBDAdaptersTests: XCTestCase {
    /// 合成VINを持つ登録可能な車両観測を返します。
    ///
    /// 責務: デモ識別結果がVINと車両フィールドを保持することを確認します。
    func testIdentificationReturnsSyntheticVINThroughNormalSnapshot() async throws {
        let snapshot = try await DemoVehicleIdentificationAdapter(
            now: { Date(timeIntervalSince1970: 123) }
        ).identifyVehicle(using: endpoint)

        XCTAssertEqual(snapshot.vin, DemoOBDAdapter.syntheticVIN(for: endpoint))
        XCTAssertEqual(snapshot.fields.first(where: { $0.id == "manufacturer" })?.value, "RevTorque Demo Motors")
        XCTAssertEqual(snapshot.observedAt, Date(timeIntervalSince1970: 123))
    }

    /// 連続読取で車速と回転数が相関して変化します。
    ///
    /// 責務: デモPID境界が要求済み車速と回転数へ更新可能な未加工値を返すことを確認します。
    func testTelemetryReturnsChangingSpeedAndEngineSpeed() async throws {
        let adapter = DemoOBDPIDTelemetryAdapter()
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let engineSpeed = OBDPIDRequest(service: 0x01, pid: 0x0C)

        let first = try await adapter.read([speed, engineSpeed], using: endpoint)
        let second = try await adapter.read([speed, engineSpeed], using: endpoint)

        XCTAssertNotEqual(first[speed], second[speed])
        XCTAssertNotEqual(first[engineSpeed], second[engineSpeed])
    }

    /// 登録済み主要PIDすべてへ数値化可能な正常域応答を返します。
    ///
    /// 責務: デモPID境界が主要カタログ全件を欠落なく正常域の値へ変換できることを確認します。
    func testTelemetryReturnsAllCatalogValuesWithinDeclaredRanges() async throws {
        let definitions = StandardOBDPIDSeed.definitions.filter(\.isDecodable)
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        let readings = try await DemoOBDPIDTelemetryAdapter().read(requests, using: endpoint)
        let evaluator = OBDPIDFormulaEvaluator()

        XCTAssertEqual(definitions.count, 87)
        XCTAssertEqual(readings.count, 87)
        XCTAssertEqual(
            Set(requests.map(OBDPIDCategory.category(for:))),
            Set(OBDPIDCategory.allCases)
        )
        for category in OBDPIDCategory.allCases {
            XCTAssertEqual(OBDPIDCategory.category(for: category.representativeRequest), category)
        }
        for definition in definitions {
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            let bytes = try XCTUnwrap(readings[request])
            let value = try evaluator.evaluate(definition, bytes: bytes)
            XCTAssertGreaterThanOrEqual(value, try XCTUnwrap(definition.minimumValue))
            XCTAssertLessThanOrEqual(value, try XCTUnwrap(definition.maximumValue))
        }
    }

    /// 初回読取で全Service 01 PIDへ従来どおりの応答バイトを返します。
    ///
    /// 責務: 対応ビットマップ以外の全PIDについて、初回更新時の合成応答と未登録PIDの欠落を固定値で確認します。
    func testTelemetryReturnsExpectedBytesForEveryPIDOnFirstRead() async throws {
        // 初回更新(tick 1)では車速2、回転数908、冷却水温72になる。
        var expected: [UInt8: [UInt8]] = [
            0x04: [57], 0x05: [112], 0x0A: [100], 0x0B: [42], 0x0C: [0x0E, 0x30], 0x0D: [2],
            0x0E: [148], 0x0F: [70], 0x10: [0x04, 0xD4], 0x11: [44], 0x1F: [0x00, 0x01],
            0x21: [0, 0], 0x22: [0x0E, 0xD5], 0x23: [0x01, 0x90], 0x2C: [77], 0x2D: [128],
            0x2E: [38], 0x2F: [166], 0x30: [2], 0x31: [0x00, 0x78], 0x32: [0x80, 0x00], 0x33: [100],
            0x42: [0x37, 0x78], 0x43: [0x00, 0x44], 0x44: [0x80, 0x00], 0x45: [42], 0x46: [65],
            0x47: [42], 0x48: [42], 0x4D: [0, 0], 0x4E: [0, 0], 0x50: [20], 0x52: [128],
            0x53: [0x27, 0x10], 0x54: [0x7F, 0xFF], 0x59: [0x01, 0x90], 0x5A: [128], 0x5B: [128],
            0x5C: [120], 0x5D: [0x6E, 0x00], 0x5E: [0x00, 0xC8], 0x61: [125], 0x62: [125],
            0x63: [0x01, 0x90], 0x7C: [0x11, 0x30], 0x8D: [128], 0x8E: [125], 0xA2: [0x01, 0x00],
            0xA4: [0x00, 0x00, 0x03, 0xE8], 0xA5: [0x00, 0x80], 0xA6: [0x00, 0x01, 0xE2, 0x40]
        ]
        for pid in UInt8(0x06)...0x09 { expected[pid] = [128] }
        for pid in UInt8(0x14)...0x1B { expected[pid] = [140, 128] }
        for pid in UInt8(0x24)...0x2B { expected[pid] = [0x80, 0x00, 0x00, 0x00] }
        for pid in UInt8(0x34)...0x3B { expected[pid] = [0x80, 0x00, 0x00, 0x00] }
        for pid in UInt8(0x3C)...0x3F { expected[pid] = [0x13, 0x24] }
        for pid in UInt8(0x49)...0x4C { expected[pid] = [37] }
        let requests = (UInt8(0)...0xFF)
            .filter { $0 % 0x20 != 0 }
            .map { OBDPIDRequest(service: 0x01, pid: $0) }

        let readings = try await DemoOBDPIDTelemetryAdapter().read(requests, using: endpoint)

        for request in requests {
            XCTAssertEqual(readings[request], expected[request.pid], "PID \(request.pid)")
        }
    }

    /// Bluetoothデモ終端もUSBデモと同じ合成車両へ接続されることを検証します。
    ///
    /// 責務: iOS向けBluetoothデモ終端が通常の識別・PID境界でVINと車速を返すことを確認します。
    func testBluetoothEndpointUsesNormalDemoIdentificationAndTelemetryBoundaries() async throws {
        let bluetoothEndpoint = OBDConnectionEndpoint(adapter: DemoOBDAdapter.bluetoothCandidate)
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)

        let snapshot = try await DemoVehicleIdentificationAdapter().identifyVehicle(using: bluetoothEndpoint)
        let readings = try await DemoOBDPIDTelemetryAdapter().read([speed], using: bluetoothEndpoint)

        XCTAssertEqual(snapshot.vin, DemoOBDAdapter.syntheticVIN(for: bluetoothEndpoint))
        XCTAssertNotNil(readings[speed])
    }

    /// USBとBluetoothの全デモ終端でVINが重複しないことを検証します。
    ///
    /// 責務: 追加後の6件デモ終端が順序依存でユニークな車両識別子を返すことを確認します。
    func testAllDemoEndpointsUseDistinctVINs() async throws {
        let candidates = DemoOBDAdapter.usbCandidates + DemoOBDAdapter.bluetoothCandidates

        XCTAssertEqual(candidates.count, 6)
        var vins: Set<String> = []
        for candidate in candidates {
            let snapshot = try await DemoVehicleIdentificationAdapter().identifyVehicle(
                using: OBDConnectionEndpoint(adapter: candidate)
            )
            let vin = try XCTUnwrap(snapshot.vin)
            XCTAssertTrue(vins.insert(vin).inserted)
        }
        XCTAssertEqual(vins.count, 6)
    }

    /// デモ累積走行距離を履歴画面へ渡せる正常値として返します。
    ///
    /// 責務: Service 01 PID A6の4バイト応答が12,345.6 kmへ数値化されることを確認します。
    func testTelemetryReturnsUsableOdometerValue() async throws {
        let definition = try XCTUnwrap(
            StandardOBDPIDSeed.definitions.first { $0.service == 0x01 && $0.pid == 0xA6 }
        )
        let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
        let readings = try await DemoOBDPIDTelemetryAdapter().read([request], using: endpoint)
        let bytes = try XCTUnwrap(readings[request])

        XCTAssertEqual(try OBDPIDFormulaEvaluator().evaluate(definition, bytes: bytes), 12_345.6)
    }

    /// デモ累積走行距離を継続取得に伴って増加させます。
    ///
    /// 責務: Service 01 PID A6が履歴用セッション走行距離を算出できる累積値として進行することを確認します。
    func testTelemetryAdvancesOdometerForSessionDistance() async throws {
        let definition = try XCTUnwrap(
            StandardOBDPIDSeed.definitions.first { $0.service == 0x01 && $0.pid == 0xA6 }
        )
        let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
        let adapter = DemoOBDPIDTelemetryAdapter()
        let firstReadings = try await adapter.read([request], using: endpoint)
        let firstBytes = try XCTUnwrap(firstReadings[request])
        for _ in 0..<10 {
            _ = try await adapter.read([request], using: endpoint)
        }
        let latestReadings = try await adapter.read([request], using: endpoint)
        let latestBytes = try XCTUnwrap(latestReadings[request])
        let evaluator = OBDPIDFormulaEvaluator()

        XCTAssertGreaterThan(
            try evaluator.evaluate(definition, bytes: latestBytes),
            try evaluator.evaluate(definition, bytes: firstBytes)
        )
    }

    /// 通常終端のPID読取をデモ値生成へ流しません。
    ///
    /// 責務: 予約済みデモ識別子以外の終端が実通信PID境界だけへ委譲されることを確認します。
    func testNonDemoEndpointRoutesTelemetryOnlyToLiveBoundary() async throws {
        let request = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let live = FixedRoutingTelemetryFake(byte: 42)
        let demo = FixedRoutingTelemetryFake(byte: 99)
        let adapter = DemoAwareOBDPIDTelemetryAdapter(live: live, demo: demo)
        let liveEndpoint = OBDConnectionEndpoint(
            transport: .serial,
            systemIdentifier: "/dev/cu.OBDLinkEX",
            displayName: "OBDLink EX"
        )

        let readings = try await adapter.read([request], using: liveEndpoint)
        let liveReadCount = await live.readCount
        let demoReadCount = await demo.readCount

        XCTAssertEqual(readings[request], [42])
        XCTAssertEqual(liveReadCount, 1)
        XCTAssertEqual(demoReadCount, 0)
    }

    /// 通常終端の車両識別をデモVIN生成へ流しません。
    ///
    /// 責務: 予約済みデモ識別子以外の終端が実通信車両識別境界だけへ委譲されることを確認します。
    func testNonDemoEndpointRoutesIdentificationOnlyToLiveBoundary() async throws {
        let live = FixedRoutingIdentificationFake(vin: "LIVEVIN0000000001")
        let demo = FixedRoutingIdentificationFake(vin: "TESTZD8CXR0000001")
        let adapter = DemoAwareVehicleIdentificationAdapter(live: live, demo: demo)
        let liveEndpoint = OBDConnectionEndpoint(
            transport: .bluetoothLowEnergy,
            systemIdentifier: "8DE3C46C-E22A-4D98-A461-REAL-ADAPTER",
            displayName: "Real BLE Adapter"
        )

        let snapshot = try await adapter.identifyVehicle(using: liveEndpoint)
        let liveReadCount = live.readCount
        let demoReadCount = demo.readCount

        XCTAssertEqual(snapshot.vin, "LIVEVIN0000000001")
        XCTAssertEqual(liveReadCount, 1)
        XCTAssertEqual(demoReadCount, 0)
    }

    /// テスト用デモ終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)
    }
}

/// PID振分け先と呼出回数を返すテスト用取得境界です。
@MainActor
private final class FixedRoutingTelemetryFake: OBDPIDTelemetryPort {
    /// 応答へ格納する固定バイトです。
    private let byte: UInt8
    /// PID読取を受けた回数です。
    private(set) var readCount = 0

    /// 固定応答バイトと空の呼出履歴を保持します。
    ///
    /// 責務: PID振分け検証用の固定取得境界を生成します。
    /// - Parameter byte: 各要求へ返す固定バイト。
    init(byte: UInt8) {
        self.byte = byte
    }

    /// 各要求へ固定バイトを返して呼出回数を記録します。
    ///
    /// 責務: 1回のPID読取要求群を呼出履歴付き固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 固定応答を割り当てるPID要求。
    ///   - endpoint: 振分け後の終端。テストでは値を使用しません。
    /// - Returns: 各要求に固定バイトを割り当てた応答。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        readCount += 1
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, [byte]) })
    }
}

/// VIN振分け先と呼出回数を返すテスト用識別境界です。
@MainActor
private final class FixedRoutingIdentificationFake: VehicleIdentificationPort {
    /// 応答へ格納する固定VINです。
    private let vin: String
    /// 車両識別を受けた回数です。
    private(set) var readCount = 0

    /// 固定VINと空の呼出履歴を保持します。
    ///
    /// 責務: 車両識別振分け検証用の固定取得境界を生成します。
    /// - Parameter vin: 識別観測へ返す固定VIN。
    init(vin: String) {
        self.vin = vin
    }

    /// 固定VINの車両識別観測を返して呼出回数を記録します。
    ///
    /// 責務: 1回の車両識別要求を呼出履歴付き固定観測へ変換します。
    /// - Parameter endpoint: 振分け後の終端。テストでは値を使用しません。
    /// - Returns: 固定VINを持つ車両識別観測。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        readCount += 1
        return VehicleIdentificationSnapshot(
            vin: vin,
            fields: [],
            observedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
