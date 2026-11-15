import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 未登録ログ照会 `LoadUnassignedObservedVINConnectionSessionsUseCase` を検証します。
@MainActor
final class LoadUnassignedObservedVINConnectionSessionsUseCaseTests: XCTestCase {
    /// Repositoryが返した順序を変えずに返します。
    ///
    /// 責務: 開始日時順に並べ直さず、保存先の結果をそのまま返すことを確認します。
    func testReturnsRepositoryResultInSameOrder() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        let older = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 10), observedVIN: "VIN-A")
        let newer = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 20), observedVIN: "VIN-B")
        repository.unassignedResult = [older, newer]

        let result = try LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "account")

        XCTAssertEqual(result.map(\.id), [older.id, newer.id])
    }

    /// 渡したアカウント識別子で1回だけ問い合わせます。
    ///
    /// 責務: 照会引数が加工されずにRepositoryへ届くことを確認します。
    func testQueriesWithGivenAccountIdentifier() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()

        _ = try LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "account-42")

        XCTAssertEqual(repository.unassignedQueries, ["account-42"])
    }

    /// Repositoryが0件を返せば0件を返します。
    ///
    /// 責務: 空の照会結果が空のまま返ることを確認します。
    func testReturnsEmptyWhenRepositoryReturnsEmpty() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()

        let result = try LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "account")

        XCTAssertTrue(result.isEmpty)
    }

    /// Repositoryの失敗はそのまま投げ、空配列にしません。
    ///
    /// 責務: 保存先の失敗が型とcaseを保ったまま呼び出し元へ届くことを確認します。
    func testPropagatesRepositoryFailure() {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.failure = ConnectionSessionRepositoryError.unavailable
        let useCase = LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository)

        XCTAssertThrowsError(try useCase.execute(accountIdentifier: "account")) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .unavailable)
        }
    }

    /// 実GRDBでは、指定アカウントの車両未設定かつ観測VIN付きのセッションだけを返します。
    ///
    /// 責務: 車両設定済み・観測VINなし・別アカウントのセッションを含めないことを確認します。
    func testWithGRDBReturnsOnlyUnassignedObservedVINSessionsOfAccount() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let assignedVehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "JF1ZD8")
        let target = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 10), observedVIN: "JF1ZD8")
        try repository.save(target)
        try repository.save(ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 20)))
        try repository.save(ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 30),
            vehicle: assignedVehicle,
            observedVIN: "JF1ZD8"
        ))
        try repository.save(ConnectionSession(accountIdentifier: "other", startedAt: Date(timeIntervalSince1970: 40), observedVIN: "JF1ZD8"))

        let result = try LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "account")

        XCTAssertEqual(result.map(\.id), [target.id])
    }
}
