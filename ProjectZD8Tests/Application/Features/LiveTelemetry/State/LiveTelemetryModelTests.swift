import XCTest
@testable import ProjectZD8

/// LiveTelemetryのPID定義DB失敗表示を検証します。
@MainActor
final class LiveTelemetryModelTests: XCTestCase {
    /// 初回探索後もPID取得を繰り返します。
    ///
    /// 責務: 接続開始が単発読取ではなく継続更新へ遷移することを確認します。
    func testStartContinuesPollingAfterInitialDiscovery() async {
        let telemetry = CountingPIDTelemetryFake()
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: FixedPIDDefinitionRepository(),
                telemetry: telemetry
            )
        )

        model.send(.startRequested(endpoint, vehicleID, .standardPolling))
        for _ in 0..<100 {
            if await telemetry.readCount >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.phase, .loaded)
        let readCount = await telemetry.readCount
        XCTAssertGreaterThanOrEqual(readCount, 2)
        model.send(.stopRequested)
        XCTAssertEqual(model.state.phase, .stopping)
        for _ in 0..<100 where model.state.phase != .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// ユーザー同意後にBRZ Beta要求を2件の周期取得へ切り替えます。
    ///
    /// 責務: 同意前に周期要求を送らず、同意後だけBeta表示状態へ遷移することを確認します。
    func testBRZBetaRequiresConsentBeforeUsingPeriodicEngineAndVehicleSpeed() async {
        let telemetry = PeriodicPIDTelemetryFake()
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: BRZBetaPIDDefinitionRepository(),
                telemetry: telemetry
            )
        )

        model.send(.startRequested(endpoint, vehicleID, .brzBetaPeriodic))
        for _ in 0..<100 where model.state.phase != .awaitingBRZBetaConsent {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.phase, .awaitingBRZBetaConsent)
        let countBeforeConsent = await telemetry.periodicReadCount
        XCTAssertEqual(countBeforeConsent, 0)

        model.send(.brzBetaAccepted)
        for _ in 0..<100 where model.state.acquisitionMode != .brzBetaPeriodic || model.state.phase != .loaded {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.acquisitionMode, .brzBetaPeriodic)
        XCTAssertEqual(model.state.samples.map(\.request), BRZBetaPIDPolicy.requests)
        let periodicReadCount = await telemetry.periodicReadCount
        XCTAssertGreaterThanOrEqual(periodicReadCount, 1)
        model.send(.stopRequested)
    }

    /// BRZ Betaを拒否した場合は標準取得へ進みます。
    ///
    /// 責務: ユーザーの通常モード選択が周期要求なしの標準ポーリングへ変換されることを確認します。
    func testBRZBetaDeclineUsesStandardPollingWithoutPeriodicRequest() async {
        let telemetry = PeriodicPIDTelemetryFake()
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: BRZBetaPIDDefinitionRepository(),
                telemetry: telemetry
            )
        )

        model.send(.startRequested(endpoint, vehicleID, .brzBetaPeriodic))
        for _ in 0..<100 where model.state.phase != .awaitingBRZBetaConsent {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.send(.brzBetaDeclined)
        for _ in 0..<100 where model.state.phase != .loaded {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.acquisitionMode, .standardPolling)
        let periodicReadCount = await telemetry.periodicReadCount
        XCTAssertEqual(periodicReadCount, 0)
        model.send(.stopRequested)
    }

    /// PID定義DB失敗を通信失敗とは異なる表示キーへ反映します。
    ///
    /// 責務: カタログ利用不能エラーが専用の失敗表示状態になることを確認します。
    func testReadMapsDefinitionCatalogFailureToDedicatedMessage() async {
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: FailingPIDDefinitionRepository(),
                telemetry: UnavailableOBDPIDTelemetryAdapter()
            )
        )

        model.send(.startRequested(endpoint, vehicleID, .standardPolling))
        for _ in 0..<100 where model.state.phase != .failed {
            await Task.yield()
        }

        XCTAssertEqual(model.state.phase, .failed)
        XCTAssertEqual(model.state.failureKey, "telemetry.error.pid_catalog_unavailable")
    }

    /// 切断要求が通信セッション終了後に待機状態へ戻ることを検証します。
    ///
    /// 責務: 手動切断が取得取消しと通信資源解放の完了を待つことを確認します。
    func testStopWaitsForSessionEndBeforeBecomingIdle() async {
        let telemetry = EndTrackingPIDTelemetryFake()
        var endReasons: [ConnectionSessionEndReason] = []
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: FixedPIDDefinitionRepository(),
                telemetry: telemetry
            ),
            sessionDidEnd: { endReasons.append($0) }
        )
        model.send(.startRequested(endpoint, vehicleID, .standardPolling))
        for _ in 0..<100 where model.state.phase == .reading {
            try? await Task.sleep(for: .milliseconds(10))
        }

        model.send(.stopRequested)

        XCTAssertEqual(model.state.phase, .stopping)
        for _ in 0..<100 where model.state.phase != .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state.phase, .idle)
        let endCount = await telemetry.endCount
        XCTAssertGreaterThanOrEqual(endCount, 1)
        XCTAssertEqual(endReasons, [.userDisconnected])
    }

    /// 継続取得中に全PID応答が消えた場合の自動切断を検証します。
    ///
    /// 責務: ECU無応答を接続中の失敗表示ではなく安全終了済みの未接続状態へ変換することを確認します。
    func testNoVehicleResponseEndsSessionAndBecomesDisconnected() async {
        let telemetry = InitialResponseThenEmptyPIDTelemetryFake()
        var endReasons: [ConnectionSessionEndReason] = []
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: FixedPIDDefinitionRepository(),
                telemetry: telemetry
            ),
            sessionDidEnd: { endReasons.append($0) }
        )

        model.send(.startRequested(endpoint, vehicleID, .standardPolling))
        for _ in 0..<150 where model.state.failureKey == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertEqual(model.state.failureKey, "telemetry.disconnected.no_response")
        let endCount = await telemetry.endCount
        XCTAssertGreaterThanOrEqual(endCount, 1)
        XCTAssertEqual(endReasons, [.vehicleNoResponse])
    }

    /// A6観測を累積走行距離通知としてLogging境界へ渡します。
    ///
    /// 責務: 数値化済みService 01 PID A6が走行距離コールバックへ通知されることを確認します。
    func testOdometerSampleNotifiesLoggingBoundary() async {
        var observedKilometers: [Double] = []
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: FixedOdometerDefinitionRepository(),
                telemetry: FixedOdometerTelemetryFake()
            ),
            odometerDidChange: { observedKilometers.append($0) }
        )

        model.send(.startRequested(endpoint, vehicleID, .standardPolling))
        for _ in 0..<100 where observedKilometers.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(observedKilometers.first, 12_345.6)
        model.send(.stopRequested)
    }

    /// テスト用OBD接続終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "Test adapter")
    }

    /// テスト用のアプリ内車両IDです。
    private var vehicleID: VehicleID {
        VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
    }
}

