#if os(iOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// iOS のホームとガレージで未登録車両の警告を出すかどうか `IOSUnassignedObservedVINWarningVisibility` を検証します。
@MainActor
final class IOSUnassignedObservedVINWarningVisibilityTests: XCTestCase {
    /// 車両管理の全段階です。
    private let allPhases: [VehicleManagementState.Phase] = [
        .idle, .loading, .identifying, .confirmingIdentification, .registering, .editing, .readyToConnect, .failed
    ]
    /// 未登録車両の警告です。
    private var unregistered: UnassignedObservedVINWarning {
        UnassignedObservedVINWarning(sessions: [UnassignedObservedVINSessionFixture.session(vin: "JF1ZD8A11P9000001", startedAt: 1)])
    }

    /// 警告なしはどの段階でも出しません。
    ///
    /// 責務: `.hidden` で全段階が偽になることを確認します。
    func testHiddenWarningIsNeverVisible() {
        for phase in allPhases {
            XCTAssertFalse(IOSUnassignedObservedVINWarningVisibility.isVisible(warning: .hidden, vehiclePhase: phase), "\(phase)")
        }
    }

    /// 一覧の段階では未登録警告と失敗の両方を出します。
    ///
    /// 責務: 識別・登録・編集の最中でない段階で、表示対象の警告が真になることを確認します。
    func testVisibleWarningsShownOutsideRegistrationFlow() {
        for phase in [VehicleManagementState.Phase.idle, .loading, .readyToConnect, .failed] {
            for warning in [unregistered, .loadFailed] {
                XCTAssertTrue(IOSUnassignedObservedVINWarningVisibility.isVisible(warning: warning, vehiclePhase: phase), "\(phase)")
            }
        }
    }

    /// 識別・確認・登録・編集の最中は重ねて出しません(型の DocC が定める契約)。
    ///
    /// 責務: 4つの段階で表示対象の警告でも偽になることを確認します。
    func testVisibleWarningsSuppressedDuringRegistrationFlow() {
        for phase in [VehicleManagementState.Phase.identifying, .confirmingIdentification, .registering, .editing] {
            for warning in [unregistered, .loadFailed] {
                XCTAssertFalse(IOSUnassignedObservedVINWarningVisibility.isVisible(warning: warning, vehiclePhase: phase), "\(phase)")
            }
        }
    }
}
#endif
