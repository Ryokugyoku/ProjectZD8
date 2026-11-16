import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` が、検知待ち以外で届いた[記録開始]の選択(プロセス終了後に残った通知から起動した場合など)を
/// 有効期限2分の「記録開始の意思」として扱い、期限内の検知で通知を出し直さずに記録を始めることを検証します。
///
/// 仕様: U4 受け入れ条件 5〜8。時間は fake の時計の `now` を進めて表します。有効期限ちょうど(2分)の扱いは仕様で未確定のため、直前と直後だけを確かめます。
@MainActor
final class AdapterLinkSupervisionUseCaseRecordingIntentTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 記録開始の意思の有効期限(2分)の秒数です。
    private let intentLifetime: TimeInterval = 120

    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 自動記録オフの手段を組み立て、終了処理の対象に加えます。
    ///
    /// 責務: 手段を返します。
    /// - Returns: 手段。
    private func makeHarness() -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(isAutomaticRecordingEnabled: false)
        harnesses.append(harness)
        return harness
    }

    /// リンク `ready` から VIN 読取の完了まで、車両の検知を進めます(時計は進めません)。
    ///
    /// 責務: 初期化・ECU の応答・VIN 読取を順に完了させ、検知の後の作用が落ち着くまで待ちます。
    /// - Parameter harness: 監視を開始済みの手段。
    private func completeDetection(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await harness.makeLinkReady(file: file, line: line)
        try await harness.finishInitialization(file: file, line: line)
        try await harness.answerRespondingAndWaitForVINRead(file: file, line: line)
        harness.vinReader.responses.resumeOldest(with: .success(F.vin), file: file, line: line)
        try await harness.wait("検知の後の記録開始か検知通知", file: file, line: line) {
            !harness.recordingControl.startRequests.isEmpty || !harness.notifications.presentedVehicleDetectedVINs.isEmpty
        }
    }

    /// 監視の開始時に、前のプロセスが残した検知通知を取り下げます。
    ///
    /// 責務: サインイン済みで監視を始めた時点で、通知の取り下げが1回以上行われることを確認します(受け入れ条件 8)。
    func testSupervisionStartDismissesLeftoverNotification() {
        let harness = makeHarness()
        XCTAssertEqual(harness.notifications.dismissCount, 0)
        harness.startSignedIn()
        XCTAssertGreaterThan(harness.notifications.dismissCount, 0)
    }

    /// 待機中に届いた[記録開始]の後、有効期限内に車両の検知が完了したら、検知通知を出し直さずに記録を始めます(自動記録オフでも)。
    ///
    /// 責務: 記録開始要求が1件(接続終端・VIN・判定結果)で、検知通知が0件で、記録中になることを確認します(受け入れ条件 5・6)。
    func testSelectionBeforeDetectionStartsRecordingOnDetection() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()

        try await completeDetection(harness)

        XCTAssertEqual(harness.recordingControl.startRequests, [F.expectedStartRequest(vin: F.vin)])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// 有効期限の直前(2分の1ミリ秒前)に検知が完了すれば、記録を始めます。
    ///
    /// 責務: 選択から119.999秒後の検知完了で記録開始要求が1件出ることを確認します(受け入れ条件 5・10 の境界)。
    func testSelectionJustBeforeExpiryStartsRecording() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        harness.clock.now = F.referenceDate.addingTimeInterval(intentLifetime - 0.001)

        try await completeDetection(harness)

        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 有効期限の直後(2分の1ミリ秒後)に検知が完了したら、意思は捨てられ、記録を始めずに通常の検知通知になります。
    ///
    /// 責務: 選択から120.001秒後の検知完了で記録開始要求が0件、検知通知が1件であることを確認します(受け入れ条件 7・10 の境界)。
    func testSelectionAfterExpiryDoesNotStartRecording() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        harness.clock.now = F.referenceDate.addingTimeInterval(intentLifetime + 0.001)

        try await completeDetection(harness)

        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [F.vin])
    }

    /// 監視が動いていない時に届いた[記録開始]は捨てられ、後で監視を始めて検知しても記録を始めません。
    ///
    /// 責務: 監視の開始前の選択の後、検知完了で記録開始要求が0件で、通常の検知通知になることを確認します(受け入れ条件 7)。
    func testSelectionBeforeSupervisionStartIsDiscarded() async throws {
        let harness = makeHarness()
        harness.useCase.recordingStartSelected()
        harness.startSignedIn()

        try await completeDetection(harness)

        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [F.vin])
    }
}