/// BRZ Beta用の回転数と車速定義を返すテストRepositoryです。
private struct BRZBetaPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// 固定定義Repositoryを生成します。
    ///
    /// 責務: BRZ Betaモデルテスト用の定義供給境界を構築します。
    init() {}

    /// 回転数と車速の定義を返します。
    ///
    /// 責務: Beta周期取得で数値化する2件の固定定義を返します。
    /// - Returns: Service 01 PID 0Cと0Dの定義。
    func definitions() throws -> [OBDPIDDefinition] {
        [
            OBDPIDDefinition(
                service: 0x01,
                pid: 0x0C,
                nameKey: "test.engine_speed",
                requiredByteCount: 2,
                formula: "(A * 256 + B) / 4",
                unit: "rpm",
                minimumValue: 0,
                maximumValue: nil,
                sourceURI: "test://engine-speed",
                revision: 1
            ),
            OBDPIDDefinition(
                service: 0x01,
                pid: 0x0D,
                nameKey: "test.vehicle_speed",
                requiredByteCount: 1,
                formula: "A",
                unit: "km/h",
                minimumValue: 0,
                maximumValue: nil,
                sourceURI: "test://vehicle-speed",
                revision: 1
            )
        ]
    }

    /// テスト対象外の保存要求を受け付けます。
    ///
    /// 責務: 未使用のPID定義保存を変更なしで完了します。
    /// - Parameter definition: テストでは使用しない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// テスト対象外の単一定義読込へ未登録を返します。
    ///
    /// 責務: 未使用の単一PID照会を未登録結果へ変換します。
    /// - Parameters:
    ///   - service: テストでは使用しないService番号。
    ///   - pid: テストでは使用しないPID番号。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
}

