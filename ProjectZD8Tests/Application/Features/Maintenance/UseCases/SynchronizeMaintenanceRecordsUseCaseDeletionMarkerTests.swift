import XCTest
@testable import ProjectZD8

/// 整備記録の同期が、実行の冒頭で削除済みの印を確認することを仕様から検証します。
///
/// 仕様: 印がある、または確認に失敗した時は、端末内への置換も遠隔への保存も呼ばれない。
@MainActor
final class SynchronizeMaintenanceRecordsUseCaseDeletionMarkerTests: XCTestCase {
    /// 確認の失敗を表す検証用エラーです。
    private struct CheckFailure: Error, Equatable {}

    /// 印がある時、`accountDeleted` で止まり、端末内も遠隔も変更しないことを検証します。
    ///
    /// 責務: 両方の保存先が初期のまま変わらないことを確認します。
    func testMarkerPresentSavesNothing() async {
        let fixture = makeFixture()
        fixture.marker.deletedAccounts = ["account"]

        do {
            _ = try await fixture.useCase.execute(accountIdentifier: "account")
            XCTFail("印があるのに同期が成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionMarkerError, .accountDeleted)
        }

        assertStoresUnchanged(fixture)
    }

    /// 印の確認に失敗した時、そのエラーで止まり、何も保存しないことを検証します。
    ///
    /// 責務: 確認できない場合を「印なし」として進めないことを確認します。
    func testCheckFailureSavesNothing() async {
        let fixture = makeFixture()
        fixture.marker.isDeletedError = CheckFailure()

        do {
            _ = try await fixture.useCase.execute(accountIdentifier: "account")
            XCTFail("印の確認に失敗したのに同期が成功しました。")
        } catch {
            XCTAssertEqual(error as? CheckFailure, CheckFailure())
        }

        assertStoresUnchanged(fixture)
    }

    /// 印がなければ、双方の保存先へ統合結果が保存されることを検証します(対照)。
    ///
    /// 責務: 印なしでは端末内と遠隔の両方が統合結果になることを確認します。
    func testNoMarkerSavesMergedRecordsToBothStores() async throws {
        let fixture = makeFixture()

        _ = try await fixture.useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(Set(fixture.local.storedRecords.map(\.id)), [fixture.localRecord.id, fixture.remoteRecord.id])
        XCTAssertEqual(Set(fixture.remote.storedRecords.map(\.id)), [fixture.localRecord.id, fixture.remoteRecord.id])
    }

    /// 検証対象と各Fakeの組です。
    private struct Fixture {
        /// 検証対象のユースケースです。
        let useCase: SynchronizeMaintenanceRecordsUseCase
        /// 端末内の保存先Fakeです。
        let local: MaintenanceMarkerLocalFake
        /// 遠隔の保存先Fakeです。
        let remote: MaintenanceMarkerRemoteFake
        /// 印のFakeです。
        let marker: AccountDeletionMarkerPortFake
        /// 端末内にだけある初期の記録です。
        let localRecord: MaintenanceRecord
        /// 遠隔にだけある初期の記録です。
        let remoteRecord: MaintenanceRecord
    }

    /// 端末内と遠隔に別々の記録を持つ同期ユースケースを組み立てます。
    ///
    /// 責務: 印のFakeを `AccountDeletionMarkerGate` 経由で確認処理として注入します。
    /// - Returns: ユースケースとFakeの組。
    private func makeFixture() -> Fixture {
        let localRecord = MaintenanceRecord(vehicleID: VehicleID(), kind: .light, title: "Oil")
        let remoteRecord = MaintenanceRecord(vehicleID: VehicleID(), kind: .heavy, title: "Engine")
        let local = MaintenanceMarkerLocalFake(records: [localRecord])
        let remote = MaintenanceMarkerRemoteFake(records: [remoteRecord])
        let marker = AccountDeletionMarkerPortFake()
        let gate = AccountDeletionMarkerGate(marker: marker)
        let useCase = SynchronizeMaintenanceRecordsUseCase(
            localRepository: local,
            remoteStore: remote,
            accountDeletionCheck: { try await gate.ensureAccountNotDeleted(for: $0) }
        )
        return Fixture(useCase: useCase, local: local, remote: remote, marker: marker, localRecord: localRecord, remoteRecord: remoteRecord)
    }

    /// 両方の保存先が初期のままであることを確認します。
    ///
    /// 責務: 同期が1件も保存しなかったことの検証を共通化します。
    /// - Parameter fixture: 検証対象の組。
    private func assertStoresUnchanged(_ fixture: Fixture) {
        XCTAssertEqual(fixture.local.storedRecords.map(\.id), [fixture.localRecord.id])
        XCTAssertEqual(fixture.remote.storedRecords.map(\.id), [fixture.remoteRecord.id])
    }
}

/// 端末内の整備保存先のFakeです。契約が非隔離のため、テストの単一スレッド利用を前提に隔離なしで保持します。
nonisolated final class MaintenanceMarkerLocalFake: MaintenanceRecordRepository, @unchecked Sendable {
    /// 現在保持する整備記録です。
    nonisolated(unsafe) var storedRecords: [MaintenanceRecord]

    /// 初期の記録を保持します。
    ///
    /// 責務: 端末内の初期集合を固定します。
    /// - Parameter records: 初期整備記録集合。
    init(records: [MaintenanceRecord]) { storedRecords = records }

    /// 保持する記録を返します。
    ///
    /// 責務: 現在の端末内集合を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 現在の記録集合。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord] { storedRecords }

    /// 1件をupsertします。
    ///
    /// 責務: 保存要求を集合へ反映します。
    /// - Parameters:
    ///   - record: 保存する記録。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws {
        storedRecords.removeAll { $0.id == record.id }
        storedRecords.append(record)
    }

    /// 集合を置き換えます。
    ///
    /// 責務: 同期結果を端末内集合へそのまま保存します。
    /// - Parameters:
    ///   - records: 置き換える記録集合。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        storedRecords = records
    }
}

/// 遠隔の整備保存先のFakeです。
@MainActor
final class MaintenanceMarkerRemoteFake: MaintenanceRemoteStore {
    /// 現在保持する遠隔記録です。
    var storedRecords: [MaintenanceRecord]

    /// 初期の記録を保持します。
    ///
    /// 責務: 遠隔の初期集合を固定します。
    /// - Parameter records: 初期整備記録集合。
    init(records: [MaintenanceRecord]) { storedRecords = records }

    /// 保持する記録を返します。
    ///
    /// 責務: 現在の遠隔集合を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 現在の記録集合。
    func fetchRecords(for accountIdentifier: String) async throws -> [MaintenanceRecord] { storedRecords }

    /// 集合を置き換えます。
    ///
    /// 責務: 同期結果を遠隔集合へそのまま保存します。
    /// - Parameters:
    ///   - records: 置き換える記録集合。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func saveRecords(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        storedRecords = records
    }
}
