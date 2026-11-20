import XCTest
@testable import ProjectZD8

/// `RouteRecordingSettingsModel` が設定の保存・2段階の許可要求・表示状態を扱うことを検証します。
@MainActor
final class RouteRecordingSettingsModelTests: XCTestCase {
    /// 走行ルート記録設定の保存先の fake です。
    private var store: RouteRecordingPreferenceStoreFake!
    /// 許可境界の fake です。
    private var authorization: LocationAuthorizationFake!
    /// `preferenceDidChange` へ通知された値です(通知順)。
    private var notifiedValues: [Bool] = []

    /// 保存値と現在の許可を指定してモデルを作ります。
    ///
    /// 責務: fake の保存先と許可境界につながり、通知を記録するモデルを組み立てます。
    /// - Parameters:
    ///   - isEnabled: 保存先の初期値。
    ///   - permission: 現在の許可。
    ///   - ignoresSave: 保存先が保存を無視する場合は `true`。
    /// - Returns: テスト対象のモデル。
    private func makeModel(
        isEnabled: Bool,
        permission: LocationPermission,
        ignoresSave: Bool = false
    ) -> RouteRecordingSettingsModel {
        store = RouteRecordingPreferenceStoreFake(isEnabled: isEnabled, ignoresSave: ignoresSave)
        authorization = LocationAuthorizationFake(currentPermission: permission)
        notifiedValues = []
        return RouteRecordingSettingsModel(
            preference: RouteRecordingPreferenceUseCase(preferencePort: store),
            authorization: authorization,
            preferenceDidChange: { self.notifiedValues.append($0) }
        )
    }

    /// 許可の変化を許可境界とモデルの両方へ伝えます。
    ///
    /// 責務: 実機と同じく現在の許可を置き換えてから、変化の操作をモデルへ送ります。
    /// - Parameters:
    ///   - permission: 新しい許可。
    ///   - model: 送り先のモデル。
    private func changePermission(_ permission: LocationPermission, on model: RouteRecordingSettingsModel) {
        authorization.currentPermission = permission
        model.send(.permissionChanged(permission))
    }

    /// 初期の表示は保存値と現在の許可から作られます。
    ///
    /// 責務: 保存オフは許可によらず off、保存オンは許可の段階に応じた状態になることを確認します。
    func testInitialSectionReflectsStoredValueAndPermission() {
        let cases: [(Bool, LocationAuthorizationLevel, RouteRecordingSettingsStatus)] = [
            (false, .always, .off),
            (false, .notDetermined, .off),
            (true, .notDetermined, .awaitingPermission),
            (true, .always, .recordsInBackground),
            (true, .whenInUse, .foregroundOnly),
            (true, .denied, .denied),
            (true, .restricted, .restricted)
        ]
        for (isEnabled, level, expected) in cases {
            let model = makeModel(isEnabled: isEnabled, permission: Self.permission(level))
            XCTAssertEqual(model.section.isEnabled, isEnabled, "\(isEnabled) \(level)")
            XCTAssertEqual(model.section.status, expected, "\(isEnabled) \(level)")
        }
        XCTAssertEqual(authorization.requests, [])
    }

