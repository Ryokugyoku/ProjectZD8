import Foundation
import XCTest
@testable import ProjectZD8

/// OBD車両識別結果を登録済み車両と新規登録へ振り分ける規則を検証します。
@MainActor
final class IdentifyVehicleForConnectionUseCaseTests: XCTestCase {
    /// 大文字小文字だけが異なるVINを同じ登録車両として扱うことを検証します。
    ///
    /// 責務: 1件の既存VIN観測が新規登録を作らず登録済み結果になることを確認します。
    func testExecuteReturnsRegisteredVehicleForExistingVIN() async throws {
        let vehicle = VehicleProfile(vin: "JF1ZD8A10NG000001", name: "ZD8")
        let snapshot = makeSnapshot(vin: "jf1zd8a10ng000001")
        let useCase = IdentifyVehicleForConnectionUseCase(
            identification: VehicleIdentificationPortFake(snapshot: snapshot)
        )

        let outcome = try await useCase.execute(endpoint: makeEndpoint(), vehicles: [vehicle])

        XCTAssertEqual(outcome, .registered(vehicle, snapshot))
    }

    /// 未登録VINで全観測値を保持した登録確認へ進むことを検証します。
    ///
    /// 責務: 1件の未知VIN観測がフィールドを失わず新規登録候補になることを確認します。
    func testExecutePreservesAllFieldsForUnknownVIN() async throws {
        let snapshot = makeSnapshot(vin: "UNKNOWN-VIN")
        let useCase = IdentifyVehicleForConnectionUseCase(
            identification: VehicleIdentificationPortFake(snapshot: snapshot)
        )

        let outcome = try await useCase.execute(endpoint: makeEndpoint(), vehicles: [])

        XCTAssertEqual(outcome, .requiresRegistration(snapshot))
    }

    /// 非VINのOBD由来識別子で登録済み車両を照合します。
    ///
    /// 責務: VINがない車両同士をOBD由来識別子の同種比較だけで一致させることを確認します。
    func testExecuteReturnsRegisteredVehicleForExistingOBDIdentifier() async throws {
        let vehicle = VehicleProfile(vin: "", obdIdentifier: "ZD81234567", name: "ZD8")
        let snapshot = makeSnapshot(vin: nil, obdIdentifier: "zd81234567")
        let useCase = IdentifyVehicleForConnectionUseCase(
            identification: VehicleIdentificationPortFake(snapshot: snapshot)
        )

        let outcome = try await useCase.execute(endpoint: makeEndpoint(), vehicles: [vehicle])

        XCTAssertEqual(outcome, .registered(vehicle, snapshot))
    }

    /// 車両識別子未取得を登録可能な空文字へ変換しないことを検証します。
    ///
    /// 責務: VINと非VIN識別子の両方を含まない観測が明示的な失敗として拒否されることを確認します。
    func testExecuteRejectsSnapshotWithoutVehicleIdentifier() async {
        let useCase = IdentifyVehicleForConnectionUseCase(
            identification: VehicleIdentificationPortFake(snapshot: makeSnapshot(vin: nil))
        )

        do {
            _ = try await useCase.execute(endpoint: makeEndpoint(), vehicles: [])
            XCTFail("車両識別子未取得は成功してはいけません")
        } catch {
            XCTAssertEqual(error as? VehicleIdentificationError, .vinUnavailable)
        }
    }

    /// テスト用の車両識別子と取得元付き全フィールドを生成します。
    ///
    /// 責務: 指定識別子を持つ決定的なOBD識別観測を1件生成します。
    /// - Parameter vin: 観測へ設定するVIN候補。
    /// - Returns: メーカーとECU識別値を含む観測。
    private func makeSnapshot(vin: String?, obdIdentifier: String? = nil) -> VehicleIdentificationSnapshot {
        VehicleIdentificationSnapshot(
            vin: vin,
            obdIdentifier: obdIdentifier,
            fields: [
                .init(id: "manufacturer", label: "Manufacturer", value: "Example", source: "ECU A"),
                .init(id: "ecu", label: "ECU", value: "RAW-01", source: "ECU B")
            ],
            observedAt: Date(timeIntervalSince1970: 100)
        )
    }

    /// テスト用のEXシリアル終端を生成します。
    ///
    /// 責務: 全車両識別照合テストへ同一の通信非依存接続情報を提供します。
    /// - Returns: 決定的なシリアル接続終端。
    private func makeEndpoint() -> OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "OBDLink EX")
    }
}

/// 車両識別照合テストへ固定のOBD識別観測を返します。
@MainActor
private struct VehicleIdentificationPortFake: VehicleIdentificationPort {
    /// 取得結果として返す固定観測です。
    let snapshot: VehicleIdentificationSnapshot

    /// 固定観測をテスト対象へ返します。
    ///
    /// 責務: 1回の識別要求へ注入済み観測を返します。
    /// - Returns: 初期化時に保持した識別観測。
    /// - Parameter endpoint: テストでは参照しない接続終端。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        snapshot
    }
}
