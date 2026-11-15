import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLifecycleAction.vinObserved` による観測VINの記録を検証します。
@MainActor
final class ConnectionSessionLifecycleModelObservedVINTests: XCTestCase {
    /// 代表VINです。
    private static let vin = "JF1ZD8ABC12345678"
    /// 履歴更新の通知回数です。
    private var historyChangeCount = 0

    /// 車両未確定の進行中セッションへ前後の空白を除いたVINを保存し、反映し、1回通知します。
    ///
    /// 責務: 観測VINの記録が保存・メモリ反映・通知の3つを1回ずつ行うことを確認します。
    func testRecordsTrimmedVINOnUnresolvedActiveSession() throws {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        let savesBefore = repository.saved.count
        let notificationsBefore = historyChangeCount

        model.send(.vinObserved(" \t\(Self.vin) \n"))

        XCTAssertEqual(repository.saved.count, savesBefore + 1)
        XCTAssertEqual(repository.saved.last?.observedVIN, Self.vin)
        XCTAssertEqual(repository.saved.last?.id, model.activeSession?.id)
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        XCTAssertEqual(historyChangeCount, notificationsBefore + 1)
    }

    /// 進行中セッションが無ければ何もしません。
    ///
    /// 責務: 開始前の観測VINが保存も通知も起こさないことを確認します。
    func testIgnoresVINWithoutActiveSession() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = makeModel(repository)
        model.send(.accountIdentifierChanged("account"))
        let notificationsBefore = historyChangeCount

        model.send(.vinObserved(Self.vin))

        XCTAssertTrue(repository.saved.isEmpty)
        XCTAssertNil(model.activeSession)
        XCTAssertEqual(historyChangeCount, notificationsBefore)
    }

    /// 車両が確定済みなら何もしません。
    ///
    /// 責務: 車両確定後の観測VINが保存も通知も起こさないことを確認します。
    func testIgnoresVINWhenVehicleAlreadyResolved() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        model.send(.vehicleResolved(VehicleProfile(vin: "OTHER", name: "BRZ")))
        let savesBefore = repository.saved.count
        let notificationsBefore = historyChangeCount

        model.send(.vinObserved(Self.vin))

        XCTAssertEqual(repository.saved.count, savesBefore)
        XCTAssertNil(model.activeSession?.observedVIN)
        XCTAssertEqual(historyChangeCount, notificationsBefore)
    }

    /// 空のVINなら何もしません。
    ///
    /// 責務: 空文字が観測VINとして保存されないことを確認します。
    func testIgnoresEmptyVIN() {
        assertIgnored("")
    }

    /// 空白・改行だけのVINなら何もしません。
    ///
    /// 責務: 空白だけの文字列が観測VINとして保存されないことを確認します。
    func testIgnoresWhitespaceOnlyVIN() {
        assertIgnored(" \t\n ")
    }

    /// 既に同じVIN(前後の空白違いを含む)が記録済みなら何もしません。
    ///
    /// 責務: 同じ観測VINの再通知で保存と通知が重複しないことを確認します。
    func testIgnoresSameVINAlreadyRecorded() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        model.send(.vinObserved(Self.vin))
        let savesBefore = repository.saved.count
        let notificationsBefore = historyChangeCount

        model.send(.vinObserved("  \(Self.vin)  "))

        XCTAssertEqual(repository.saved.count, savesBefore)
        XCTAssertEqual(historyChangeCount, notificationsBefore)
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
    }

    /// 保存に失敗したら進行中セッションは変わらず、通知もしません。
    ///
    /// 責務: 保存失敗時にメモリ上の観測VINだけが先行しないことを確認します。
    func testSaveFailureLeavesActiveSessionUnchangedAndDoesNotNotify() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        let before = model.activeSession
        let notificationsBefore = historyChangeCount
        repository.failsSave = true

        model.send(.vinObserved(Self.vin))

        XCTAssertEqual(model.activeSession, before)
        XCTAssertNil(model.activeSession?.observedVIN)
        XCTAssertEqual(historyChangeCount, notificationsBefore)
    }

    /// その後の距離更新と終了でも観測VINは消えません。
    ///
    /// 責務: 距離保存と終了保存の両方が観測VINを保持することを確認します。
    func testDistanceAndEndKeepObservedVIN() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        model.send(.vinObserved(Self.vin))

        model.send(.distanceObserved(.init(source: .odometer, kilometers: 100)))
        let afterDistance = repository.saved.last
        model.send(.endRequested(.userDisconnected))

        XCTAssertEqual(afterDistance?.startingOdometerKilometers, 100)
        XCTAssertEqual(afterDistance?.observedVIN, Self.vin)
        XCTAssertNotNil(repository.saved.last?.endedAt)
        XCTAssertEqual(repository.saved.last?.observedVIN, Self.vin)
    }

    /// VIN記録後に車両が確定しても観測VINは残り、車両が設定されます。
    ///
    /// 責務: 車両確定が観測VINを上書き・消去しないことを確認します。
    func testVehicleResolvedAfterVINKeepsObservedVIN() {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")
        model.send(.vinObserved(Self.vin))

        model.send(.vehicleResolved(vehicle))

        XCTAssertEqual(model.activeSession?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        XCTAssertEqual(repository.saved.last?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(repository.saved.last?.observedVIN, Self.vin)
    }

    /// 実GRDBで終了したセッションを読み戻しても観測VINが残っています。
    ///
    /// 責務: 取得証跡の終了境界なしの終了保存が観測VINを保持することを確認します。
    func testEndedSessionReloadedFromGRDBKeepsObservedVIN() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let model = startedModel(repository)

        try runVINDistanceAndEnd(model)

        let reloaded = try XCTUnwrap(try repository.sessions(for: "account").first)
        XCTAssertNotNil(reloaded.endedAt)
        XCTAssertEqual(reloaded.observedVIN, Self.vin)
    }

    /// 取得証跡の終了境界を使う終了でも、実GRDBから読み戻した観測VINが残っています。
    ///
    /// 責務: 製品構成と同じ終了経路が観測VINを保持することを確認します。
    func testEndedSessionThroughAcquisitionTerminationKeepsObservedVIN() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let termination = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let model = ConnectionSessionLifecycleModel(repository: repository, acquisitionTerminationRepository: termination)
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        try runVINDistanceAndEnd(model)

        let reloaded = try XCTUnwrap(try repository.sessions(for: "account").first)
        XCTAssertNotNil(reloaded.endedAt)
        XCTAssertEqual(reloaded.observedVIN, Self.vin)
    }

    // MARK: - Helpers

    /// 通知回数を数えるモデルを組み立てます。
    ///
    /// 責務: 指定Repositoryと通知回数の記録先を1つのモデルへ結び付けます。
    /// - Parameter repository: セッションの保存先。
    /// - Returns: 未開始のモデル。
    private func makeModel(_ repository: any ConnectionSessionRepository) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(repository: repository, historyDidChange: { [weak self] in self?.historyChangeCount += 1 })
    }

    /// アカウントを設定してセッションを開始したモデルを返します。
    ///
    /// 責務: 車両未確定の進行中セッションを1件持つ状態を作ります。
    /// - Parameter repository: セッションの保存先。
    /// - Returns: 進行中セッションを持つモデル。
    private func startedModel(_ repository: any ConnectionSessionRepository) -> ConnectionSessionLifecycleModel {
        let model = makeModel(repository)
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        XCTAssertNotNil(model.activeSession)
        return model
    }

    /// 観測VIN・距離更新・終了を順に送ります。
    ///
    /// 責務: 観測VINの記録後に距離更新と終了を行い、終了済みになったことを確かめます。
    /// - Parameter model: 進行中セッションを持つモデル。
    private func runVINDistanceAndEnd(_ model: ConnectionSessionLifecycleModel) throws {
        model.send(.vinObserved(Self.vin))
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        model.send(.distanceObserved(.init(source: .odometer, kilometers: 100)))
        model.send(.endRequested(.userDisconnected))
        XCTAssertNil(model.activeSession)
    }

    /// 指定VINが何も起こさないことを確認します。
    ///
    /// 責務: 保存回数・通知回数・進行中セッションの観測VINが変わらないことをまとめて検証します。
    /// - Parameter vin: 送る観測VIN。
    private func assertIgnored(_ vin: String, file: StaticString = #filePath, line: UInt = #line) {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = startedModel(repository)
        let savesBefore = repository.saved.count
        let notificationsBefore = historyChangeCount

        model.send(.vinObserved(vin))

        XCTAssertEqual(repository.saved.count, savesBefore, file: file, line: line)
        XCTAssertEqual(historyChangeCount, notificationsBefore, file: file, line: line)
        XCTAssertNil(model.activeSession?.observedVIN, file: file, line: line)
    }
}