    /// 未確定でオンにすると保存し、「使用中のみ」だけを1回要求して許可待ちになります。
    ///
    /// 責務: 1段目の要求だけが出て「常に許可」は保留され、保存と通知と表示が揃うことを確認します。
    func testTurningOnWhileNotDeterminedRequestsWhenInUseOnly() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.notDetermined))
        model.send(.toggled(isEnabled: true))

        XCTAssertEqual(store.savedValues, [true])
        XCTAssertEqual(authorization.requests, [.whenInUse])
        XCTAssertTrue(model.section.isEnabled)
        XCTAssertEqual(model.section.status, .awaitingPermission)
        XCTAssertEqual(notifiedValues, [true])
    }

    /// 保留中に「使用中のみ」へ変わると「常に許可」を1回だけ要求します。
    ///
    /// 責務: 2段目の要求が1回出て前面のみの状態になり、同じ通知の繰り返しでは要求が増えないことを確認します。
    func testWhenInUseAfterPendingRequestsAlwaysOnce() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.notDetermined))
        model.send(.toggled(isEnabled: true))

        changePermission(Self.permission(.whenInUse), on: model)
        XCTAssertEqual(authorization.requests, [.whenInUse, .always])
        XCTAssertEqual(model.section.status, .foregroundOnly)

        changePermission(Self.permission(.whenInUse), on: model)
        XCTAssertEqual(authorization.requests, [.whenInUse, .always])
        XCTAssertEqual(model.section.status, .foregroundOnly)
    }

    /// 保留中に「常に許可」・拒否・制限へ変わった場合は「常に許可」を要求しません。
    ///
    /// 責務: 2段目が不要または出せない許可では要求が増えず、状態がそれぞれの段階になることを確認します。
    func testOtherPermissionsAfterPendingDoNotRequestAlways() {
        let cases: [(LocationAuthorizationLevel, RouteRecordingSettingsStatus)] = [
            (.always, .recordsInBackground),
            (.denied, .denied),
            (.restricted, .restricted)
        ]
        for (level, expected) in cases {
            let model = makeModel(isEnabled: false, permission: Self.permission(.notDetermined))
            model.send(.toggled(isEnabled: true))
            changePermission(Self.permission(level), on: model)

            XCTAssertEqual(authorization.requests, [.whenInUse], "\(level)")
            XCTAssertEqual(model.section.status, expected, "\(level)")
            XCTAssertTrue(model.section.isEnabled, "\(level)")
        }
    }

    /// 既に「使用中のみ」の状態でオンにすると「常に許可」だけを1回要求します。
    ///
    /// 責務: 1段目を飛ばして2段目の要求だけが出ることを確認します。
    func testTurningOnWhileWhenInUseRequestsAlways() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.whenInUse))
        model.send(.toggled(isEnabled: true))

        XCTAssertEqual(authorization.requests, [.always])
        XCTAssertEqual(model.section.status, .foregroundOnly)
        XCTAssertEqual(notifiedValues, [true])
    }

    /// 既に「常に許可」・拒否・制限の状態でオンにしても、どちらの要求も出しません。
    ///
    /// 責務: 要求が不要または出せない許可では要求が無く、保存と通知だけが行われることを確認します。
    func testTurningOnWithSettledPermissionRequestsNothing() {
        let cases: [(LocationAuthorizationLevel, RouteRecordingSettingsStatus)] = [
            (.always, .recordsInBackground),
            (.denied, .denied),
            (.restricted, .restricted)
        ]
        for (level, expected) in cases {
            let model = makeModel(isEnabled: false, permission: Self.permission(level))
            model.send(.toggled(isEnabled: true))

            XCTAssertEqual(authorization.requests, [], "\(level)")
            XCTAssertEqual(store.savedValues, [true], "\(level)")
            XCTAssertEqual(model.section.status, expected, "\(level)")
            XCTAssertEqual(notifiedValues, [true], "\(level)")
        }
    }

    /// オフにすると保存し、要求を出さず、off を表示して通知します。
    ///
    /// 責務: オフ操作が保存・表示・通知に反映され、許可要求が出ないことを確認します。
    func testTurningOffSavesAndRequestsNothing() {
        let model = makeModel(isEnabled: true, permission: Self.permission(.notDetermined))
        model.send(.toggled(isEnabled: false))

        XCTAssertEqual(store.savedValues, [false])
        XCTAssertEqual(authorization.requests, [])
        XCTAssertFalse(model.section.isEnabled)
        XCTAssertEqual(model.section.status, .off)
        XCTAssertEqual(notifiedValues, [false])
    }

    /// 保留中にオフへ戻すと保留が解け、その後「使用中のみ」になっても「常に許可」を要求しません。
    ///
    /// 責務: オフ操作で2段目の保留が解除されることを確認します。
    func testTurningOffClearsPendingAlwaysRequest() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.notDetermined))
        model.send(.toggled(isEnabled: true))
        model.send(.toggled(isEnabled: false))

        changePermission(Self.permission(.whenInUse), on: model)
        XCTAssertEqual(authorization.requests, [.whenInUse])
        XCTAssertEqual(model.section.status, .off)
        XCTAssertEqual(notifiedValues, [true, false])
    }

    /// 設定オフの間に許可が変わっても、要求は出さず off のままです。
    ///
    /// 責務: 各許可への変化で要求が無く、表示が off のままであることを確認します。
    func testPermissionChangesWhileOffRequestNothing() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.notDetermined))
        for level in [LocationAuthorizationLevel.whenInUse, .always, .denied, .restricted, .notDetermined] {
            changePermission(Self.permission(level), on: model)
            XCTAssertEqual(model.section.status, .off, "\(level)")
            XCTAssertFalse(model.section.isEnabled, "\(level)")
        }
        XCTAssertEqual(authorization.requests, [])
        XCTAssertEqual(store.savedValues, [])
    }

    /// 表示と通知は、保存し直した後に保存先から読み直した値に従います。
    ///
    /// 責務: 保存を無視する保存先ではオンにしても表示がオフのままで、通知も false になることを確認します。
    func testSectionUsesValueReloadedFromStore() {
        let model = makeModel(isEnabled: false, permission: Self.permission(.always), ignoresSave: true)
        model.send(.toggled(isEnabled: true))

        XCTAssertEqual(store.savedValues, [true])
        XCTAssertFalse(model.section.isEnabled)
        XCTAssertEqual(model.section.status, .off)
        XCTAssertEqual(notifiedValues, [false])
    }

    /// 正確な位置の許可状態を作ります。
    ///
    /// 責務: 許可の段階から精度ありの許可状態を返します。
    /// - Parameter level: 許可の段階。
    /// - Returns: 許可状態。
    private static func permission(_ level: LocationAuthorizationLevel) -> LocationPermission {
        LocationPermission(level: level, isPreciseAccuracy: true)
    }
}
