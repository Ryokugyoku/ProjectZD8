import XCTest
@testable import ProjectZD8

/// アカウント削除の順序(クラウド削除の後に失効発行、その後にローカル消去)を仕様から検証します。
@MainActor
final class DeleteAccountUseCaseTests: XCTestCase {
    /// 検証用に失敗させるエラーです。
    private struct StepFailure: Error {}

    /// 成功時に失効発行がクラウド削除の後、ローカル消去の前に行われることを検証します。
    ///
    /// 責務: 他端末への失効通知が全クラウド削除の成功後に限られることを確認します。
    func testPublishRevocationHappensAfterCloudDeletionAndBeforeLocalErasure() async throws {
        let recorder = DeleteAccountUseCaseRecorder()

        try await makeUseCase(recorder).execute(userIdentifier: "user")

        let publish = try XCTUnwrap(recorder.index(of: "publish"))
        let sessions = try XCTUnwrap(recorder.index(of: "delete-cloud-driving-data"))
        let vehicles = try XCTUnwrap(recorder.index(of: "delete-vehicle-data"))
        let erase = try XCTUnwrap(recorder.index(of: "erase"))
        XCTAssertLessThan(sessions, publish)
        XCTAssertLessThan(vehicles, publish)
        XCTAssertLessThan(publish, erase)
        XCTAssertEqual(recorder.events.filter { $0.hasPrefix("publish:") }, ["publish:user"])
    }

    /// 接続セッションのクラウド削除が失敗したら失効を発行せずローカルも消さないことを検証します。
    ///
    /// 責務: クラウド削除失敗時に失効通知とローカル消去が起きないことを確認します。
    func testSessionCloudDeletionFailureDoesNotPublishRevocationNorEraseLocal() async {
        let recorder = DeleteAccountUseCaseRecorder()
        recorder.failures["delete-cloud-driving-data"] = StepFailure()

        await assertDeletionFails(recorder)

        XCTAssertNil(recorder.index(of: "publish"))
        XCTAssertNil(recorder.index(of: "erase"))
        XCTAssertNil(recorder.index(of: "remove-session"))
    }

    /// 車両のクラウド削除が失敗したら失効を発行せずローカルも消さないことを検証します。
    ///
    /// 責務: 車両クラウド削除失敗時に失効通知とローカル消去が起きないことを確認します。
    func testVehicleCloudDeletionFailureDoesNotPublishRevocationNorEraseLocal() async {
        let recorder = DeleteAccountUseCaseRecorder()
        recorder.failures["delete-vehicle-data"] = StepFailure()

        await assertDeletionFails(recorder)

        XCTAssertNil(recorder.index(of: "publish"))
        XCTAssertNil(recorder.index(of: "erase"))
        XCTAssertNil(recorder.index(of: "remove-session"))
    }

    /// 車両のクラウド削除が成功した時点で車両の端末キャッシュも消えることを検証します。
    ///
    /// 責務: 後続段階(ローカル消去)が失敗してもキャッシュが残らないことを確認します。
    func testVehicleCacheIsRemovedRightAfterVehicleCloudDeletionEvenIfLaterStepFails() async throws {
        let recorder = DeleteAccountUseCaseRecorder()
        recorder.failures["erase"] = StepFailure()

        await assertDeletionFails(recorder)

        let cloud = try XCTUnwrap(recorder.index(of: "delete-vehicle-data"))
        let cache = try XCTUnwrap(
            recorder.index(of: "remove-local-vehicle-cache"),
            "車両のクラウド削除が成功しても端末キャッシュが消されていません。"
        )
        XCTAssertLessThan(cloud, cache)
        let erase = try XCTUnwrap(recorder.index(of: "erase"))
        XCTAssertLessThan(cache, erase)
    }

    /// 車両のクラウド削除が失敗した場合は端末キャッシュを消さないことを検証します。
    ///
    /// 責務: クラウド削除が済んでいない車両の端末キャッシュを残すことを確認します。
    func testVehicleCacheIsKeptWhenVehicleCloudDeletionFails() async {
        let recorder = DeleteAccountUseCaseRecorder()
        recorder.failures["delete-vehicle-data"] = StepFailure()

        await assertDeletionFails(recorder)

        XCTAssertNil(recorder.index(of: "remove-local-vehicle-cache"))
    }

    /// 削除が失敗として投げられることを確認します。
    ///
    /// 責務: 失敗指定のあるユースケース実行がエラーを投げることを共通化します。
    /// - Parameter recorder: 失敗指定を持つ記録先。
    private func assertDeletionFails(_ recorder: DeleteAccountUseCaseRecorder) async {
        do {
            try await makeUseCase(recorder).execute(userIdentifier: "user")
            XCTFail("失敗指定の削除が成功しました。")
        } catch { XCTAssertTrue(error is StepFailure, "想定外のエラー: \(error)") }
    }

    /// 共有Fakeからユースケースを組み立てます。
    ///
    /// 責務: 1件のテストへ同一構成の依存を注入します。
    /// - Parameter recorder: 副作用の共有記録先。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(_ recorder: DeleteAccountUseCaseRecorder) -> DeleteAccountUseCase {
        DeleteAccountUseCase(
            sessionRevocation: DeleteAccountUseCaseRevocationFake(recorder: recorder),
            cloudErasers: AccountCloudDataErasers(
                sessionTransfers: DeleteAccountUseCaseTransferFake(recorder: recorder),
                vehicleDataEraser: DeleteAccountUseCaseVehicleEraserFake(recorder: recorder),
                maintenanceDataEraser: AuthenticationModelMaintenanceDataEraserFake()
            ),
            dataEraser: DeleteAccountUseCaseDataEraserFake(recorder: recorder),
            sessionStore: DeleteAccountUseCaseSessionStoreFake(recorder: recorder)
        )
    }
}
