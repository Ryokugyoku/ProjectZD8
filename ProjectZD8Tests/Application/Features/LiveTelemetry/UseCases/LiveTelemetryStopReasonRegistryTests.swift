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

    /// 指定した世代以前の理由はすべて消え、より新しい世代の理由は残ります。
    ///
    /// 責務: 世代1・2・3へ結び付けて `discard(through: 2)` した後、1と2が `nil`、3が残り、件数が1であることを確認します
    /// (U8 R3。同じ世代は消え、新しい世代は残る境界)。
    func testDiscardThroughRemovesSameAndOlderGenerationsOnly() {
        let registry = LiveTelemetryStopReasonRegistry()
        registry.register(.userDisconnected, for: 1)
        registry.register(.accountSignedOut, for: 2)
        registry.register(.superseded, for: 3)

        registry.discard(through: 2)

        XCTAssertEqual(registry.registeredCount, 1)
        XCTAssertNil(registry.take(for: 1))
        XCTAssertNil(registry.take(for: 2))
        XCTAssertEqual(registry.take(for: 3), .superseded)
    }

    /// 結び付けていない世代や空の入れ物で消しても、何も起きません。
    ///
    /// 責務: 空での `discard(through: 0)` と、世代5だけがある時の `discard(through: 4)` で件数が変わらないことを確認します。
    func testDiscardThroughWithoutOlderRegistrationsKeepsNewer() {
        let registry = LiveTelemetryStopReasonRegistry()
        registry.discard(through: 0)
        XCTAssertEqual(registry.registeredCount, 0)

        registry.register(.connectionLost, for: 5)
        registry.discard(through: 4)
        XCTAssertEqual(registry.registeredCount, 1)
        XCTAssertEqual(registry.take(for: 5), .connectionLost)
    }

    /// 件数は、取り出されていない世代の数です(同じ世代への2回目の結び付けでは増えず、取り出すと減ります)。
    ///
    /// 責務: 空・2世代の登録・同じ世代への再登録・1件の取り出しの後の `registeredCount` を確認します。
    func testRegisteredCountTracksUntakenGenerations() {
        let registry = LiveTelemetryStopReasonRegistry()
        XCTAssertEqual(registry.registeredCount, 0)
        registry.register(.userDisconnected, for: 1)
        registry.register(.superseded, for: 2)
        registry.register(.accountSignedOut, for: 2)
        XCTAssertEqual(registry.registeredCount, 2)
        _ = registry.take(for: 1)
        XCTAssertEqual(registry.registeredCount, 1)
    }
}
