import Foundation
import XCTest
@testable import ProjectZD8

/// `UnassignedObservedVINWarningModel` がアカウントと照会結果を警告の状態へ反映することを検証します。
@MainActor
final class UnassignedObservedVINWarningModelTests: XCTestCase {
    /// 警告に使うセッションを作ります。
    private typealias Fixture = UnassignedObservedVINSessionFixture
    /// 照会境界の spy です。
    private var repository: ObservedVINConnectionSessionRepositorySpy!

    /// 照会境界の spy につながったモデルを作ります。
    ///
    /// 責務: 照会結果を差し替えられる spy を用意し、テスト対象のモデルを組み立てます。
    /// - Parameter sessions: 照会で返すセッション。
    /// - Returns: 未サインインで始まるモデル。
    private func makeModel(sessions: [ConnectionSession] = []) -> UnassignedObservedVINWarningModel {
        repository = ObservedVINConnectionSessionRepositorySpy()
        repository.unassignedResult = sessions
        return UnassignedObservedVINWarningModel(
            loadSessions: LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository)
        )
    }

    /// 未サインインのうちは照会せず、警告を出しません。
    ///
    /// 責務: 初期状態・アカウントなしの通知・再読込要求のどれでも照会が0回で `.hidden` のままであることを確認します。
    func testSignedOutDoesNotQueryAndIsHidden() {
        let model = makeModel(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 1)])
        XCTAssertEqual(model.warning, .hidden)
        model.send(.accountIdentifierChanged(nil))
        model.send(.refreshRequested)
        XCTAssertEqual(model.warning, .hidden)
        XCTAssertTrue(repository.unassignedQueries.isEmpty)
    }

    /// サインインすると、そのアカウントで1回照会し、0件なら警告を出しません。
    ///
    /// 責務: 照会に渡ったアカウントと、空の結果が `.hidden` になることを確認します。
    func testSignInQueriesAccountAndHidesWhenEmpty() {
        let model = makeModel(sessions: [])
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertEqual(repository.unassignedQueries, ["account-a"])
        XCTAssertEqual(model.warning, .hidden)
    }

    /// 照会結果が1件以上なら件数どおりの警告を出します。
    ///
    /// 責務: 2台3件の照会結果が車両数・件数を持つ警告になることを確認します。
    func testSessionsProduceUnregisteredWarning() {
        let sessions = [
            Fixture.session(vin: Fixture.firstVIN, startedAt: 1),
            Fixture.session(vin: Fixture.secondVIN, startedAt: 2),
            Fixture.session(vin: Fixture.firstVIN, startedAt: 3)
        ]
        let model = makeModel(sessions: sessions)
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertTrue(model.warning.isVisible)
        XCTAssertEqual(model.warning.messageArguments, [2, 3])
        XCTAssertEqual(model.warning.primaryAction, .registerVehicle(vin: Fixture.firstVIN))
    }

    /// 照会が失敗したら警告なしにせず、失敗の状態にします。
    ///
    /// 責務: 照会の throw が `.hidden` ではなく `.loadFailed` になることを確認します。
    func testQueryFailureProducesLoadFailed() {
        let model = makeModel(sessions: [])
        repository.failure = ConnectionSessionRepositoryError.unavailable
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertEqual(model.warning, .loadFailed)
        XCTAssertNotEqual(model.warning, .hidden)
    }

    /// 失敗の後に再読込で成功すれば通常の状態へ戻ります。
    ///
    /// 責務: 再読込要求が同じアカウントで照会し直し、結果が警告へ反映されることを確認します。
    func testRefreshAfterFailureRecovers() {
        let model = makeModel(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 1)])
        repository.failure = ConnectionSessionRepositoryError.unavailable
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertEqual(model.warning, .loadFailed)

        repository.failure = nil
        model.send(.refreshRequested)

        XCTAssertEqual(repository.unassignedQueries, ["account-a", "account-a"])
        XCTAssertEqual(model.warning.messageArguments, [1, 1])
    }

    /// 再読込で結果が0件になれば警告を消します。
    ///
    /// 責務: 警告表示中に照会結果が空へ変わると `.hidden` になることを確認します。
    func testRefreshWithEmptyResultHidesWarning() {
        let model = makeModel(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 1)])
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertTrue(model.warning.isVisible)
        repository.unassignedResult = []
        model.send(.refreshRequested)
        XCTAssertEqual(model.warning, .hidden)
    }

    /// サインアウトすると照会せずに警告を消します。
    ///
    /// 責務: 警告表示中のアカウントなし通知で照会回数が増えず `.hidden` になり、以後の再読込でも照会しないことを確認します。
    func testSignOutClearsWarningWithoutQuery() {
        let model = makeModel(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 1)])
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertTrue(model.warning.isVisible)

        model.send(.accountIdentifierChanged(nil))
        model.send(.refreshRequested)

        XCTAssertEqual(model.warning, .hidden)
        XCTAssertEqual(repository.unassignedQueries, ["account-a"])
    }

    /// 失敗表示中にサインアウトしても警告を消します。
    ///
    /// 責務: `.loadFailed` からアカウントなしの通知で `.hidden` になることを確認します。
    func testSignOutClearsFailure() {
        let model = makeModel(sessions: [])
        repository.failure = ConnectionSessionRepositoryError.unavailable
        model.send(.accountIdentifierChanged("account-a"))
        model.send(.accountIdentifierChanged(nil))
        XCTAssertEqual(model.warning, .hidden)
    }

    /// アカウントが変わると新しいアカウントで照会し直し、以後の再読込も新しいアカウントで行います。
    ///
    /// 責務: 照会に渡ったアカウントの順と、新しい結果が警告へ反映されることを確認します。
    func testAccountChangeQueriesNewAccount() {
        let model = makeModel(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 1)])
        model.send(.accountIdentifierChanged("account-a"))
        XCTAssertTrue(model.warning.isVisible)

        repository.unassignedResult = []
        model.send(.accountIdentifierChanged("account-b"))
        model.send(.refreshRequested)

        XCTAssertEqual(repository.unassignedQueries, ["account-a", "account-b", "account-b"])
        XCTAssertEqual(model.warning, .hidden)
    }
}
