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

        model.send(.startRequested(endpoint))
        for _ in 0..<100 {
            if await telemetry.readCount >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.state.phase, .loaded)
        let readCount = await telemetry.readCount
        XCTAssertGreaterThanOrEqual(readCount, 2)
        model.send(.stopRequested)
        XCTAssertEqual(model.state.phase, .idle)
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

        model.send(.startRequested(endpoint))
        for _ in 0..<100 where model.state.phase != .failed {
            await Task.yield()
        }

        XCTAssertEqual(model.state.phase, .failed)
        XCTAssertEqual(model.state.failureKey, "telemetry.error.pid_catalog_unavailable")
    }

    /// テスト用OBD接続終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "Test adapter")
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
