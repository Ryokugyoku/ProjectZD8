import Foundation
import XCTest
@testable import ProjectZD8

/// 検証済み主要PIDの一括読取と数値化を検証します。
@MainActor
final class ReadMajorOBDPIDsUseCaseTests: XCTestCase {
    /// 実車観測バイトを冷却水温と回転数へ変換します。
    ///
    /// 責務: 2件の検証済み定義が1回の読取応答から名称と単位付き数値になることを確認します。
    func testExecuteDecodesObservedCoolantAndEngineSpeedBytes() async throws {
        let telemetry = MajorPIDTelemetryFake(values: [
            .init(service: 0x01, pid: 0x05): [0x85],
            .init(service: 0x01, pid: 0x0C): [0x00, 0x00]
        ])
        let useCase = ReadMajorOBDPIDsUseCase(
            definitions: StandardOBDPIDSeed.definitions,
            telemetry: telemetry,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let samples = try await useCase.execute(using: endpoint)
        let receivedRequests = await telemetry.receivedRequests

        XCTAssertEqual(samples.map(\.value), [93, 0])
        XCTAssertEqual(samples.map(\.unit), ["°C", "rpm"])
        XCTAssertEqual(samples.map(\.observedAt), [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 100)])
        XCTAssertEqual(receivedRequests, StandardOBDPIDSeed.definitions.map { .init(service: $0.service, pid: $0.pid) })
    }

    /// 応答欠落を零値へ変換しません。
    ///
    /// 責務: 定義済みPIDの一部が返らない場合に不完全応答として失敗することを確認します。
    func testExecuteRejectsMissingMajorPIDResponse() async {
        let telemetry = MajorPIDTelemetryFake(values: [.init(service: 0x01, pid: 0x05): [0x85]])
        let useCase = ReadMajorOBDPIDsUseCase(definitions: StandardOBDPIDSeed.definitions, telemetry: telemetry)

        do {
            _ = try await useCase.execute(using: endpoint)
            XCTFail("応答欠落は成功してはいけません")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .incompleteResponse)
        }
    }

    /// テスト用OBD接続終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "OBDLink EX")
    }
}

/// 主要PIDユースケースへ固定バイト辞書を返す境界です。
private actor MajorPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 要求別に返す固定バイトです。
    private let values: [OBDPIDRequest: [UInt8]]
    /// 直近に受け取った要求順です。
    private(set) var receivedRequests: [OBDPIDRequest] = []

    /// 固定応答辞書を保持します。
    ///
    /// 責務: テストで返すService/PID別バイトを初期化します。
    /// - Parameter values: 要求別の固定応答。
    init(values: [OBDPIDRequest: [UInt8]]) { self.values = values }

    /// 受信要求を記録して固定応答を返します。
    ///
    /// 責務: 1回の読取要求群を観測して注入済み応答辞書を返します。
    /// - Parameters:
    ///   - requests: 観測するService/PID要求。
    ///   - endpoint: テストでは使用しない接続終端。
    /// - Returns: 初期化時に保持した応答辞書。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        receivedRequests = requests
        return values
    }
}
