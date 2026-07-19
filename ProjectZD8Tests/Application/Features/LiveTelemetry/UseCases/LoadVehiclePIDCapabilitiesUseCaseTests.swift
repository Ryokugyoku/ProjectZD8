import Foundation
import XCTest
@testable import ProjectZD8

/// 車両別対応PIDの再利用とService 01範囲探索を検証します。
@MainActor
final class LoadVehiclePIDCapabilitiesUseCaseTests: XCTestCase {
    /// 00の継続ビットから20範囲へ進み、範囲照会PID自体を収集対象から除外します。
    ///
    /// 責務: 0x20刻みの対応ビットマップ連鎖を全件有効の車両別設定へ変換することを確認します。
    func testDiscoversChainedRangesAndPersistsAllEnabled() async throws {
        let repository = CapabilityRepositoryFake()
        let telemetry = CapabilityTelemetryFake(responses: [
            0x00: [0x80, 0x00, 0x00, 0x01],
            0x20: [0x80, 0x00, 0x00, 0x00]
        ])
        let useCase = LoadVehiclePIDCapabilitiesUseCase(
            repository: repository,
            telemetry: telemetry,
            now: { Date(timeIntervalSince1970: 123) }
        )

        let capabilities = try await useCase.execute(vehicleID: vehicleID, endpoint: endpoint)

        let queriedPIDs = await telemetry.queriedPIDs
        XCTAssertEqual(queriedPIDs, [0x00, 0x20])
        XCTAssertEqual(capabilities.map(\.id.request.pid), [0x01, 0x21])
        XCTAssertTrue(capabilities.allSatisfy(\.isCollectionEnabled))
        XCTAssertEqual(capabilities.map(\.discoveredAt), [Date(timeIntervalSince1970: 123), Date(timeIntervalSince1970: 123)])
        XCTAssertEqual(try repository.capabilities(for: vehicleID), capabilities)
    }

    /// 保存済み対応PIDが1件でもあれば車両通信を行いません。
    ///
    /// 責務: 既存の車両別収集選択を再探索せずそのまま返すことを確認します。
    func testReusesStoredCapabilitiesWithoutPolling() async throws {
        let stored = VehiclePIDCapability(
            vehicleID: vehicleID,
            request: .init(service: 0x01, pid: 0x0C),
            isCollectionEnabled: false,
            discoveredAt: .distantPast
        )
        let repository = CapabilityRepositoryFake(stored: [stored])
        let telemetry = CapabilityTelemetryFake(responses: [:])
        let useCase = LoadVehiclePIDCapabilitiesUseCase(repository: repository, telemetry: telemetry)

        let result = try await useCase.execute(vehicleID: vehicleID, endpoint: endpoint)

        XCTAssertEqual(result, [stored])
        let queriedPIDs = await telemetry.queriedPIDs
        XCTAssertEqual(queriedPIDs, [])
    }

    /// テスト用車両IDです。
    private var vehicleID: VehicleID { VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!) }
    /// テスト用OBD終端です。
    private var endpoint: OBDConnectionEndpoint { .init(transport: .serial, systemIdentifier: "/dev/test", displayName: "Test") }
}

/// 対応PID設定をメモリ保持するテスト境界です。
private final class CapabilityRepositoryFake: VehiclePIDCapabilityRepository, @unchecked Sendable {
    /// 現在の固定設定です。
    private var stored: [VehiclePIDCapability]

    /// 初期設定を保持します。
    ///
    /// 責務: テスト用の車両別PID保存状態を初期化します。
    /// - Parameter stored: 初期設定。
    init(stored: [VehiclePIDCapability] = []) { self.stored = stored }

    /// 現在設定を返します。
    ///
    /// 責務: テスト用設定一覧を返します。
    /// - Parameter vehicleID: 使用しない車両ID。
    /// - Returns: 現在設定。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] { stored }

    /// 初回設定を保持します。
    ///
    /// 責務: 探索結果をテスト用状態へ保存します。
    /// - Parameters:
    ///   - capabilities: 保存する設定。
    ///   - vehicleID: 使用しない車両ID。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws { stored = capabilities }

    /// テスト対象外の選択更新を受け付けます。
    ///
    /// 責務: テスト対象外の収集選択変更を変更なしで完了します。
    /// - Parameters:
    ///   - isEnabled: 使用しない選択状態。
    ///   - request: 使用しないPID。
    ///   - vehicleID: 使用しない車両ID。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws {}
}

/// 対応ビットマップをPID範囲別に返すテスト境界です。
private actor CapabilityTelemetryFake: OBDPIDTelemetryPort {
    /// 範囲先頭PID別の固定応答です。
    private let responses: [UInt8: [UInt8]]
    /// 照会された範囲先頭PIDです。
    private(set) var queriedPIDs: [UInt8] = []

    /// 固定応答を保持します。
    ///
    /// 責務: 範囲探索テスト用応答を初期化します。
    /// - Parameter responses: 範囲先頭PID別の4バイト応答。
    init(responses: [UInt8: [UInt8]]) { self.responses = responses }

    /// 単一範囲照会へ固定ビットマップを返します。
    ///
    /// 責務: 受信した範囲先頭PIDを記録して対応する固定応答を返します。
    /// - Parameters:
    ///   - requests: 単一の対応範囲照会。
    ///   - endpoint: 使用しないOBD終端。
    /// - Returns: 照会PIDへ対応する固定応答。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        guard let request = requests.first, let bytes = responses[request.pid] else { return [:] }
        queriedPIDs.append(request.pid)
        return [request: bytes]
    }
}
