import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryModel.acquisitionDidStart` が、取得が実際に始まった時点(最初の周回で ECU が正応答し取得対象が確定した時)に
/// 取得セッションごとに1回だけ呼ばれ、準備の失敗や応答のない周回では呼ばれないことを検証します。
///
/// 仕様: U4 受け入れ条件 1・2(記録開始の確定 = 取得の開始まで進んだ時。辞退・失敗では確定しない)。
@MainActor
final class LiveTelemetryModelAcquisitionDidStartTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?
    /// `acquisitionDidStart` が呼ばれた回数です。
    private var startCount = 0

    /// 責務: 動いている取得を止めます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        startCount = 0
        try await super.tearDown()
    }

    /// 部品を作り、取得の開始の通知先を数える処理へ結び付けます。
    ///
    /// 責務: 指定のカタログと記録ポートの部品を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログ。
    ///   - failsCatalog: カタログ読込を失敗させるか。
    ///   - recorder: 記録ポートのスパイ。
    /// - Returns: 部品。
    private func make(
        catalog: [OBDPIDDefinition] = LiveTelemetryTestDefinitions.standard([0x0C]),
        failsCatalog: Bool = false,
        recorder: LiveTelemetryRecordingPortSpy? = nil
    ) -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: catalog, failsCatalog: failsCatalog, recorder: recorder)
        fixture.model.acquisitionDidStart = { [weak self] in self?.startCount += 1 }
        self.fixture = fixture
        return fixture
    }

    /// 最初の周回で正応答して取得対象が確定した時に1回呼ばれ、以後の周回では呼ばれません。
    ///
    /// 責務: 開始直後0回、初回の正応答の後1回、さらに3周回答えても1回のままであることを確認します。
    func testCalledOnceWhenFirstRoundConfirmsTargets() async {
        let fixture = make()
        fixture.start()
        XCTAssertEqual(startCount, 0, "開始要求の時点では呼ばない")

        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("取得対象の確定") { fixture.model.state.phase == .loaded }
        XCTAssertEqual(startCount, 1)

        await fixture.telemetry.answer(3) { _ in .responded([1]) }
        await fixture.telemetry.waitForSentRequests(5)
        XCTAssertEqual(startCount, 1)
    }

    /// 最初の周回で正応答が無ければ呼ばれず、正応答した周回で初めて呼ばれます。
    ///
    /// 責務: 非対応応答だけの周回の後0回、次の正応答の後1回であることを確認します。
    func testNotCalledUntilECURespondsPositively() async {
        let fixture = make()
        fixture.start()

        await fixture.telemetry.release(.unsupported)
        await fixture.telemetry.waitForSentRequests(2)
        XCTAssertEqual(startCount, 0)

        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("取得対象の確定") { fixture.model.state.phase == .loaded }
        XCTAssertEqual(startCount, 1)
    }

    /// PIDカタログを読めない準備の失敗では呼ばれません。
    ///
    /// 責務: 失敗表示になった後も0回であることを確認します。
    func testNotCalledWhenPreparationFails() async {
        let fixture = make(catalog: [], failsCatalog: true)
        fixture.start()

        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }

        XCTAssertEqual(startCount, 0)
    }

    /// 記録の開始(接続セッションの取得記録の作成)に失敗した場合は呼ばれません。
    ///
    /// 責務: 記録ポートの開始失敗で失敗表示になった後も0回であることを確認します。
    func testNotCalledWhenRecordingStartFails() async {
        let fixture = make(recorder: LiveTelemetryRecordingPortSpy(failing: .start))
        fixture.start()

        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }

        XCTAssertEqual(startCount, 0)
    }

    /// 停止した後に取得を始め直したら、新しい取得セッションの確定で再び1回呼ばれます。
    ///
    /// 責務: 1回目の確定・停止・2回目の確定で合計2回になることを確認します。
    func testCalledAgainForNextAcquisition() async {
        let fixture = make()
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("1回目の確定") { fixture.model.state.phase == .loaded }
        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }
        XCTAssertEqual(startCount, 1)

        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("2回目の確定") { startCount == 2 }

        XCTAssertEqual(startCount, 2)
    }
}
