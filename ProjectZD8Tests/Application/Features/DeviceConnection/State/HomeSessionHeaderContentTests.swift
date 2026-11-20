import XCTest
@testable import ProjectZD8

/// 接続中のセッション見出しの車両名・記録状態・切断操作の可否を決める規則を検証します。
@MainActor
final class HomeSessionHeaderContentTests: XCTestCase {
    private typealias Fixture = HomeScreenTestFixture

    private let vehicleID = VehicleID()

    /// 登録済み車両の表示状態を作ります。
    ///
    /// 責務: テスト対象の車両 ID を持つ受信中の表示状態を返します。
    private func registeredTelemetry(phase: LiveTelemetryState.Phase = .loaded) -> LiveTelemetryState {
        Fixture.telemetry(phase: phase, vehicle: .registered(vehicleID, vehicleModelCode: "ZD8"))
    }

    /// 車両名を引きます。
    ///
    /// 責務: 登録済みの表示状態とセッション・車両一覧から車両表示を返します。
    private func label(session: ConnectionSession? = nil, vehicles: [VehicleProfile] = []) -> HomeVehicleLabel {
        HomeSessionHeaderContent(telemetry: registeredTelemetry(), activeSession: session, vehicles: vehicles).vehicle
    }

    /// 未登録の車両は、セッションに車両名があっても未登録と表示します。
    ///
    /// 責務: `.unregistered` の分岐を確かめます。
    func testUnregisteredVehicle() {
        let telemetry = Fixture.telemetry(phase: .loaded, vehicle: .unregistered)
        let content = HomeSessionHeaderContent(telemetry: telemetry, activeSession: Fixture.session(vehicleName: "BRZ"), vehicles: [])

        XCTAssertEqual(content.vehicle, .unregistered)
    }

    /// 車両の文脈が無ければ、セッションに車両名があっても名前なしです。
    ///
    /// 責務: vehicle が nil の分岐を確かめます。
    func testMissingVehicleContextIsUnnamed() {
        let telemetry = Fixture.telemetry(phase: .loaded, vehicle: nil)
        let vehicles = [Fixture.vehicle(id: vehicleID, name: "BRZ")]
        let content = HomeSessionHeaderContent(telemetry: telemetry, activeSession: Fixture.session(vehicleName: "BRZ"), vehicles: vehicles)

        XCTAssertEqual(content.vehicle, .unnamed)
    }

    /// 車両一覧の同じ ID の名前を、セッションの車両名より優先します。
    ///
    /// 責務: 1段目(車両一覧)の優先を確かめます。
    func testVehicleListNameTakesPriority() {
        let vehicles = [Fixture.vehicle(id: VehicleID(), name: "Other"), Fixture.vehicle(id: vehicleID, name: "My BRZ")]

        XCTAssertEqual(label(session: Fixture.session(vehicleName: "Old Name"), vehicles: vehicles), .named("My BRZ"))
    }

    /// 車両一覧の名前は前後の空白と改行を除いて出します。
    ///
    /// 責務: 1段目の名前の前後の空白の除去を確かめます。
    func testVehicleListNameIsTrimmed() {
        XCTAssertEqual(label(vehicles: [Fixture.vehicle(id: vehicleID, name: "  My BRZ \n")]), .named("My BRZ"))
    }

    /// 車両一覧に同じ ID が無ければ、セッションの車両名で補います。
    ///
    /// 責務: 2段目(セッションの車両名)への移行を確かめます。
    func testFallsBackToSessionVehicleName() {
        let vehicles = [Fixture.vehicle(id: VehicleID(), name: "Other")]

        XCTAssertEqual(label(session: Fixture.session(vehicleName: " Session BRZ "), vehicles: vehicles), .named("Session BRZ"))
    }

    /// 車両一覧の名前が空白だけなら、名前なしとしてセッションの車両名へ進みます。
    ///
    /// 責務: 1段目の空白だけの名前を飛ばすことを確かめます。
    func testBlankVehicleListNameFallsBackToSession() {
        let vehicles = [Fixture.vehicle(id: vehicleID, name: " \t\n ")]

        XCTAssertEqual(label(session: Fixture.session(vehicleName: "Session BRZ"), vehicles: vehicles), .named("Session BRZ"))
    }

    /// 車両一覧の名前が空文字なら、セッションの車両名へ進みます。
    ///
    /// 責務: 1段目の空文字を飛ばすことを確かめます。
    func testEmptyVehicleListNameFallsBackToSession() {
        let vehicles = [Fixture.vehicle(id: vehicleID, name: "")]

        XCTAssertEqual(label(session: Fixture.session(vehicleName: "Session BRZ"), vehicles: vehicles), .named("Session BRZ"))
    }

    /// 車両一覧にもセッションにも使える名前が無ければ名前なしです。
    ///
    /// 責務: 3段目(名前なし)を、セッションなし・車両なし・空白だけの3通りで確かめます。
    func testUnnamedWhenNoUsableName() {
        XCTAssertEqual(label(), .unnamed)
        XCTAssertEqual(label(session: Fixture.session(vehicleName: nil)), .unnamed)
        XCTAssertEqual(label(session: Fixture.session(vehicleName: "   "), vehicles: [Fixture.vehicle(id: vehicleID, name: " ")]), .unnamed)
    }

    /// セッションが無ければ記録していない状態です。
    ///
    /// 責務: activeSession が nil の分岐を確かめます。
    func testNotRecordingWithoutSession() {
        let content = HomeSessionHeaderContent(telemetry: registeredTelemetry(), activeSession: nil, vehicles: [])

        XCTAssertEqual(content.recording, .notRecording)
    }

    /// 終了済みのセッションでは記録中と偽りません。
    ///
    /// 責務: endedAt がある分岐を確かめます。
    func testNotRecordingWithEndedSession() {
        let session = Fixture.session(endedAt: Fixture.startedAt.addingTimeInterval(60))
        let content = HomeSessionHeaderContent(telemetry: registeredTelemetry(), activeSession: session, vehicles: [])

        XCTAssertEqual(content.recording, .notRecording)
    }

    /// 進行中のセッションでは、その開始時刻から記録中です。
    ///
    /// 責務: endedAt が nil の分岐と開始時刻の受け渡しを確かめます。
    func testRecordingWithOngoingSession() {
        let content = HomeSessionHeaderContent(telemetry: registeredTelemetry(), activeSession: Fixture.session(), vehicles: [])

        XCTAssertEqual(content.recording, .recording(startedAt: Fixture.startedAt))
    }

    /// 切断中だけ切断操作を無効にします。
    ///
    /// 責務: 6フェーズについて `isDisconnectEnabled` を確かめます。
    func testDisconnectDisabledOnlyWhileStopping() {
        let phases: [LiveTelemetryState.Phase] = [.idle, .reading, .loaded, .paused, .stopping, .failed]
        for phase in phases {
            let content = HomeSessionHeaderContent(telemetry: registeredTelemetry(phase: phase), activeSession: nil, vehicles: [])

            XCTAssertEqual(content.isDisconnectEnabled, phase != .stopping, "\(phase)")
        }
    }
}
