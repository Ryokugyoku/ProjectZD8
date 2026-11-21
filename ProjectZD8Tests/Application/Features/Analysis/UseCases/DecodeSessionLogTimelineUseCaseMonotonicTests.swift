import Foundation
import XCTest
@testable import ProjectZD8

/// 保存済みPIDログの時系列変換が、Rawログの単調時刻をサンプルへ運ぶことを検証します。
@MainActor
final class DecodeSessionLogTimelineUseCaseMonotonicTests: XCTestCase {
    /// 単調時刻を持つ行は、その値が時系列サンプルへ渡ります。
    ///
    /// 責務: 単調時刻のある行が同じ値を持つサンプルになり、既存の項目が変わらないことを確認します。
    func testMonotonicNanosecondsAreCarriedToSamples() async throws {
        let entries = [
            makeEntry(sequence: 0, seconds: 10, payload: [0x1A, 0xF8], monotonic: 5_000_000_000),
            makeEntry(sequence: 1, seconds: 11, payload: [0x20, 0x00], monotonic: 6_250_000_000)
        ]

        let result = try await decode(entries)

        XCTAssertEqual(result.map(\.monotonicNanoseconds), [5_000_000_000, 6_250_000_000])
        XCTAssertEqual(result.map(\.sequence), [0, 1])
        XCTAssertEqual(result.map(\.observedAt), [Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 11)])
        XCTAssertEqual(result.map(\.value), [1_726, 2_048])
        XCTAssertEqual(result.map(\.unit), ["rpm", "rpm"])
        XCTAssertEqual(result.map(\.payload), [[0x1A, 0xF8], [0x20, 0x00]])
    }

    /// 単調時刻の無い旧い行は nil のままです。
    ///
    /// 責務: 単調時刻が nil の行から作ったサンプルが nil を保ち、ほかの項目が変わらないことを確認します。
    func testMissingMonotonicNanosecondsStayNil() async throws {
        let entries = [makeEntry(sequence: 3, seconds: 30, payload: [0x1A, 0xF8], monotonic: nil)]

        let result = try await decode(entries)

        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].monotonicNanoseconds)
        XCTAssertEqual(result[0].sequence, 3)
        XCTAssertEqual(result[0].observedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(result[0].value, 1_726)
    }

    /// 単調時刻のある行と無い行が混在しても、行ごとに対応します。
    ///
    /// 責務: 値あり・nil・0 が混在する行が、それぞれの行の単調時刻を保つことを確認します。
    func testMonotonicNanosecondsAreMappedPerEntryIncludingZero() async throws {
        let entries = [
            makeEntry(sequence: 0, seconds: 1, payload: [0x1A, 0xF8], monotonic: nil),
            makeEntry(sequence: 1, seconds: 2, payload: [0x1A, 0xF8], monotonic: 0),
            makeEntry(sequence: 2, seconds: 3, payload: [0x1A, 0xF8], monotonic: UInt64.max)
        ]

        let result = try await decode(entries)

        XCTAssertEqual(result.map(\.monotonicNanoseconds), [nil, 0, UInt64.max])
    }

    /// 定義の無いPIDの行でも単調時刻は失われません。
    ///
    /// 責務: 数値化できない行(定義なし)が単調時刻を保持したまま Raw として残ることを確認します。
    func testMonotonicNanosecondsSurviveForUndecodableEntries() async throws {
        let entries = [makeEntry(sequence: 0, seconds: 5, service: 0x01, pid: 0xFF, payload: [0x12], monotonic: 777)]

        let result = try await decode(entries)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].decodingFailure, .missingDefinition)
        XCTAssertNil(result[0].value)
        XCTAssertEqual(result[0].monotonicNanoseconds, 777)
    }

    /// `TimelineSample` の初期化で単調時刻を省くと nil になります。
    ///
    /// 責務: 既存の呼び出しを壊さない既定値(nil)と、明示した値の保持を確認します。
    func testTimelineSampleMonotonicDefaultsToNil() {
        let withoutValue = makeSample(monotonic: nil, omit: true)
        let withValue = makeSample(monotonic: 42, omit: false)

        XCTAssertNil(withoutValue.monotonicNanoseconds)
        XCTAssertEqual(withValue.monotonicNanoseconds, 42)
    }

    /// 検証用のRawログを変換してサンプルの並びで返します。
    ///
    /// 責務: 回転数定義だけを持つ変換器へ指定の行を渡し、全サンプルを集めます。
    /// - Parameter entries: 変換するRawログ。
    /// - Returns: 通知された全サンプル。
    private func decode(_ entries: [ConnectionSessionRawLogEntry]) async throws -> [SessionLogAnalysisState.TimelineSample] {
        let definition = OBDPIDDefinition(
            service: 0x01, pid: 0x0C, nameKey: "obd.pid.01.0C.name", requiredByteCount: 2,
            formula: "(A * 256 + B) / 4", unit: "rpm", minimumValue: 0, maximumValue: 16_383.75,
            sourceURI: "https://example.invalid", revision: 1
        )
        let useCase = DecodeSessionLogTimelineUseCase(
            rawLogRepository: MonotonicRawLogRepositoryFake(entries: entries),
            definitionRepository: MonotonicDefinitionRepositoryFake(storedDefinitions: [definition]),
            batchSize: 2
        )
        var batches: [[SessionLogAnalysisState.TimelineSample]] = []
        try await useCase.execute(sessionID: ConnectionSessionID(), prepared: { _ in }, batchDecoded: { batches.append($0) })
        return batches.flatMap { $0 }
    }

    /// 検証用のRawログ1行を作ります。
    ///
    /// 責務: 回転数PIDを既定とするRawログ行を、単調時刻の有無を指定して生成します。
    /// - Parameters:
    ///   - sequence: 記録順序。
    ///   - seconds: 観測時刻(1970年からの秒)。
    ///   - service: OBD Service番号。
    ///   - pid: PID番号。
    ///   - payload: 応答データ。
    ///   - monotonic: 単調時刻。
    /// - Returns: 検証用のRawログ行。
    private func makeEntry(
        sequence: Int64, seconds: TimeInterval, service: UInt8 = 0x01, pid: UInt8 = 0x0C,
        payload: [UInt8], monotonic: UInt64?
    ) -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: sequence, observedAt: Date(timeIntervalSince1970: seconds), batchElapsedNanoseconds: 1,
            service: service, pid: pid, payload: payload, monotonicNanoseconds: monotonic
        )
    }

    /// 検証用のサンプルを作ります。
    ///
    /// 責務: 単調時刻の引数を省いた初期化と、指定した初期化を切り替えて生成します。
    /// - Parameters:
    ///   - monotonic: 指定する単調時刻。
    ///   - omit: true の場合は引数自体を省いて初期化します。
    /// - Returns: 検証用のサンプル。
    private func makeSample(monotonic: UInt64?, omit: Bool) -> SessionLogAnalysisState.TimelineSample {
        let date = Date(timeIntervalSince1970: 1)
        if omit {
            return .init(sequence: 0, observedAt: date, service: 0x01, pid: 0x0C, nameKey: nil, value: 1, unit: nil,
                         payload: [], decodingFailure: nil)
        }
        return .init(sequence: 0, observedAt: date, service: 0x01, pid: 0x0C, nameKey: nil, value: 1, unit: nil,
                     payload: [], decodingFailure: nil, monotonicNanoseconds: monotonic)
    }
}

