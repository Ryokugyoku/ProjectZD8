import XCTest
@testable import ProjectZD8

/// 取得を始める車両の登録状態から、車両IDと型式コードを取り出すことを検証します。
final class LiveTelemetryVehicleContextTests: XCTestCase {
    /// 登録済みなら車両IDと型式コード(未確認なら `nil`)を返し、未登録ならどちらも `nil` です。
    ///
    /// 責務: 3つの状態の2つの計算プロパティを確認します。
    func testVehicleIDAndModelCode() {
        let id = LiveTelemetryTestDefinitions.vehicleID
        let withCode = LiveTelemetryVehicleContext.registered(id, vehicleModelCode: "ZD8")
        let withoutCode = LiveTelemetryVehicleContext.registered(id, vehicleModelCode: nil)

        XCTAssertEqual(withCode.vehicleID, id)
        XCTAssertEqual(withCode.vehicleModelCode, "ZD8")
        XCTAssertEqual(withoutCode.vehicleID, id)
        XCTAssertNil(withoutCode.vehicleModelCode)
        XCTAssertNil(LiveTelemetryVehicleContext.unregistered.vehicleID)
        XCTAssertNil(LiveTelemetryVehicleContext.unregistered.vehicleModelCode)
    }
}
