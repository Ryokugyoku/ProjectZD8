import XCTest
@testable import ProjectZD8

/// アカウント削除が、控えた車両IDと端末キャッシュの車両IDを合わせてローカル消去へ渡すことを仕様から検証します。
///
/// 仕様: 控えと今のキャッシュを重複なく合わせて保存し、`eraseAllData(for:knownVehicleIDs:)` へ渡す。
/// 失敗して控えが残れば、再試行でキャッシュが空でも控えのIDを渡す。成功したら控えを消す。
@MainActor
final class DeleteAccountUseCaseVehicleIDTests: XCTestCase {
    /// 検証用に失敗させるエラーです。
    private struct StepFailure: Error {}

    /// 控えとキャッシュを重複なく合わせて、保存とローカル消去の両方へ渡すことを検証します。
    ///
    /// 責務: 控え [A, B] とキャッシュ [B, C] から A・B・C が1回ずつ保存され、消去へ渡ることを確認します。
    func testPendingAndCachedIDsAreMergedWithoutDuplicates() async throws {
        let (a, b, c) = (VehicleID(), VehicleID(), VehicleID())
        let fixture = makeFixture(pending: [a, b], cached: [b, c])

        try await fixture.useCase.execute(userIdentifier: "user")

        let saved = try XCTUnwrap(fixture.store.saveCalls.first?.ids)
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(Set(saved), [a, b, c])
        let passed = try XCTUnwrap(fixture.eraser.receivedVehicleIDs.first)
        XCTAssertEqual(passed.count, 3)
        XCTAssertEqual(Set(passed), [a, b, c])
        XCTAssertEqual(fixture.eraser.receivedVehicleIDs.count, 1)
        XCTAssertEqual(fixture.eraser.plainEraseCount, 0)
    }

    /// 控えが無く、キャッシュに重複があっても、重複なく渡すことを検証します。
    ///
    /// 責務: キャッシュ内の重複が1件へ畳まれることを確認します。
    func testDuplicatesWithinCacheAreCollapsed() async throws {
        let a = VehicleID()
        let fixture = makeFixture(pending: [], cached: [a, a])

        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertEqual(fixture.eraser.receivedVehicleIDs, [[a]])
    }

    /// 控えもキャッシュも空なら、空の車両IDを渡すことを検証します。
    ///
    /// 責務: 車両が1台も無いアカウントでも消去が呼ばれ、空配列が渡ることを確認します。
    func testEmptyPendingAndCacheErasesWithEmptyIDs() async throws {
        let fixture = makeFixture(pending: [], cached: [])

        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertEqual(fixture.eraser.receivedVehicleIDs, [[]])
    }

    /// 整備削除などで失敗して控えが残った後、再試行でキャッシュが空でも控えのIDを渡すことを検証します。
    ///
    /// 責務: 1回目の失敗で控えが残り、2回目がキャッシュ空でも控えのIDでローカル消去することを確認します。
    func testRetryAfterFailureUsesPersistedIDsEvenWhenCacheIsEmpty() async throws {
        let a = VehicleID()
        let fixture = makeFixture(pending: [], cached: [a])
        fixture.recorder.failures["delete-maintenance-data"] = StepFailure()

        do {
            try await fixture.useCase.execute(userIdentifier: "user")
            XCTFail("整備削除の失敗後も削除が成功しました。")
        } catch { XCTAssertTrue(error is StepFailure, "想定外のエラー: \(error)") }
        XCTAssertEqual(fixture.store.stored["user"], [a])
        XCTAssertTrue(fixture.eraser.receivedVehicleIDs.isEmpty)

        fixture.recorder.failures = [:]
        fixture.vehicles.cachedVehicleIDs = []
        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertEqual(fixture.eraser.receivedVehicleIDs, [[a]])
    }

    /// 成功したら控えを消すことを検証します。
    ///
    /// 責務: 削除の成功後に、そのアカウントの控えが残らないことを確認します。
    func testSuccessClearsPersistedIDs() async throws {
        let fixture = makeFixture(pending: [VehicleID()], cached: [VehicleID()])

        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertNil(fixture.store.stored["user"])
    }

    /// 他アカウントの控えを合わせず、消さないことを検証します。
    ///
    /// 責務: アカウントごとに控えが分離されていることを確認します。
    func testOtherAccountPendingIDsAreNeitherMergedNorCleared() async throws {
        let (mine, theirs) = (VehicleID(), VehicleID())
        let fixture = makeFixture(pending: [mine], cached: [], otherPending: [theirs])

        try await fixture.useCase.execute(userIdentifier: "user")

        XCTAssertEqual(fixture.eraser.receivedVehicleIDs, [[mine]])
        XCTAssertEqual(fixture.store.stored["other"], [theirs])
    }

    /// 検証対象と各Fakeの組です。
    private struct Fixture {
        /// 検証対象のユースケースです。
        let useCase: DeleteAccountUseCase
        /// 副作用の共有履歴です。
        let recorder: DeleteAccountUseCaseRecorder
        /// 車両IDの控えのFakeです。
        let store: AccountDeletionVehicleIDStoreFake
        /// 端末キャッシュを持つ車両削除Fakeです。
        let vehicles: DeleteAccountUseCaseCachedVehicleEraserFake
        /// 渡された車両IDを記録するデータ消去Fakeです。
        let eraser: DeleteAccountUseCaseKnownIDsDataEraserFake
    }

    /// 控えとキャッシュを指定してユースケースを組み立てます。
    ///
    /// 責務: 控え・キャッシュ・車両ID記録付きの消去を同じ記録先へ注入します。
    /// - Parameters:
    ///   - pending: `user` の控え。
    ///   - cached: `user` の端末キャッシュの車両ID。
    ///   - otherPending: 別アカウント `other` の控え。
    /// - Returns: ユースケースとFakeの組。
    private func makeFixture(pending: [VehicleID], cached: [VehicleID], otherPending: [VehicleID] = []) -> Fixture {
        let recorder = DeleteAccountUseCaseRecorder()
        var initial: [String: [VehicleID]] = [:]
        if !pending.isEmpty { initial["user"] = pending }
        if !otherPending.isEmpty { initial["other"] = otherPending }
        let store = AccountDeletionVehicleIDStoreFake(initial: initial)
        let vehicles = DeleteAccountUseCaseCachedVehicleEraserFake(recorder: recorder, cachedVehicleIDs: cached)
        let eraser = DeleteAccountUseCaseKnownIDsDataEraserFake(recorder: recorder)
        let useCase = DeleteAccountUseCase(
            sessionRevocation: DeleteAccountUseCaseRevocationFake(recorder: recorder),
            cloudErasers: AccountCloudDataErasers(
                sessionTransfers: DeleteAccountUseCaseTransferFake(recorder: recorder),
                vehicleDataEraser: vehicles,
                maintenanceDataEraser: DeleteAccountUseCaseRecordingMaintenanceFake(recorder: recorder)
            ),
            dataEraser: eraser,
            sessionStore: DeleteAccountUseCaseSessionStoreFake(recorder: recorder),
            deletionMarker: AccountDeletionMarkerPortFake(),
            vehicleIDStore: store
        )
        return Fixture(useCase: useCase, recorder: recorder, store: store, vehicles: vehicles, eraser: eraser)
    }
}