/// 直接読取と周期読取へ固定した回転数と車速を返します。
private actor PeriodicPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 周期読取を呼び出された回数です。
    private(set) var periodicReadCount = 0

    /// 空の周期読取履歴を生成します。
    ///
    /// 責務: BRZ Betaテスト用の周期読取回数を初期化します。
    init() {}

    /// 対応確認用の回転数と車速を返します。
    ///
    /// 責務: 直接読取要求を2件の固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 応答するService/PID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 回転数2,000 rpmと車速50 km/hの未加工バイト。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        values(for: requests)
    }

    /// 周期応答として回転数と車速を返します。
    ///
    /// 責務: 1回の周期受信要求を回数記録付き固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 応答するService/PID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 回転数2,000 rpmと車速50 km/hの未加工バイト。
    func readPeriodic(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        periodicReadCount += 1
        return values(for: requests)
    }

    /// 指定要求だけを固定応答辞書へ変換します。
    ///
    /// 責務: Service 01 PID 0Cと0Dを決定的な未加工値へ対応付けます。
    /// - Parameter requests: 応答対象の要求。
    /// - Returns: 入力に含まれる対応要求だけの辞書。
    private func values(for requests: [OBDPIDRequest]) -> [OBDPIDRequest: [UInt8]] {
        let available: [OBDPIDRequest: [UInt8]] = [
            OBDPIDRequest(service: 0x01, pid: 0x0C): [0x1F, 0x40],
            OBDPIDRequest(service: 0x01, pid: 0x0D): [0x32]
        ]
        return available.filter { requests.contains($0.key) }
    }
}

/// A6定義だけを返すテスト用PID Repositoryです。
private struct FixedOdometerDefinitionRepository: OBDPIDDefinitionRepository {
    /// A6通知テスト用の空状態を生成します。
    ///
    /// 責務: 固定累積走行距離定義を提供するテスト境界を構築します。
    init() {}

    /// 累積走行距離定義を1件返します。
    ///
    /// 責務: Service 01 PID A6の固定定義一覧を返します。
    /// - Returns: 4バイトの累積走行距離定義1件。
    func definitions() throws -> [OBDPIDDefinition] {
        [OBDPIDDefinition(
            service: 0x01,
            pid: 0xA6,
            nameKey: "obd.pid.odometer",
            requiredByteCount: 4,
            formula: "(A * 16777216 + B * 65536 + C * 256 + D) / 10",
            unit: "km",
            minimumValue: 0,
            maximumValue: nil,
            sourceURI: "test://odometer",
            revision: 1
        )]
    }

    /// テスト対象外の保存要求を受け付けます。
    ///
    /// 責務: 未使用のPID定義保存を変更なしで完了します。
    /// - Parameter definition: テストでは使用しない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// テスト対象外の単一定義読込へ未登録を返します。
    ///
    /// 責務: 未使用の単一PID照会を未登録結果へ変換します。
    /// - Parameters:
    ///   - service: テストでは使用しないService番号。
    ///   - pid: テストでは使用しないPID番号。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
}

/// 固定の累積走行距離応答を返すテスト用PID境界です。
private actor FixedOdometerTelemetryFake: OBDPIDTelemetryPort {
    /// A6通知テスト用の空状態を生成します。
    ///
    /// 責務: 固定累積走行距離応答を提供するテスト境界を構築します。
    init() {}

    /// 要求PIDへ12,345.6 km相当の固定バイトを返します。
    ///
    /// 責務: 1回のA6読取要求を固定累積走行距離応答へ変換します。
    /// - Parameters:
    ///   - requests: 応答するPID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: A6へ12,345.6 km相当の4バイトを割り当てた辞書。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        Dictionary(uniqueKeysWithValues: requests.map { ($0, [0x00, 0x01, 0xE2, 0x40]) })
    }
}

