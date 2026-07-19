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
            definitionRepository: MajorPIDDefinitionRepositoryFake(
                definitions: StandardOBDPIDSeed.definitions
            ),
            telemetry: telemetry,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let samples = try await useCase.execute(using: endpoint)
        let receivedRequests = await telemetry.receivedRequests

        XCTAssertEqual(samples.map(\.value), [93, 0])
        XCTAssertEqual(samples.map(\.unit), ["°C", "rpm"])
        XCTAssertEqual(samples.map(\.observedAt), [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 100)])
        XCTAssertEqual(receivedRequests, StandardOBDPIDSeed.definitions.filter(\.isDecodable).map { .init(service: $0.service, pid: $0.pid) })
    }

    /// 応答しないPIDを対応済み一覧へ含めません。
    ///
    /// 責務: 定義済みPIDの一部が返らない場合に応答済み観測だけを返すことを確認します。
    func testExecuteKeepsOnlyRespondingPIDs() async throws {
        let telemetry = MajorPIDTelemetryFake(values: [.init(service: 0x01, pid: 0x05): [0x85]])
        let useCase = ReadMajorOBDPIDsUseCase(
            definitionRepository: MajorPIDDefinitionRepositoryFake(
                definitions: StandardOBDPIDSeed.definitions
            ),
            telemetry: telemetry
        )

        let samples = try await useCase.execute(using: endpoint)

        XCTAssertEqual(samples.map(\.request), [.init(service: 0x01, pid: 0x05)])
        XCTAssertEqual(samples.map(\.value), [93])
    }

    /// Repositoryが返した数式と単位を固定seedより優先します。
    ///
    /// 責務: PID要求と数値化が実行時に取得したRepository定義だけを使用することを確認します。
    func testExecuteUsesDefinitionsLoadedFromRepository() async throws {
        let databaseDefinition = OBDPIDDefinition(
            service: 0x01,
            pid: 0x05,
            nameKey: "database.name",
            requiredByteCount: 1,
            formula: "A + 10",
            unit: "db-unit",
            minimumValue: nil,
            maximumValue: nil,
            sourceURI: "test://database",
            revision: 2
        )
        let telemetry = MajorPIDTelemetryFake(values: [
            .init(service: 0x01, pid: 0x05): [5]
        ])
        let useCase = ReadMajorOBDPIDsUseCase(
            definitionRepository: MajorPIDDefinitionRepositoryFake(
                definitions: [databaseDefinition]
            ),
            telemetry: telemetry
        )

        let samples = try await useCase.execute(using: endpoint)
        let receivedRequests = await telemetry.receivedRequests

        XCTAssertEqual(samples.map(\.nameKey), ["database.name"])
        XCTAssertEqual(samples.map(\.value), [15])
        XCTAssertEqual(samples.map(\.unit), ["db-unit"])
        XCTAssertEqual(receivedRequests, [.init(service: 0x01, pid: 0x05)])
    }

    /// PID定義DBが空の場合は実車要求を開始しません。
    ///
    /// 責務: 空のRepository一覧を固定seedへ戻さず専用エラーとして拒否することを確認します。
    func testExecuteRejectsEmptyDefinitionCatalogBeforeTelemetryRead() async {
        let telemetry = MajorPIDTelemetryFake(values: [:])
        let useCase = ReadMajorOBDPIDsUseCase(
            definitionRepository: MajorPIDDefinitionRepositoryFake(definitions: []),
            telemetry: telemetry
        )

        do {
            _ = try await useCase.execute(using: endpoint)
            XCTFail("空のPID定義一覧は成功してはいけません")
        } catch {
            let receivedRequests = await telemetry.receivedRequests
            XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            XCTAssertEqual(receivedRequests, [])
        }
    }

    /// PID定義DBの読込失敗を通信失敗と区別します。
    ///
    /// 責務: Repositoryエラーを専用カタログ利用不能エラーへ変換することを確認します。
    func testExecuteMapsRepositoryFailureBeforeTelemetryRead() async {
        let telemetry = MajorPIDTelemetryFake(values: [:])
        let useCase = ReadMajorOBDPIDsUseCase(
            definitionRepository: MajorPIDDefinitionRepositoryFake(error: RepositoryReadError()),
            telemetry: telemetry
        )

        do {
            _ = try await useCase.execute(using: endpoint)
            XCTFail("PID定義読込失敗は成功してはいけません")
        } catch {
            let receivedRequests = await telemetry.receivedRequests
            XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            XCTAssertEqual(receivedRequests, [])
        }
    }

    /// テスト用OBD接続終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "OBDLink EX")
    }
}

/// テスト用のPID定義一覧または読込失敗を返します。
private struct MajorPIDDefinitionRepositoryFake: OBDPIDDefinitionRepository {
    /// 返却するPID定義一覧です。
    private let storedDefinitions: [OBDPIDDefinition]
    /// 一覧読込時に送出するエラーです。
    private let storedError: (any Error)?

    /// 固定PID定義一覧を保持します。
    ///
    /// 責務: テストで返すPID定義一覧を初期化します。
    /// - Parameter definitions: 一覧読込時に返す定義。
    init(definitions: [OBDPIDDefinition]) {
        storedDefinitions = definitions
        storedError = nil
    }

    /// 固定読込エラーを保持します。
    ///
    /// 責務: テストで送出するRepositoryエラーを初期化します。
    /// - Parameter error: 一覧読込時に送出するエラー。
    init(error: any Error) {
        storedDefinitions = []
        storedError = error
    }

    /// 固定PID定義一覧を返すか固定エラーを送出します。
    ///
    /// 責務: 注入済みのRepository読込結果を再現します。
    /// - Returns: 初期化時に保持したPID定義一覧。
    /// - Throws: 初期化時に保持した読込エラー。
    func definitions() throws -> [OBDPIDDefinition] {
        if let storedError { throw storedError }
        return storedDefinitions
    }

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

/// PID定義Repositoryの読込失敗を再現します。
private struct RepositoryReadError: Error {}

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
