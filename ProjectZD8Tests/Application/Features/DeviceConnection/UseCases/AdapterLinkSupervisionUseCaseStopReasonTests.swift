import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` が、記録中の停止要求に原因ごとの理由を付け、記録中のリンク可用性の変化を記録側へ伝えることを検証します。
///
/// 仕様: U2 受け入れ条件 4・9〜12 と管理チャットの決定 i(別のアダプターへの変更は置き換え)。
@MainActor
final class AdapterLinkSupervisionUseCaseStopReasonTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 記録中まで進めた手段を返します。
    ///
    /// 責務: 手段を組み立てて終了処理の対象に加え、記録中まで進めます。
    /// - Returns: 記録中の手段。
    private func recordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness()
        harnesses.append(harness)
        try await harness.driveToRecording(file: file, line: line)
        return harness
    }

    /// 記録中のサインアウトは `accountSignedOut` で停止を要求します。
    ///
    /// 責務: 停止理由が1件だけで `accountSignedOut` であることを確認します(仕様 9)。
    func testSignOutStopsWithAccountSignedOut() async throws {
        let harness = try await recordingHarness()
        harness.useCase.authenticationDidChange(isSignedIn: false)
        XCTAssertEqual(harness.recordingControl.stopReasons, [.accountSignedOut])
    }

    /// 記録中の手動接続の開始は `superseded` で停止を要求します。
    ///
    /// 責務: 停止理由が1件だけで `superseded` であることを確認します(仕様 10)。
    func testExternalAdapterUseStopsWithSuperseded() async throws {
        let harness = try await recordingHarness()
        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.recordingControl.stopReasons, [.superseded])
    }

    /// 記録中に既定アダプターを別のアダプター(別の BLE・Classic・シリアル)へ変えたら `superseded` で停止を要求します。
    ///
    /// 責務: 変更先ごとに停止理由が `superseded` の1件であることを確認します(仕様 10、決定 i)。
    func testDefaultAdapterChangedToOtherAdapterStopsWithSuperseded() async throws {
        for preference in [F.otherBLEPreference, F.classicPreference, F.serialPreference] {
            let harness = try await recordingHarness()
            harness.preferenceStore.preference = preference
            harness.useCase.defaultAdapterPreferenceDidChange()
            XCTAssertEqual(harness.recordingControl.stopReasons, [.superseded], "\(preference)")
        }
    }

    /// 記録中に既定アダプターを削除したら、接続対象が無くなった理由で停止を要求し、保存される終了理由は接続断です。
    ///
    /// 責務: 停止理由が `connectionTargetLost` の1件で、その終了理由が `connectionLost` であることを確認します(仕様 11)。
    func testDefaultAdapterRemovedStopsWithConnectionTargetLost() async throws {
        let harness = try await recordingHarness()
        harness.preferenceStore.preference = nil
        harness.useCase.defaultAdapterPreferenceDidChange()
        XCTAssertEqual(harness.recordingControl.stopReasons, [.connectionTargetLost])
        XCTAssertEqual(harness.recordingControl.stopReasons.map(\.sessionEndReason), [.connectionLost])
    }

    /// 記録中に監視そのものを止めたら、接続断として保存される理由で停止を要求します。
    ///
    /// 責務: 停止理由が `supervisionStopped` の1件で、その終了理由が `connectionLost` であることを確認します(決定 i)。
    func testSupervisionStopStopsWithConnectionLostReason() async throws {
        let harness = try await recordingHarness()
        harness.useCase.stop()
        XCTAssertEqual(harness.recordingControl.stopReasons, [.supervisionStopped])
        XCTAssertEqual(harness.recordingControl.stopReasons.map(\.sessionEndReason), [.connectionLost])
    }

    /// 停止要求で終了中になった後の記録終了は、終了理由にかかわらず抑止せず待機へ戻ります。
    ///
    /// 責務: サインアウトで終了中にした後、どの終了理由の通知でも `.standby` になることを確認します(仕様 12)。
    func testFinishAfterStopRequestReturnsToStandbyForEveryReason() async throws {
        let reasons: [ConnectionSessionEndReason] = [.accountSignedOut, .superseded, .connectionLost, .userDisconnected]
        for reason in reasons {
            let harness = try await recordingHarness()
            harness.useCase.externalAdapterUseDidBegin()
            harness.useCase.recordingDidFinish(endReason: reason)
            XCTAssertEqual(harness.useCase.state, .standby, "\(reason)")
        }
    }

    /// 記録中にリンクが切れたらリンク断、`ready` へ戻ったらリンク復帰を、この順に1件ずつ記録側へ伝えます。
    ///
    /// 責務: 再接続の手順の途中(接続中など)では伝えず、`ready` の出入りだけを伝えることを確認します(仕様 4)。
    func testLinkAvailabilityChangesWhileRecordingAreForwarded() async throws {
        let harness = try await recordingHarness()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.recordingControl.linkAvailabilityChanges, [false])
        harness.link.emit(.connecting)
        harness.link.emit(.discovering)
        XCTAssertEqual(harness.recordingControl.linkAvailabilityChanges, [false])
        harness.link.emit(.ready)
        XCTAssertEqual(harness.recordingControl.linkAvailabilityChanges, [false, true])
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
    }

    /// 記録中でない時(記録の終了後)のリンクの出入りは、記録側へ伝えません。
    ///
    /// 責務: 記録終了で待機へ戻った後のリンク断・復帰で、伝えた変化が増えないことを確認します(仕様 4)。
    func testLinkAvailabilityOutsideRecordingIsNotForwarded() async throws {
        let harness = try await recordingHarness()
        harness.useCase.recordingDidFinish(endReason: .connectionLost)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.recordingControl.linkAvailabilityChanges, [])
    }
}
