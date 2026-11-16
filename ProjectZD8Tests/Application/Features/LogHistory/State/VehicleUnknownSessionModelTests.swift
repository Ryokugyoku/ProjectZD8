import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleUnknownSessionModel` の照会・警告・画面の開閉・選択・紐付け・失敗の表示を、メモリ上の保存先で検証します。
///
/// 仕様: U4 受け入れ条件 11・12・14・15(紐付け後は件数が減り、0件で警告と画面が消える。失敗は空や成功に潰さない)。
@MainActor
final class VehicleUnknownSessionModelTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = VehicleUnknownSessionFixture

    /// 保存先のフェイクです。
    private var repository: VehicleUnknownConnectionSessionRepositoryFake!
    /// 履歴の再読込の通知回数です。
    private var historyChangeCount = 0
    /// 候補の登録済み車両です。
    private let vehicles = [VehicleUnknownSessionFixture.vehicle, VehicleUnknownSessionFixture.otherVehicle]

    /// 責務: テストごとに保存先と通知回数を作り直します。
    override func setUp() async throws {
        try await super.setUp()
        repository = VehicleUnknownConnectionSessionRepositoryFake()
        historyChangeCount = 0
    }

    /// 責務: 保存先を片付けます。
    override func tearDown() async throws {
        repository = nil
        try await super.tearDown()
    }

    /// 検証対象を作ります。
    ///
    /// 責務: 実際の照会・紐付けのユースケースを保存先のフェイクと履歴の通知へ結び付けます。
    /// - Returns: 検証対象。
    private func makeModel() -> VehicleUnknownSessionModel {
        VehicleUnknownSessionModel(
            loadSessions: LoadVehicleUnknownConnectionSessionsUseCase(repository: repository),
            assignVehicle: AssignVehicleToVehicleUnknownConnectionSessionsUseCase(repository: repository) { [weak self] in
                self?.historyChangeCount += 1
            }
        )
    }

    /// 指定件数の車両不明ログを保存し、サインイン済みのモデルを返します。
    ///
    /// 責務: 新しい順の一覧を保存先へ置き、アカウントを伝えます。
    /// - Parameter count: 保存する件数。
    /// - Returns: モデルと保存したログ。
    private func signedInModel(sessionCount count: Int) -> (VehicleUnknownSessionModel, [ConnectionSession]) {
        let sessions = (0..<count).map { F.session(startedAt: Double(1_000 - $0 * 100)) }
        repository.sessionsByAccount[F.accountIdentifier] = sessions
        let model = makeModel()
        model.send(.accountIdentifierChanged(F.accountIdentifier))
        return (model, sessions)
    }

    /// 生成直後は警告も画面も出しません。
    ///
    /// 責務: 初期の `warning` が `.hidden`、画面が非表示で、照会していないことを確認します。
    func testInitiallyHidden() {
        let model = makeModel()
        XCTAssertEqual(model.warning, .hidden)
        XCTAssertEqual(model.assignment, VehicleUnknownSessionAssignmentState())
        XCTAssertEqual(repository.loadQueries, [])
    }

    /// アカウントが決まると照会し、件数つきの警告と紐付けの候補を出します。
    ///
    /// 責務: 2件の保存で `.sessions(count: 2)`、候補が保存先の並びであることを確認します(受け入れ条件 11)。
    func testAccountChangeLoadsWarningAndCandidates() {
        let (model, sessions) = signedInModel(sessionCount: 2)
        XCTAssertEqual(repository.loadQueries, [F.accountIdentifier])
        XCTAssertEqual(model.warning, .sessions(count: 2))
        XCTAssertEqual(model.assignment.sessions, sessions)
        XCTAssertFalse(model.assignment.isPresented)
    }

    /// 車両不明ログが無ければ警告を出しません。
    ///
    /// 責務: 0件で `.hidden` であることを確認します(受け入れ条件 11 の境界)。
    func testNoSessionsHidesWarning() {
        let (model, _) = signedInModel(sessionCount: 0)
        XCTAssertEqual(model.warning, .hidden)
    }

    /// サインアウト(アカウントなし)では照会せず、警告と画面を消します。
    ///
    /// 責務: 件数ありの後の `nil` で `.hidden`・画面の状態が既定に戻り、照会が増えないことを確認します。
    func testSignOutHidesWarningWithoutLoading() {
        let (model, _) = signedInModel(sessionCount: 1)
        model.send(.warningActionSelected(.reviewSessions))

        model.send(.accountIdentifierChanged(nil))

        XCTAssertEqual(model.warning, .hidden)
        XCTAssertEqual(model.assignment, VehicleUnknownSessionAssignmentState())
        XCTAssertEqual(repository.loadQueries.count, 1)
    }

    /// 照会の失敗は空にせず、再読み込みを促す警告にし、再読み込みの成功で件数の警告へ戻ります。
    ///
    /// 責務: 失敗で `.loadFailed`、主要操作の再読み込みで `.sessions(count: 1)` になることを確認します(受け入れ条件 15)。
    func testLoadFailureShowsFailureAndRetryRecovers() {
        repository.sessionsByAccount[F.accountIdentifier] = [F.session(startedAt: 100)]
        repository.loadFailure = VehicleUnknownSessionTestError.storageFailed
        let model = makeModel()
        model.send(.accountIdentifierChanged(F.accountIdentifier))
        XCTAssertEqual(model.warning, .loadFailed)

        repository.loadFailure = nil
        model.send(.warningActionSelected(.retryLoading))

        XCTAssertEqual(model.warning, .sessions(count: 1))
        XCTAssertEqual(repository.loadQueries.count, 2)
    }

    /// 再読込の要求で照会し直し、保存先の変化を警告へ反映します。
    ///
    /// 責務: 1件から3件へ増えた保存先を `.refreshRequested` で読み直すと `.sessions(count: 3)` になることを確認します。
    func testRefreshReloads() {
        let (model, _) = signedInModel(sessionCount: 1)
        repository.sessionsByAccount[F.accountIdentifier] = (0..<3).map { F.session(startedAt: Double($0)) }

        model.send(.refreshRequested)

        XCTAssertEqual(model.warning, .sessions(count: 3))
    }

    /// 警告の主要操作で紐付けの画面を開き、閉じると選択を消して候補だけ残します。
    ///
    /// 責務: `.reviewSessions` で表示、`.assignmentDismissed` で非表示・選択なし・候補はそのままであることを確認します(受け入れ条件 12)。
    func testReviewOpensAndDismissClearsSelection() {
        let (model, sessions) = signedInModel(sessionCount: 2)
        model.send(.warningActionSelected(.reviewSessions))
        XCTAssertTrue(model.assignment.isPresented)
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.vehicleSelected(F.vehicle.id))

        model.send(.assignmentDismissed)

        XCTAssertFalse(model.assignment.isPresented)
        XCTAssertEqual(model.assignment.selectedSessionIDs, [])
        XCTAssertNil(model.assignment.selectedVehicleID)
        XCTAssertEqual(model.assignment.sessions, sessions)
    }

    /// ログの選択は候補のログだけを切り替え、同じログを2回選ぶと外れます。
    ///
    /// 責務: 候補の選択・解除と、候補に無いIDの無視を確認します(受け入れ条件 12・13)。
    func testSelectionToggleOnlyForCandidates() {
        let (model, sessions) = signedInModel(sessionCount: 2)
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.sessionSelectionToggled(sessions[1].id))
        XCTAssertEqual(model.assignment.selectedSessionIDs, Set(sessions.map(\.id)))

        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.sessionSelectionToggled(ConnectionSessionID()))

        XCTAssertEqual(model.assignment.selectedSessionIDs, [sessions[1].id])
    }

    /// 選んだログ(複数可)を選んだ車両へ紐付け、警告の件数が減り、履歴の再読込を通知します。
    ///
    /// 責務: 3件のうち2件を紐付けると、保存先へ選んだ2件・選んだ車両で依頼し、警告が1件・選択なし・通知1回になることを確認します(受け入れ条件 12・14)。
    func testAssignSelectedSessionsReducesCount() throws {
        let (model, sessions) = signedInModel(sessionCount: 3)
        model.send(.warningActionSelected(.reviewSessions))
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.sessionSelectionToggled(sessions[2].id))
        model.send(.vehicleSelected(F.vehicle.id))

        model.send(.assignRequested(vehicles: vehicles))

        let call = try XCTUnwrap(repository.assignCalls.first)
        XCTAssertEqual(repository.assignCalls.count, 1)
        XCTAssertEqual(call.vehicle, ConnectionSessionVehicle(profile: F.vehicle))
        XCTAssertEqual(Set(call.sessionIDs), [sessions[0].id, sessions[2].id])
        XCTAssertEqual(call.accountIdentifier, F.accountIdentifier)
        XCTAssertEqual(model.warning, .sessions(count: 1))
        XCTAssertEqual(model.assignment.sessions, [sessions[1]])
        XCTAssertEqual(model.assignment.selectedSessionIDs, [])
        XCTAssertTrue(model.assignment.isPresented)
        XCTAssertEqual(historyChangeCount, 1)
    }

    /// 最後のログを紐付けて0件になったら、警告と紐付けの画面が消えます。
    ///
    /// 責務: 1件を紐付けた後に `.hidden`・画面が非表示になることを確認します(受け入れ条件 12)。
    func testAssigningLastSessionHidesWarningAndClosesScreen() {
        let (model, sessions) = signedInModel(sessionCount: 1)
        model.send(.warningActionSelected(.reviewSessions))
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.vehicleSelected(F.otherVehicle.id))

        model.send(.assignRequested(vehicles: vehicles))

        XCTAssertEqual(model.warning, .hidden)
        XCTAssertFalse(model.assignment.isPresented)
        XCTAssertEqual(model.assignment.sessions, [])
    }

    /// ログか車両を選んでいない時、または選んだ車両が候補に無い時は、紐付けを依頼しません。
    ///
    /// 責務: 3つの不足のどれでも保存先が呼ばれず、警告の件数が変わらないことを確認します(受け入れ条件 12)。
    func testAssignWithIncompleteSelectionDoesNothing() {
        let (model, sessions) = signedInModel(sessionCount: 1)
        model.send(.vehicleSelected(F.vehicle.id))
        model.send(.assignRequested(vehicles: vehicles))

        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.assignRequested(vehicles: [F.otherVehicle]))

        let noVehicle = makeModel()
        noVehicle.send(.accountIdentifierChanged(F.accountIdentifier))
        noVehicle.send(.sessionSelectionToggled(sessions[0].id))
        noVehicle.send(.assignRequested(vehicles: vehicles))

        XCTAssertEqual(repository.assignCalls, [])
        XCTAssertEqual(model.warning, .sessions(count: 1))
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// 紐付けの失敗は成功に潰さず、失敗の文言を示し、選択と件数を保ちます。選択を変えると失敗の表示は消えます。
    ///
    /// 責務: 失敗で `failureKey` が設定・選択と警告が保たれ・通知0回、車両を選び直すと `failureKey` が `nil` になることを確認します(受け入れ条件 15)。
    func testAssignFailureShowsFailureAndKeepsSelection() {
        let (model, sessions) = signedInModel(sessionCount: 2)
        model.send(.warningActionSelected(.reviewSessions))
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.vehicleSelected(F.vehicle.id))
        repository.assignFailure = VehicleUnknownSessionTestError.storageFailed

        model.send(.assignRequested(vehicles: vehicles))

        XCTAssertEqual(model.assignment.failureKey, "vehicle_unknown.assignment.failure")
        XCTAssertEqual(model.assignment.selectedSessionIDs, [sessions[0].id])
        XCTAssertTrue(model.assignment.isPresented)
        XCTAssertEqual(model.warning, .sessions(count: 2))
        XCTAssertEqual(historyChangeCount, 0)

        model.send(.vehicleSelected(F.otherVehicle.id))
        XCTAssertNil(model.assignment.failureKey)
    }

    /// 再読込で候補から消えたログ(別の経路で紐付いた等)は、選択から外れます。
    ///
    /// 責務: 選んでいた2件のうち1件が保存先から消えた後の再読込で、選択が残りの1件だけになることを確認します。
    func testReloadDropsSelectionOfVanishedSessions() {
        let (model, sessions) = signedInModel(sessionCount: 2)
        model.send(.sessionSelectionToggled(sessions[0].id))
        model.send(.sessionSelectionToggled(sessions[1].id))
        repository.sessionsByAccount[F.accountIdentifier] = [sessions[1]]

        model.send(.refreshRequested)

        XCTAssertEqual(model.assignment.selectedSessionIDs, [sessions[1].id])
        XCTAssertEqual(model.warning, .sessions(count: 1))
    }
}
