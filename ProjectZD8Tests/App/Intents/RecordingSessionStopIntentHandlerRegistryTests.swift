import XCTest
@testable import ProjectZD8

/// `RecordingSessionStopIntentHandlerRegistry` の登録・呼び出し・未登録時・置き換え・解除を検証します。
///
/// 仕様: U5 受け入れ条件 10(B14)。static 状態は各テストの前後で `unregister()` により後始末します。
@MainActor
final class RecordingSessionStopIntentHandlerRegistryTests: XCTestCase {
    /// 呼ばれた停止処理の記録です。
    private var calls: [String] = []

    /// 責務: 登録を外した状態から始めます。
    override func setUp() async throws {
        try await super.setUp()
        RecordingSessionStopIntentHandlerRegistry.unregister()
        calls = []
    }

    /// 責務: 登録を外して後始末します。
    override func tearDown() async throws {
        RecordingSessionStopIntentHandlerRegistry.unregister()
        try await super.tearDown()
    }

    /// 未登録なら登録されておらず、停止を実行しても何も起きません。
    ///
    /// 責務: `isRegistered` が偽で `performStop()` が何も呼ばないことを確認します。
    func testUnregisteredPerformStopDoesNothing() {
        XCTAssertFalse(RecordingSessionStopIntentHandlerRegistry.isRegistered)
        RecordingSessionStopIntentHandlerRegistry.performStop()
        XCTAssertEqual(calls, [])
    }

    /// 登録した停止処理を、停止の実行ごとに1回呼びます。
    ///
    /// 責務: 登録後の `isRegistered` と、2回の実行で2回呼ばれることを確認します。
    func testRegisteredHandlerIsCalledPerStop() {
        RecordingSessionStopIntentHandlerRegistry.register { [weak self] in self?.calls.append("first") }
        XCTAssertTrue(RecordingSessionStopIntentHandlerRegistry.isRegistered)

        RecordingSessionStopIntentHandlerRegistry.performStop()
        RecordingSessionStopIntentHandlerRegistry.performStop()

        XCTAssertEqual(calls, ["first", "first"])
    }

    /// 後から登録した停止処理で置き換え、前の処理は呼びません。
    ///
    /// 責務: 2回登録した後の実行で、2回目の処理だけが呼ばれることを確認します。
    func testLaterRegistrationReplaces() {
        RecordingSessionStopIntentHandlerRegistry.register { [weak self] in self?.calls.append("first") }
        RecordingSessionStopIntentHandlerRegistry.register { [weak self] in self?.calls.append("second") }

        RecordingSessionStopIntentHandlerRegistry.performStop()

        XCTAssertEqual(calls, ["second"])
    }

    /// 解除すると登録されていない状態へ戻り、停止を実行しても呼びません。
    ///
    /// 責務: 解除後の `isRegistered` が偽で、実行しても呼ばれないことを確認します。
    func testUnregisterRemovesHandler() {
        RecordingSessionStopIntentHandlerRegistry.register { [weak self] in self?.calls.append("first") }

        RecordingSessionStopIntentHandlerRegistry.unregister()
        RecordingSessionStopIntentHandlerRegistry.performStop()

        XCTAssertFalse(RecordingSessionStopIntentHandlerRegistry.isRegistered)
        XCTAssertEqual(calls, [])
    }
}
