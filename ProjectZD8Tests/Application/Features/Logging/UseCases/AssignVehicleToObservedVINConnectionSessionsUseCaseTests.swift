import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 観測VINによる車両紐付け `AssignVehicleToObservedVINConnectionSessionsUseCase` を検証します。
@MainActor
final class AssignVehicleToObservedVINConnectionSessionsUseCaseTests: XCTestCase {
    /// 紐付ける登録車両です。VINの前後に空白を持ちます。
    private let vehicle = VehicleProfile(
        id: VehicleID(rawValue: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!),
        vin: "  JF1ZD8ABC12345678\n",
        name: "BRZ"
    )
    /// 履歴更新の通知回数です。
    private var historyChangeCount = 0

    /// 前後の空白を除いたVINと車両スナップショットとアカウントでRepositoryを呼び、更新件数を返します。
    ///
    /// 責務: Repositoryへ渡す3つの引数と戻り値の受け渡しを確認します。
    func testCallsRepositoryWithTrimmedVINAndVehicleSnapshotAndReturnsCount() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 3

        let count = try makeUseCase(repository).execute(vehicle: vehicle, accountIdentifier: "account")

        XCTAssertEqual(count, 3)
        XCTAssertEqual(repository.assignCalls, [.init(
            vehicle: ConnectionSessionVehicle(profile: vehicle),
            observedVIN: "JF1ZD8ABC12345678",
            accountIdentifier: "account"
        )])
    }

    /// 1件紐付けたら履歴更新を1回通知します。
    ///
    /// 責務: 更新件数の下限1で通知が1回だけ行われることを確認します。
    func testNotifiesHistoryOnceWhenOneSessionAssigned() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 1

        _ = try makeUseCase(repository).execute(vehicle: vehicle, accountIdentifier: "account")

        XCTAssertEqual(historyChangeCount, 1)
    }

    /// 複数件紐付けても履歴更新の通知は1回です。
    ///
    /// 責務: 通知回数が更新件数に比例しないことを確認します。
    func testNotifiesHistoryOnceWhenManySessionsAssigned() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 5

        _ = try makeUseCase(repository).execute(vehicle: vehicle, accountIdentifier: "account")

        XCTAssertEqual(historyChangeCount, 1)
    }

    /// 0件なら0を返し、通知しません。
    ///
    /// 責務: 一致なしの境界で履歴更新を通知しないことを確認します。
    func testDoesNotNotifyWhenNothingAssigned() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 0

        let count = try makeUseCase(repository).execute(vehicle: vehicle, accountIdentifier: "account")

        XCTAssertEqual(count, 0)
        XCTAssertEqual(repository.assignCalls.count, 1)
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// 車両のVINが空ならRepositoryを呼ばず0を返し、通知しません。
    ///
    /// 責務: 空VINで全未紐付けセッションへ車両を設定しないことを確認します。
    func testEmptyVINSkipsRepository() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 7

        let count = try makeUseCase(repository).execute(vehicle: profile(vin: ""), accountIdentifier: "account")

        XCTAssertEqual(count, 0)
        XCTAssertTrue(repository.assignCalls.isEmpty)
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// 車両のVINが空白・改行だけならRepositoryを呼ばず0を返し、通知しません。
    ///
    /// 責務: 空白だけのVINを空VINと同じく扱うことを確認します。
    func testWhitespaceOnlyVINSkipsRepository() throws {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.assignResult = 7

        let count = try makeUseCase(repository).execute(vehicle: profile(vin: " \t\n "), accountIdentifier: "account")

        XCTAssertEqual(count, 0)
        XCTAssertTrue(repository.assignCalls.isEmpty)
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// Repositoryの失敗はそのまま投げ、通知しません。
    ///
    /// 責務: 保存先の失敗が型とcaseを保って届き、履歴更新が起きないことを確認します。
    func testPropagatesRepositoryFailureWithoutNotifying() {
        let repository = ObservedVINConnectionSessionRepositorySpy()
        repository.failure = ConnectionSessionRepositoryError.unavailable
        let useCase = makeUseCase(repository)

        XCTAssertThrowsError(try useCase.execute(vehicle: vehicle, accountIdentifier: "account")) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .unavailable)
        }
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// 実GRDBでは、大文字小文字違いのVINの未紐付けセッションだけが紐付き、他は変わりません。
    ///
    /// 責務: 別VIN・別アカウント・車両設定済みのセッションを変えずに、一致する1件だけへ車両を設定することを確認します。
    func testWithGRDBAssignsCaseInsensitiveMatchOnly() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let previous = ConnectionSessionVehicle(id: VehicleID(), name: "86", displayIdentifier: "ZN8")
        let match = try seed(repository, account: "account", vin: "jf1zd8abc12345678")
        let otherVIN = try seed(repository, account: "account", vin: "JF1ZD8XYZ87654321")
        let otherAccount = try seed(repository, account: "other", vin: "JF1ZD8ABC12345678")
        let assigned = try seed(repository, account: "account", vin: "JF1ZD8ABC12345678", vehicle: previous)

        let count = try makeUseCase(repository).execute(vehicle: vehicle, accountIdentifier: "account")

        XCTAssertEqual(count, 1)
        XCTAssertEqual(historyChangeCount, 1)
        XCTAssertEqual(try reload(repository, match).vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(try reload(repository, match).observedVIN, "jf1zd8abc12345678")
        XCTAssertNil(try reload(repository, otherVIN).vehicle)
        XCTAssertNil(try reload(repository, otherAccount).vehicle)
        XCTAssertEqual(try reload(repository, assigned).vehicle, previous)
    }

    // MARK: - Helpers

    /// 通知回数を数える検証対象を組み立てます。
    ///
    /// 責務: 指定Repositoryと通知回数の記録先を1つのユースケースへ結び付けます。
    /// - Parameter repository: 観測VIN付きセッションの更新先。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(_ repository: any ObservedVINConnectionSessionRepository) -> AssignVehicleToObservedVINConnectionSessionsUseCase {
        AssignVehicleToObservedVINConnectionSessionsUseCase(repository: repository) { [weak self] in
            self?.historyChangeCount += 1
        }
    }

    /// 指定VINの登録車両を返します。
    ///
    /// 責務: VINだけを変えた登録車両を作ります。
    /// - Parameter vin: 登録車両のVIN。
    /// - Returns: 固定IDの登録車両。
    private func profile(vin: String) -> VehicleProfile {
        VehicleProfile(id: vehicle.id, vin: vin, name: vehicle.name)
    }

    /// 観測VIN付きセッションを保存します。
    ///
    /// 責務: アカウント・観測VIN・車両を指定した1件のセッションを実Repositoryへ保存します。
    /// - Parameters:
    ///   - repository: 保存先。
    ///   - account: 所有アカウント識別子。
    ///   - vin: 観測VIN。
    ///   - vehicle: 設定済みの車両。
    /// - Returns: 保存したセッション。
    private func seed(
        _ repository: GRDBConnectionSessionRepository,
        account: String,
        vin: String,
        vehicle: ConnectionSessionVehicle? = nil
    ) throws -> ConnectionSession {
        let session = ConnectionSession(accountIdentifier: account, startedAt: Date(timeIntervalSince1970: 100), vehicle: vehicle, observedVIN: vin)
        try repository.save(session)
        return session
    }

    /// 保存済みセッションを読み戻します。
    ///
    /// 責務: 所有アカウントの一覧からIDが一致する1件を取り出します。
    /// - Parameters:
    ///   - repository: 読取元。
    ///   - session: 読み戻すセッション。
    /// - Returns: 読み戻したセッション。
    private func reload(_ repository: GRDBConnectionSessionRepository, _ session: ConnectionSession) throws -> ConnectionSession {
        try XCTUnwrap(try repository.sessions(for: session.accountIdentifier).first { $0.id == session.id })
    }
}