/// テスト用の固定Rawログを返すリポジトリです。
private struct MonotonicRawLogRepositoryFake: ConnectionSessionRawLogRepository {
    /// テストで返すRawログです。
    let entries: [ConnectionSessionRawLogEntry]
    /// 固定Rawログを返します。
    ///
    /// 責務: 任意のセッション読取要求へ固定Rawログを返します。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] { entries }
    /// 使用しない車両別Rawログを返します。
    ///
    /// 責務: 不要な車両別照会へ空配列を返します。
    func entries(for vehicleID: VehicleID, accountIdentifier: String) throws -> [VehicleConnectionSessionRawLogEntry] { [] }
    /// 使用しないCloudKit保存結果を受理します。
    ///
    /// 責務: 不要な保存結果を副作用なく受理します。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}
    /// 使用しないCloudKit失敗を受理します。
    ///
    /// 責務: 不要な失敗通知を副作用なく受理します。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}
    /// 使用しないMac取込結果を受理します。
    ///
    /// 責務: 不要な取込結果を副作用なく受理します。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {}
    /// 使用しない転送取込を受理します。
    ///
    /// 責務: 不要な転送取込を副作用なく受理します。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {}
    /// 使用しないローカル除去を受理します。
    ///
    /// 責務: 不要な除去要求を副作用なく受理します。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}
}

/// テスト用の固定PID定義を返すリポジトリです。
private struct MonotonicDefinitionRepositoryFake: OBDPIDDefinitionRepository {
    /// テストで返すPID定義です。
    let storedDefinitions: [OBDPIDDefinition]
    /// 固定PID定義を返します。
    ///
    /// 責務: 定義一覧要求へ固定PID定義を返します。
    func definitions() throws -> [OBDPIDDefinition] { storedDefinitions }
    /// 使用しない保存要求を受理します。
    ///
    /// 責務: 不要な定義保存を副作用なく受理します。
    func upsert(_ definition: OBDPIDDefinition) throws {}
    /// 対応する固定定義を返します。
    ///
    /// 責務: Service/PID検索を対応する固定定義へ変換します。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { storedDefinitions.first { $0.service == service && $0.pid == pid } }
}
