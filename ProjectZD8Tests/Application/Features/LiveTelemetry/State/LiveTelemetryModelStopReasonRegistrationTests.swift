import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel の停止で、取得ループに結び付けた停止理由が取り出されないまま溜まらないこと(取得が動いていない時の停止・
/// 準備の失敗・準備中の取り消し・通常の終了)と、先の停止が終わった後の新しい取得の停止は受け付けることを検証します。
///
/// 仕様: U8 R3。
@MainActor
final class LiveTelemetryModelStopReasonRegistrationTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixtures: [LiveTelemetryModelFixture] = []

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        for fixture in fixtures { await fixture.tearDown() }
        fixtures.removeAll()
        try await super.tearDown()
    }

    /// 取得が動いていない時の停止は、理由を結び付けません。
    ///
    /// 責務: 開始していないモデルへ `stopRequested` と `endRequested` を送っても、登録が0件のままであることを確認します。
    func testStopWithoutAcquisitionDoesNotRegisterReason() async {
        let fixture = make()

        fixture.model.send(.stopRequested)
        fixture.model.send(.endRequested(.accountSignedOut))
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.loop.registeredStopReasonCount, 0)
    }

    /// 取得中の停止で終えた後は、登録が残りません。
    ///
    /// 責務: 読み込み済みからの `stopRequested` で待機へ戻った後、登録が0件であることを確認します。
    func testNormalStopLeavesNoRegistration() async {
        let fixture = await makeLoaded()

        fixture.model.send(.stopRequested)
        guard await fixture.waitUntil("待機状態", condition: { fixture.model.state.phase == .idle }) else { return }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.loop.registeredStopReasonCount, 0)
    }

    /// 準備(PIDカタログの読込)に失敗して終えた後は、登録が残りません。
    ///
    /// 責務: カタログ読込の失敗で失敗表示になった後、続けて停止しても登録が0件であることを確認します。
    func testPreparationFailureLeavesNoRegistration() async {
        let fixture = make(catalog: [], failsCatalog: true, recordsAcquisition: false)
        fixture.start()
        guard await fixture.waitUntil("失敗表示", condition: { fixture.model.state.phase == .failed }) else { return }

        fixture.model.send(.stopRequested)
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.loop.registeredStopReasonCount, 0)
    }

    /// 準備中に停止(取り消し)した後は、登録が残りません。
    ///
    /// 責務: 開始の直後(準備の途中)の `endRequested(.superseded)` で終えた後、登録が0件で、要求を送らないことを確認します。
    func testStopDuringPreparationLeavesNoRegistration() async {
        let fixture = make()
        fixture.start()

        fixture.model.send(.endRequested(.superseded))
        guard await fixture.waitUntil("準備中の停止の後の待機", condition: { fixture.model.state.phase == .idle }) else { return }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.loop.registeredStopReasonCount, 0)
    }

    /// 先の停止が終わった後に始めた取得の停止は受け付け、その理由で取得記録と終了通知を1回ずつ終えます。
    ///
    /// 責務: 1回目(ユーザー切断)の終了の後、2回目の取得を置き換えで止めると、終了通知と取得記録の理由が
    /// `[.userDisconnected, .superseded]` になり、登録が0件であることを確認します。
    func testStopAfterPreviousStopCompletedIsAccepted() async {
        let fixture = await makeLoaded()
        fixture.model.send(.stopRequested)
        guard await fixture.waitUntil("1回目の待機", condition: { fixture.model.state.phase == .idle }) else { return }

        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        guard await fixture.waitUntil("2回目の読み込み済み", condition: { fixture.model.state.phase == .loaded }) else { return }
        fixture.model.send(.endRequested(.superseded))
        guard await fixture.waitUntil("2回目の待機", condition: { fixture.model.state.phase == .idle }) else { return }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected, .superseded])
        let finishes = await fixture.recorder?.finishCalls ?? []
        let reasons = finishes.compactMap { if case let .finish(_, reason) = $0 { reason } else { nil } }
        XCTAssertEqual(reasons, [.userDisconnected, .superseded])
        XCTAssertEqual(fixture.loop.registeredStopReasonCount, 0)
    }

    /// 部品を生成して後片付けの対象にします。
    ///
    /// 責務: PIDカタログと読込の失敗を指定したモデル部品を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - failsCatalog: カタログ読込を失敗させる場合は `true`。
    ///   - recordsAcquisition: 記録ポートのスパイを付ける場合は `true`(付けなければカタログ全体を取得対象にします)。
    /// - Returns: モデル部品。
    private func make(
        catalog: [OBDPIDDefinition] = LiveTelemetryTestDefinitions.standard([0x0C]), failsCatalog: Bool = false, recordsAcquisition: Bool = true
    ) -> LiveTelemetryModelFixture {
        let recorder = recordsAcquisition ? LiveTelemetryRecordingPortSpy() : nil
        let fixture = LiveTelemetryModelFixture(catalog: catalog, failsCatalog: failsCatalog, recorder: recorder)
        fixtures.append(fixture)
        return fixture
    }

    /// PID 0x0C だけを開始し、初回周回の正応答で読み込み済みにします。
    ///
    /// 責務: 読み込み済みで次の要求を待つ状態のモデル部品を返します。
    /// - Returns: モデル部品。
    private func makeLoaded() async -> LiveTelemetryModelFixture {
        let fixture = make()
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        return fixture
    }
}
