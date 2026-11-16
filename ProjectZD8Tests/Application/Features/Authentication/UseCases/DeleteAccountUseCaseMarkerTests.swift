import XCTest
@testable import ProjectZD8

/// アカウント削除の全順序と、削除済みの印の保存を仕様から検証します。
///
/// 仕様: 車両IDを控える → セッション → 車両 → 車両キャッシュ → 整備 → 印の保存 → 失効通知 → ローカル消去 → サインイン情報 → 控えの削除。
/// どこかで失敗したら、それ以降は実行しない。
@MainActor
final class DeleteAccountUseCaseMarkerTests: XCTestCase {
    /// 検証用に失敗させるエラーです。
    private struct StepFailure: Error {}

    /// 成功時の副作用の全順序です(仕様の順序そのもの)。
    private static let fullOrder = [
        "save-pending-vehicle-ids:user",
        "delete-cloud-driving-data:user",
        "delete-vehicle-data:user",
        "remove-local-vehicle-cache:user",
        "delete-maintenance-data:user",
        "mark-deleted:user",
        "publish:user",
        "erase:user",
        "remove-session:",
        "clear-pending-vehicle-ids:user"
    ]

    /// 失敗を指定できる段階です(`try?` で握りつぶす段階は含みません)。
    private static let failableSteps = [
        "delete-cloud-driving-data",
        "delete-vehicle-data",
        "delete-maintenance-data",
        "mark-deleted",
        "erase",
        "remove-session"
    ]

    /// 成功時に、副作用が仕様の順序どおりに1回ずつ起きることを検証します。
    ///
    /// 責務: 控え・クラウド削除・印・失効通知・ローカル消去・資格情報・控えの削除の順序を確認します。
    func testSuccessRunsEveryStepInSpecifiedOrder() async throws {
        let fixture = makeFixture()

        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertEqual(fixture.recorder.events, Self.fullOrder)
        XCTAssertEqual(fixture.marker.markedAccounts, ["user"])
        XCTAssertNil(fixture.store.stored["user"])
    }

    /// どの段階が失敗しても、それ以降の段階を実行しないことを検証します。
    ///
    /// 責務: 失敗段階までの履歴だけが残り、後続(特に失効通知とローカル消去)が起きず、控えが残ることを段階ごとに確認します。
    func testFailureAtAnyStepStopsEveryLaterStep() async throws {
        for step in Self.failableSteps {
            let fixture = makeFixture(cachedVehicleIDs: [VehicleID()])
            fixture.recorder.failures[step] = StepFailure()
            let failingIndex = try XCTUnwrap(Self.fullOrder.firstIndex { $0.hasPrefix(step + ":") }, step)

            do {
                try await fixture.useCase.execute(userIdentifier: "user")
                XCTFail("\(step) の失敗後も削除が成功しました。")
            } catch { XCTAssertTrue(error is StepFailure, "想定外のエラー: \(error)") }

            XCTAssertEqual(fixture.recorder.events, Array(Self.fullOrder[0...failingIndex]), step)
            XCTAssertNotNil(fixture.store.stored["user"], "\(step): 失敗後は控えを残して再試行に備えます。")
        }
    }

    /// 印の保存が失敗したら、失効通知もローカル消去もしないことを検証します。
    ///
    /// 責務: クラウド削除が済んでも印を残せなければ、他端末への通知と端末内消去へ進まないことを確認します。
    func testMarkerSaveFailureDoesNotPublishNorEraseLocal() async {
        let fixture = makeFixture()
        fixture.marker.markError = StepFailure()

        do {
            try await fixture.useCase.execute(userIdentifier: "user")
            XCTFail("印の保存に失敗したのに削除が成功しました。")
        } catch { XCTAssertTrue(error is StepFailure, "想定外のエラー: \(error)") }

        XCTAssertNil(fixture.recorder.index(of: "publish"))
        XCTAssertNil(fixture.recorder.index(of: "erase"))
        XCTAssertNil(fixture.recorder.index(of: "remove-session"))
    }

    /// 空のユーザー識別子では何も実行しないことを検証します。
    ///
    /// 責務: 入力が不正な場合に副作用が1件も起きないことを確認します。
    func testEmptyIdentifierThrowsWithoutAnySideEffect() async {
        let fixture = makeFixture()

        do {
            try await fixture.useCase.execute(userIdentifier: "")
            XCTFail("空の識別子で削除が成功しました。")
        } catch {
            XCTAssertEqual(error as? AuthenticationSessionStoreError, .unavailable)
        }

        XCTAssertTrue(fixture.recorder.events.isEmpty)
    }

    /// 検証対象と各Fakeの組です。
    private struct Fixture {
        /// 検証対象のユースケースです。
        let useCase: DeleteAccountUseCase
        /// 副作用の共有履歴です。
        let recorder: DeleteAccountUseCaseRecorder
        /// 印のFakeです。
        let marker: AccountDeletionMarkerPortFake
        /// 車両IDの控えのFakeです。
        let store: AccountDeletionVehicleIDStoreFake
    }

    /// 共有履歴へ結んだFake一式でユースケースを組み立てます。
    ///
    /// 責務: 印・控えを含む全依存を同じ記録先へ注入します。
    /// - Parameter cachedVehicleIDs: 端末キャッシュにある車両ID群。
    /// - Returns: ユースケースとFakeの組。
    private func makeFixture(cachedVehicleIDs: [VehicleID] = []) -> Fixture {
        let recorder = DeleteAccountUseCaseRecorder()
        let marker = AccountDeletionMarkerPortFake(recorder: recorder)
        let store = AccountDeletionVehicleIDStoreFake(recorder: recorder)
        let useCase = DeleteAccountUseCase(
            sessionRevocation: DeleteAccountUseCaseRevocationFake(recorder: recorder),
            cloudErasers: AccountCloudDataErasers(
                sessionTransfers: ConnectionSessionTransferRepositoryFake.recording(into: recorder),
                vehicleDataEraser: DeleteAccountUseCaseCachedVehicleEraserFake(recorder: recorder, cachedVehicleIDs: cachedVehicleIDs),
                maintenanceDataEraser: DeleteAccountUseCaseRecordingMaintenanceFake(recorder: recorder)
            ),
            dataEraser: DeleteAccountUseCaseDataEraserFake(recorder: recorder),
            sessionStore: DeleteAccountUseCaseSessionStoreFake(recorder: recorder),
            deletionMarker: marker,
            vehicleIDStore: store
        )
        return Fixture(useCase: useCase, recorder: recorder, marker: marker, store: store)
    }
}
