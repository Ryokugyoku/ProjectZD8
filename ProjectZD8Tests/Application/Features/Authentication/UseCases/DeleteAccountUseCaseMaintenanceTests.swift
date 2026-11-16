import XCTest
@testable import ProjectZD8

/// アカウント削除が整備のクラウドデータ(`MaintenanceCatalog`)を対象に含めることを検証します。
///
/// 仮定API: `AccountMaintenanceDataErasurePort.deleteAllMaintenanceData(for:) async throws` と、
/// `DeleteAccountUseCase.init` の `maintenanceDataEraser:` 引数(`vehicleDataEraser:` の次)。未実装のためコンパイルエラーで失敗します。
@MainActor
final class DeleteAccountUseCaseMaintenanceTests: XCTestCase {
    /// 検証用に失敗させるエラーです。
    private struct StepFailure: Error {}

    /// 整備のクラウド削除が呼ばれ、失効発行より前に行われることを検証します。
    ///
    /// 責務: 整備データが削除対象に含まれ、失効通知より先に消えることを確認します。
    func testMaintenanceCloudDataIsDeletedBeforeRevocationPublish() async throws {
        let recorder = DeleteAccountUseCaseRecorder()

        try await makeUseCase(recorder).execute(userIdentifier: "user")

        let maintenance = try XCTUnwrap(recorder.index(of: "delete-maintenance-data"))
        let publish = try XCTUnwrap(recorder.index(of: "publish"))
        XCTAssertEqual(recorder.events.filter { $0.hasPrefix("delete-maintenance-data:") }, ["delete-maintenance-data:user"])
        XCTAssertLessThan(maintenance, publish)
    }

    /// 整備のクラウド削除が失敗したら失効発行もローカル消去もしないことを検証します。
    ///
    /// 責務: 整備クラウド削除の失敗が再試行可能な状態を保つことを確認します。
    func testMaintenanceCloudDeletionFailureDoesNotPublishNorEraseLocal() async {
        let recorder = DeleteAccountUseCaseRecorder()
        recorder.failures["delete-maintenance-data"] = StepFailure()

        do {
            try await makeUseCase(recorder).execute(userIdentifier: "user")
            XCTFail("整備クラウド削除の失敗後も削除が成功しました。")
        } catch {
            XCTAssertNil(recorder.index(of: "publish"))
            XCTAssertNil(recorder.index(of: "erase"))
            XCTAssertNil(recorder.index(of: "remove-session"))
        }
    }

    /// 共有Fakeからユースケースを組み立てます。
    ///
    /// 責務: 整備削除境界を含む同一構成の依存を注入します。
    /// - Parameter recorder: 副作用の共有記録先。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(_ recorder: DeleteAccountUseCaseRecorder) -> DeleteAccountUseCase {
        DeleteAccountUseCase(
            sessionRevocation: DeleteAccountUseCaseRevocationFake(recorder: recorder),
            sessionTransfers: DeleteAccountUseCaseTransferFake(recorder: recorder),
            vehicleDataEraser: DeleteAccountUseCaseVehicleEraserFake(recorder: recorder),
            maintenanceDataEraser: DeleteAccountUseCaseMaintenanceEraserFake(recorder: recorder),
            dataEraser: DeleteAccountUseCaseDataEraserFake(recorder: recorder),
            sessionStore: DeleteAccountUseCaseSessionStoreFake(recorder: recorder)
        )
    }
}

/// アカウント削除テストで整備のクラウド削除を記録します。
@MainActor
private final class DeleteAccountUseCaseMaintenanceEraserFake: AccountMaintenanceDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 整備削除Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 整備クラウド削除を履歴へ追加します。
    ///
    /// 責務: 1件の整備クラウド削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllMaintenanceData(for accountIdentifier: String) async throws {
        try recorder.record("delete-maintenance-data:\(accountIdentifier)")
    }
}
