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
