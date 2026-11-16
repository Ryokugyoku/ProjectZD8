import XCTest
@testable import ProjectZD8

/// `LiveTelemetryStopReasonRegistry` が、世代ごとに最初に結び付けた停止理由を1回だけ取り出せることを検証します。
///
/// 仕様: U2 受け入れ条件 13(取得記録と終了通知の理由を一致させるため、取り消しより先に理由を結び付ける)。
final class LiveTelemetryStopReasonRegistryTests: XCTestCase {
    /// 結び付けた理由を取り出すと、その世代の理由は消えます。
    ///
    /// 責務: 1回目の `take` で理由が返り、2回目は `nil` になることを確認します。
    func testTakeReturnsRegisteredReasonOnce() {
        let registry = LiveTelemetryStopReasonRegistry()
        registry.register(.accountSignedOut, for: 3)
        XCTAssertEqual(registry.take(for: 3), .accountSignedOut)
        XCTAssertNil(registry.take(for: 3))
    }

    /// 同じ世代へ2回結び付けたら、最初の理由が残ります。
    ///
    /// 責務: 後から結び付けた理由で上書きされないことを確認します。
    func testFirstRegistrationWins() {
        let registry = LiveTelemetryStopReasonRegistry()
        registry.register(.superseded, for: 1)
        registry.register(.userDisconnected, for: 1)
        XCTAssertEqual(registry.take(for: 1), .superseded)
    }

    /// 理由は世代ごとに分かれ、結び付けていない世代は `nil` です。
    ///
    /// 責務: 別の世代の理由を取り出さないことと、未登録の世代が `nil` であることを確認します。
    func testReasonsAreSeparatedByGeneration() {
        let registry = LiveTelemetryStopReasonRegistry()
        registry.register(.connectionLost, for: 1)
        registry.register(.superseded, for: 2)
        XCTAssertNil(registry.take(for: 3))
        XCTAssertEqual(registry.take(for: 2), .superseded)
        XCTAssertEqual(registry.take(for: 1), .connectionLost)
    }
}
