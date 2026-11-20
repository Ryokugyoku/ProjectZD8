import Foundation
import XCTest
@testable import ProjectZD8

/// 車両識別の失敗が、失敗段階と原因の文言キーへ正しく変換されることを検証します。
@MainActor
final class VehicleIdentificationFailureTests: XCTestCase {
    /// 段階を持たない識別失敗と、期待する文言キーの対応です。
    private static let stagelessCases: [(error: VehicleIdentificationError, key: String)] = [
        (.vinUnavailable, "garage.error.vin_unavailable"),
        (.pidCatalogUnavailable, "garage.error.pid_catalog"),
        (.connectionFailed, "garage.error.connection"),
        (.responseTimedOut, "garage.error.timeout"),
        (.commandRejected, "garage.error.command_rejected"),
        (.malformedResponse, "garage.error.malformed_response"),
        (.unavailable, "garage.error.obd_unavailable"),
        (.transportUnsupported, "garage.error.obd_unavailable")
    ]

    /// 段階別の失敗で観測した原因と、期待する文言キーの対応です。
    private static let causeCases: [(cause: VehicleIdentificationError.Cause, key: String)] = [
        (.unavailable, "garage.error.obd_unavailable"),
        (.transportUnsupported, "garage.error.obd_unavailable"),
        (.connectionFailed, "garage.error.connection"),
        (.responseTimedOut, "garage.error.timeout"),
        (.commandRejected, "garage.error.command_rejected"),
        (.malformedResponse, "garage.error.malformed_response")
    ]

    /// 失敗段階として存在する全ての段階です。
    private static let allStages: [VehicleIdentificationError.Stage] = [
        .endpointValidation, .transportCreation, .transportOpen, .adapterReset, .adapterConfiguration,
        .adapterIdentity, .vehicleIdentificationRequest, .vehicleIdentificationParsing, .protocolDescription
    ]

    /// 想定外の失敗として渡すエラーです。
    private struct UnexpectedError: Error {}

    /// 段階を伴わない識別失敗は、段階なしで対応する文言キーになります。
    ///
    /// 責務: 段階を持たない全ての識別失敗の case について、段階が `nil` で文言キーが仕様どおりであることを確認します。
    func testStagelessErrorsHaveNoStageAndMatchingKey() {
        for entry in Self.stagelessCases {
            let failure = VehicleIdentificationFailure(error: entry.error)
            XCTAssertNil(failure.stage, "\(entry.error)")
            XCTAssertEqual(failure.failureKey, entry.key, "\(entry.error)")
        }
    }

    /// 段階別の失敗は、原因ごとの文言キーと失敗した段階を保ちます。
    ///
    /// 責務: 全ての原因について、段階つきの失敗が原因に対応する文言キーと渡した段階を持つことを確認します。
    func testStageFailedKeepsStageAndMapsEveryCause() {
        for entry in Self.causeCases {
            let failure = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(.adapterReset, entry.cause))
            XCTAssertEqual(failure.stage, .adapterReset, "\(entry.cause)")
            XCTAssertEqual(failure.failureKey, entry.key, "\(entry.cause)")
        }
    }

    /// 段階別の失敗は、どの段階でも段階をそのまま保ちます。
    ///
    /// 責務: 全ての失敗段階について、変換結果の段階が入力と同じであることを確認します。
    func testStageFailedPreservesEveryStage() {
        for stage in Self.allStages {
            let failure = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(stage, .connectionFailed))
            XCTAssertEqual(failure.stage, stage, "\(stage)")
            XCTAssertEqual(failure.failureKey, "garage.error.connection", "\(stage)")
        }
    }

    /// 識別失敗ではないエラーは、段階なしのOBD利用不可として扱われます。
    ///
    /// 責務: 想定外のエラー(独自型・NSError・キャンセル)が段階なしで `garage.error.obd_unavailable` になることを確認します。
    func testUnexpectedErrorsAreTreatedAsObdUnavailableWithoutStage() {
        let errors: [any Error] = [UnexpectedError(), NSError(domain: "test", code: 1), CancellationError()]
        for error in errors {
            let failure = VehicleIdentificationFailure(error: error)
            XCTAssertNil(failure.stage, "\(error)")
            XCTAssertEqual(failure.failureKey, "garage.error.obd_unavailable", "\(error)")
        }
    }

    /// 同じ段階と文言キーを持つ失敗は等しく、どちらかが違えば等しくありません。
    ///
    /// 責務: `Equatable` が段階と文言キーの両方を比較することを確認します。
    func testEqualityComparesStageAndKey() {
        let base = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(.adapterReset, .responseTimedOut))
        let same = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(.adapterReset, .responseTimedOut))
        let otherStage = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(.adapterIdentity, .responseTimedOut))
        let otherKey = VehicleIdentificationFailure(error: VehicleIdentificationError.stageFailed(.adapterReset, .commandRejected))
        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, otherStage)
        XCTAssertNotEqual(base, otherKey)
    }
}
