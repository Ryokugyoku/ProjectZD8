import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLifecycleAction.observedVINVehicleRegistered` が、記録中の車両なしセッションの観測VINと
/// 登録された車両のVINが一致した時だけ、同じセッションへ車両を入れることを検証します。
@MainActor
final class ConnectionSessionLifecycleModelObservedVINVehicleRegisteredTests: XCTestCase {
    /// 観測VINです。
    private static let vin = "JF1ZD8A11P9000001"
    /// 履歴更新の通知回数です。
    private var historyChangeCount = 0
    /// セッションの保存先 spy です。
    private var repository = SavingConnectionSessionRepositorySpy()

    /// 観測VINと同じ表記のVINを持つ車両が登録されると、同じセッションへ車両が入り、保存と通知が1回ずつ行われます。
    ///
    /// 責務: 一致時の保存・メモリ反映・通知とセッションIDの維持を確認します。
    func testMatchingVehicleBindsToSameSession() throws {
        let model = observedModel()
        let session = try XCTUnwrap(model.activeSession)
        let (saves, notifications) = (repository.saved.count, historyChangeCount)
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")

        model.send(.observedVINVehicleRegistered(vehicle))

        XCTAssertEqual(model.activeSession?.id, session.id)
        XCTAssertEqual(model.activeSession?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        XCTAssertEqual(repository.saved.count, saves + 1)
        XCTAssertEqual(repository.saved.last?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(historyChangeCount, notifications + 1)
    }

    /// 大文字小文字だけが違うVINも一致として扱います。
    ///
    /// 責務: 車両VINが小文字で保存されていても一致することを確認します。
    func testCaseInsensitiveVINMatches() {
        let model = observedModel()

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: Self.vin.lowercased(), name: "BRZ")))

        XCTAssertNotNil(model.activeSession?.vehicle)
    }

    /// 車両VINの前後の空白は除いて比較します。
    ///
    /// 責務: 前後に空白・改行のある車両VINでも一致することを確認します。
    func testSurroundingWhitespaceInVehicleVINMatches() {
        let model = observedModel()

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: " \t\(Self.vin)\n ", name: "BRZ")))

        XCTAssertNotNil(model.activeSession?.vehicle)
    }

    /// VINが違う車両(1文字違い)が登録されても何もしません。
    ///
    /// 責務: 不一致では保存・通知・車両の反映が起きないことを確認します。
    func testMismatchedVINIsIgnored() {
        assertIgnored(VehicleProfile(vin: "JF1ZD8A11P9000002", name: "Other"))
    }

    /// 車両VINが空文字・空白だけなら何もしません。
    ///
    /// 責務: 正規化で空になるVINを一致として扱わないことを確認します。
    func testEmptyOrWhitespaceVehicleVINIsIgnored() {
        assertIgnored(VehicleProfile(vin: "", name: "Empty"))
        assertIgnored(VehicleProfile(vin: "   ", name: "Blank"))
    }

    /// 観測VINの無い車両なしセッションでは何もしません。
    ///
    /// 責務: 観測VINが無ければ、どのVINの車両でも関連付けないことを確認します。
    func testSessionWithoutObservedVINIsIgnored() {
        let model = startedModel()
        let (saves, notifications) = (repository.saved.count, historyChangeCount)

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: Self.vin, name: "BRZ")))

        XCTAssertNil(model.activeSession?.vehicle)
        XCTAssertEqual(repository.saved.count, saves)
        XCTAssertEqual(historyChangeCount, notifications)
    }

    /// 進行中セッションが無ければ何もしません。
    ///
    /// 責務: 終了後の登録で保存・通知が起きないことを確認します。
    func testWithoutActiveSessionDoesNothing() {
        let model = observedModel()
        model.send(.endRequested(.userDisconnected))
        let (saves, notifications) = (repository.saved.count, historyChangeCount)

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: Self.vin, name: "BRZ")))

        XCTAssertNil(model.activeSession)
        XCTAssertEqual(repository.saved.count, saves)
        XCTAssertEqual(historyChangeCount, notifications)
    }

    /// 既に車両のあるセッションの車両は置き換えません。
    ///
    /// 責務: 1台目で関連付けた後に同じVINの2台目が来ても、最初の車両が残ることを確認します。
    func testAlreadyBoundVehicleIsNotReplaced() {
        let model = observedModel()
        let first = VehicleProfile(vin: Self.vin, name: "First")
        model.send(.observedVINVehicleRegistered(first))
        let saves = repository.saved.count

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: Self.vin, name: "Second")))

        XCTAssertEqual(model.activeSession?.vehicle, ConnectionSessionVehicle(profile: first))
        XCTAssertEqual(repository.saved.count, saves)
    }

    /// 不具合の再現: 関連付けた後の距離更新と終了の保存でも、車両が消えずに残ります。
    ///
    /// 責務: 関連付けがメモリ上の現在セッションにも反映され、後続の保存が車両なしの値で上書きしないことを確認します。
    func testDistanceAndEndAfterBindingKeepVehicle() {
        let model = observedModel()
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")
        model.send(.observedVINVehicleRegistered(vehicle))

        model.send(.distanceObserved(.init(source: .odometer, kilometers: 100)))
        let afterDistance = repository.saved.last
        model.send(.endRequested(.userDisconnected))

        XCTAssertEqual(afterDistance?.startingOdometerKilometers, 100)
        XCTAssertEqual(afterDistance?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertNotNil(repository.saved.last?.endedAt)
        XCTAssertEqual(repository.saved.last?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(repository.saved.last?.observedVIN, Self.vin)
    }

    /// 保存に失敗したら、メモリ上の現在セッションは変わらず通知もしません。
    ///
    /// 責務: 保存失敗時に車両だけがメモリ上で先行しないことを確認します。
    func testSaveFailureLeavesActiveSessionUnchanged() {
        let model = observedModel()
        let before = model.activeSession
        let notifications = historyChangeCount
        repository.failsSave = true

        model.send(.observedVINVehicleRegistered(VehicleProfile(vin: Self.vin, name: "BRZ")))

        XCTAssertEqual(model.activeSession, before)
        XCTAssertNil(model.activeSession?.vehicle)
        XCTAssertEqual(historyChangeCount, notifications)
    }

    // MARK: - Helpers

    /// 車両なしの進行中セッションを1件持つモデルを返します。
    ///
    /// 責務: 保存先 spy と通知回数の記録先を結び付け、アカウントを設定して未登録の接続を始めます。
    /// - Returns: 進行中セッションを持つモデル。
    private func startedModel() -> ConnectionSessionLifecycleModel {
        repository = SavingConnectionSessionRepositorySpy()
        let model = ConnectionSessionLifecycleModel(repository: repository, historyDidChange: { [weak self] in self?.historyChangeCount += 1 })
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        model.send(.vehicleUnregistered)
        XCTAssertNotNil(model.activeSession)
        return model
    }

    /// 観測VINを記録した車両なしの進行中セッションを持つモデルを返します。
    ///
    /// 責務: 代表VINを観測VINとして記録した状態を作ります。
    /// - Returns: 観測VIN付きの進行中セッションを持つモデル。
    private func observedModel() -> ConnectionSessionLifecycleModel {
        let model = startedModel()
        model.send(.vinObserved(Self.vin))
        XCTAssertEqual(model.activeSession?.observedVIN, Self.vin)
        return model
    }

    /// 指定車両の登録通知が何も起こさないことを確認します。
    ///
    /// 責務: 保存回数・通知回数・現在セッションの車両が変わらないことをまとめて検証します。
    /// - Parameter vehicle: 登録された車両。
    private func assertIgnored(_ vehicle: VehicleProfile, file: StaticString = #filePath, line: UInt = #line) {
        let model = observedModel()
        let (saves, notifications) = (repository.saved.count, historyChangeCount)

        model.send(.observedVINVehicleRegistered(vehicle))

        XCTAssertNil(model.activeSession?.vehicle, file: file, line: line)
        XCTAssertEqual(repository.saved.count, saves, file: file, line: line)
        XCTAssertEqual(historyChangeCount, notifications, file: file, line: line)
    }
}
