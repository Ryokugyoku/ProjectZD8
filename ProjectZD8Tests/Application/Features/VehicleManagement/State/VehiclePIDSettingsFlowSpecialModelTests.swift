import Foundation
import XCTest
@testable import ProjectZD8

/// 登録車両ごとの車種専用PID型式を求める処理を検証します。
@MainActor
final class VehiclePIDSettingsFlowSpecialModelTests: XCTestCase {
    /// ZD8として扱われる登録車両です。
    private let zd8Vehicle = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "ZD8")

    /// ZD8として扱われない登録車両です。
    private let otherVehicle = VehicleProfile(vin: "WVWZZZ1JZXW000001", name: "Other")

    /// 型式「ZD8」付きの専用PIDの要求です。
    private let specialRequest = OBDPIDRequest(service: 0x21, pid: 0x02)

    /// 別の型式「ABC」付きの専用PIDの要求です。
    private let otherSpecialRequest = OBDPIDRequest(service: 0x21, pid: 0x03)

    /// 型式を持たない標準PIDの要求です。
    private let standardRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)

    /// 指定した型式を持つPID定義を生成します。
    ///
    /// 責務: 要求と型式だけを差し替えた、最小のPID定義を作ります。
    /// - Parameters:
    ///   - request: 定義のService/PID。
    ///   - modelCode: 車種専用PIDの型式。標準PIDは `nil`。
    /// - Returns: 生成した定義。
    private func definition(_ request: OBDPIDRequest, modelCode: String?) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: request.service,
            pid: request.pid,
            vehicleModelCode: modelCode,
            nameKey: "test.pid",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://pid",
            revision: 1
        )
    }

    /// 型式つき2件と標準1件の定義を持つ Repository を生成します。
    ///
    /// 責務: 型式「ZD8」「ABC」の専用PIDと標準PIDの定義を返す Repository を作ります。
    /// - Parameter failsRead: 読込を失敗させる場合は `true`。
    /// - Returns: 生成した定義 Repository。
    private func definitions(failsRead: Bool = false) -> StubOBDPIDDefinitionRepository {
        StubOBDPIDDefinitionRepository(
            definitions: [
                definition(standardRequest, modelCode: nil),
                definition(specialRequest, modelCode: "ZD8"),
                definition(otherSpecialRequest, modelCode: "ABC")
            ],
            failsRead: failsRead
        )
    }

    /// 指定車両の対応PIDを並べた Repository を生成します。
    ///
    /// 責務: 車両ごとに、与えた要求の順で対応PIDを持つ Repository を作ります。
    /// - Parameter requestsByVehicle: 車両IDごとの要求(順序つき)。
    /// - Returns: 生成した対応PID Repository。
    private func capabilities(_ requestsByVehicle: [VehicleID: [OBDPIDRequest]]) -> ScriptedVehiclePIDCapabilityRepository {
        ScriptedVehiclePIDCapabilityRepository(capabilitiesByVehicle: requestsByVehicle.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.map {
                VehiclePIDCapability(vehicleID: entry.key, request: $0, isCollectionEnabled: true, discoveredAt: Date(timeIntervalSince1970: 1))
            }
        })
    }

    /// 検証対象の処理を生成します。
    ///
    /// 責務: 与えた境界を結び付けた処理を作ります。
    /// - Parameters:
    ///   - capabilities: 対応PIDの保存先。
    ///   - definitions: 定義の参照先。
    /// - Returns: 生成した処理。
    private func flow(
        _ capabilities: (any VehiclePIDCapabilityRepository)?,
        _ definitions: (any OBDPIDDefinitionRepository)?
    ) -> VehiclePIDSettingsFlow {
        VehiclePIDSettingsFlow(pidCapabilityRepository: capabilities, pidDefinitionRepository: definitions)
    }

    /// 専用PIDを持つZD8車両だけが、型式つきで返されます。
    ///
    /// 責務: ZD8の車両は型式が返り、ZD8でない車両は専用PIDを持っていても含まれないことを確認します。
    func testReturnsModelCodeOnlyForZD8Vehicles() {
        let repository = capabilities([zd8Vehicle.id: [specialRequest], otherVehicle.id: [specialRequest]])
        let result = flow(repository, definitions()).specialModelCodes(for: [zd8Vehicle, otherVehicle])
        XCTAssertEqual(result, [zd8Vehicle.id: "ZD8"])
    }

    /// 標準PIDしか持たないZD8車両や、対応PIDが無いZD8車両は、含まれません。
    ///
    /// 責務: 型式つきの定義に一致する対応PIDが無い場合に、その車両が結果から外れることを確認します。
    func testOmitsZD8VehicleWithoutModelCodedCapability() {
        let standardOnly = VehicleProfile(vin: "JF1ZD8A11P9000002", name: "standard")
        let none = VehicleProfile(vin: "JF1ZD8A11P9000003", name: "none")
        let repository = capabilities([standardOnly.id: [standardRequest], none.id: []])
        XCTAssertEqual(flow(repository, definitions()).specialModelCodes(for: [standardOnly, none]), [:])
    }

    /// VINが空でも、OBD識別子がZD8を示す車両は含まれます。
    ///
    /// 責務: VINでなくOBD識別子でZD8と判定される車両が、型式つきで返ることを確認します。
    func testMatchesZD8ThroughOBDIdentifier() {
        let vehicle = VehicleProfile(vin: "", obdIdentifier: "ZD8-OBD", name: "obd")
        let repository = capabilities([vehicle.id: [specialRequest]])
        XCTAssertEqual(flow(repository, definitions()).specialModelCodes(for: [vehicle]), [vehicle.id: "ZD8"])
    }

    /// 型式つきの対応PIDが複数あるときは、対応PIDの並びで最初のものの型式を返します。
    ///
    /// 責務: 複数の型式つき対応PIDのうち、先頭の型式が採用されることを確認します。
    func testUsesFirstModelCodedCapabilityInOrder() {
        let repository = capabilities([zd8Vehicle.id: [standardRequest, otherSpecialRequest, specialRequest]])
        XCTAssertEqual(flow(repository, definitions()).specialModelCodes(for: [zd8Vehicle]), [zd8Vehicle.id: "ABC"])
    }

    /// 一部の車両で対応PIDの読込に失敗しても、その車両だけを除いて結果を返します。
    ///
    /// 責務: 読込に失敗した車両が結果から外れ、ほかの車両は型式つきで残ることを確認します。
    func testSkipsVehicleWhoseCapabilityReadFails() {
        let failing = VehicleProfile(vin: "JF1ZD8A11P9000004", name: "failing")
        let repository = capabilities([zd8Vehicle.id: [specialRequest], failing.id: [specialRequest]])
        repository.failingReadVehicleIDs = [failing.id]
        XCTAssertEqual(flow(repository, definitions()).specialModelCodes(for: [failing, zd8Vehicle]), [zd8Vehicle.id: "ZD8"])
    }

    /// 車両が0台なら、`nil` でなく空の辞書を返します。
    ///
    /// 責務: 境界が使える状態で車両一覧が空のとき、空の辞書になることを確認します。
    func testReturnsEmptyDictionaryForNoVehicles() {
        XCTAssertEqual(flow(capabilities([:]), definitions()).specialModelCodes(for: []), [:])
    }

    /// 保存先・定義の参照先が無いか、定義の読込に失敗したときは `nil` を返します。
    ///
    /// 責務: 利用できない3つの場合で、結果が空辞書ではなく `nil` になることを確認します。
    func testReturnsNilWhenBoundariesUnavailable() {
        let repository = capabilities([zd8Vehicle.id: [specialRequest]])
        XCTAssertNil(flow(nil, definitions()).specialModelCodes(for: [zd8Vehicle]))
        XCTAssertNil(flow(repository, nil).specialModelCodes(for: [zd8Vehicle]))
        XCTAssertNil(flow(repository, definitions(failsRead: true)).specialModelCodes(for: [zd8Vehicle]))
    }
}