/// 回転数定義を返すテスト用PID Repositoryです。
private struct FixedPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// 固定定義Repositoryを生成します。
    ///
    /// 責務: 継続取得テスト用のPID定義供給境界を構築します。
    init() {}

    /// 回転数定義を1件返します。
    ///
    /// 責務: 継続取得に使用する固定PID定義一覧を返します。
    /// - Returns: Service 01 PID 0Cの定義1件。
    func definitions() throws -> [OBDPIDDefinition] {
        [OBDPIDDefinition(
            service: 0x01,
            pid: 0x0C,
            nameKey: "test.engine_speed",
            requiredByteCount: 2,
            formula: "(A * 256 + B) / 4",
            unit: "rpm",
            minimumValue: 0,
            maximumValue: nil,
            sourceURI: "test://engine-speed",
            revision: 1
        )]
    }

    /// テスト対象外の保存要求を受け付けます。
    ///
    /// 責務: 未使用のPID定義保存を変更なしで完了します。
    /// - Parameter definition: テストでは使用しない定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// テスト対象外の単一定義読込へ未登録を返します。
    ///
    /// 責務: 未使用の単一PID照会を未登録結果へ変換します。
    /// - Parameters:
    ///   - service: テストでは使用しないService番号。
    ///   - pid: テストでは使用しないPID番号。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
}

/// 読取回数を記録して固定回転数バイトを返します。
private actor CountingPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 受け取った読取要求の回数です。
    private(set) var readCount = 0

    /// 空の読取履歴を生成します。
    ///
    /// 責務: 継続取得テストの読取回数を初期化します。
    init() {}

    /// 読取回数を増やして要求PIDへ固定バイトを返します。
    ///
    /// 責務: 1回のPID読取要求を計数済み固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 応答するPID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 各要求に対する800 rpm相当バイト。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        readCount += 1
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, [0x0C, 0x80]) })
    }
}

/// 終了通知回数を記録する固定応答PID境界です。
private actor EndTrackingPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 受け取った終了通知の回数です。
    private(set) var endCount = 0

    /// 空の終了通知履歴を生成します。
    ///
    /// 責務: 安全終了テスト用のPID境界を初期化します。
    init() {}

    /// 要求PIDへ固定回転数バイトを返します。
    ///
    /// 責務: 1回のPID読取要求を固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 応答するPID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 各要求に対する800 rpm相当バイト。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        Dictionary(uniqueKeysWithValues: requests.map { ($0, [0x0C, 0x80]) })
    }

    /// 終了通知回数を増やします。
    ///
    /// 責務: 1件の通信セッション終了通知を記録します。
    func endSession() async {
        endCount += 1
    }
}

/// 初回だけ応答し、その後はECU無応答を再現するPID境界です。
private actor InitialResponseThenEmptyPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 受け取った読取回数です。
    private var readCount = 0
    /// 受け取った終了通知の回数です。
    private(set) var endCount = 0

    /// 空の読取・終了履歴を生成します。
    ///
    /// 責務: ECU応答消失テスト用のPID境界を初期化します。
    init() {}

    /// 初回は固定応答、その後は空応答を返します。
    ///
    /// 責務: 継続取得中にECU応答が消失する境界を再現します。
    /// - Parameters:
    ///   - requests: 初回だけ応答するPID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 初回は固定応答、2回目以降は空辞書。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        readCount += 1
        guard readCount == 1 else { return [:] }
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, [0x0C, 0x80]) })
    }

    /// 終了通知回数を増やします。
    ///
    /// 責務: 自動切断による通信セッション終了通知を記録します。
    func endSession() async {
        endCount += 1
    }
}

/// PID定義一覧の読込に必ず失敗します。
private struct FailingPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// PID定義読込失敗を表します。
    private struct ReadError: Error {}

    /// 常に失敗するPID定義Repositoryを生成します。
    ///
    /// 責務: PID定義読込失敗を再現する境界を生成します。
    init() {}

    /// PID定義一覧の読込失敗を送出します。
    ///
    /// 責務: LiveTelemetryへRepository読込失敗を通知します。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常にテスト用読込エラー。
    func definitions() throws -> [OBDPIDDefinition] { throw ReadError() }

    /// このテストでは使用しないPID定義保存です。
    ///
    /// 責務: テスト対象外の保存要求を変更なしで受け付けます。
    /// - Parameter definition: 使用しないPID定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// このテストでは使用しない単一PID定義読込です。
    ///
    /// 責務: テスト対象外の単一読込へ未登録を返します。
    /// - Parameters:
    ///   - service: 使用しないOBD Service番号。
    ///   - pid: 使用しないService内PID番号。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
}
