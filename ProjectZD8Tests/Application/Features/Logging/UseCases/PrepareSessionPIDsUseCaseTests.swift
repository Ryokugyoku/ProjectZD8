import XCTest
@testable import ProjectZD8

final class PrepareSessionPIDsUseCaseTests: XCTestCase {
    private typealias F = DriveFlowFixtures

    private let zd8VIN = "JF1ZD8TEST0000001"

    private func makeUseCase(_ settings: DriveFlowPIDSettingRepository) -> PrepareSessionPIDsUseCase {
        PrepareSessionPIDsUseCase(settings: settings, now: { F.epoch })
    }

    func testStandardVehicleListsSupportedPIDsInCatalogOrderWithFastGroup() async throws {
        let settings = DriveFlowPIDSettingRepository()
        let link = DriveFlowScriptedLink(supported: F.fastRequests.union([F.coolant]))
        let pids = try await makeUseCase(settings).execute(vehicle: F.vehicle(), link: link)

        XCTAssertEqual(pids.map(\.ordinal), Array(0..<5))
        XCTAssertEqual(pids.map(\.request.pid), [0x04, 0x05, 0x0C, 0x0D, 0x11])
        XCTAssertEqual(pids.filter(\.isFastGroup).map(\.request.pid), [0x04, 0x0C, 0x0D, 0x11])
        XCTAssertTrue(pids.allSatisfy { $0.isPolled && $0.support == .supported })
        XCTAssertTrue(link.queries.isEmpty, "a non-ZD8 vehicle must not probe vehicle-specific PIDs")
        let merged = settings.mergedSets
        XCTAssertEqual(merged, [F.fastRequests.union([F.coolant])])
    }

    func testSnapshotCopiesTheDefinitionRules() async throws {
        let link = DriveFlowScriptedLink(supported: [F.rpm])
        let pid = try await makeUseCase(DriveFlowPIDSettingRepository()).execute(vehicle: F.vehicle(), link: link).first
        let definition = try XCTUnwrap(OBDPIDCatalog.definition(for: F.rpm, vehicleModelCode: nil))
        XCTAssertEqual(pid?.formula, definition.formula)
        XCTAssertEqual(pid?.requiredByteCount, definition.requiredByteCount)
        XCTAssertEqual(pid?.unit, definition.unit)
        XCTAssertEqual(pid?.maximumValue, definition.maximumValue)
        XCTAssertEqual(pid?.definitionRevision, definition.revision)
    }

    func testUserDisabledPIDIsListedButNotPolled() async throws {
        let vehicle = F.vehicle()
        let settings = DriveFlowPIDSettingRepository(rows: [
            VehiclePIDSetting(vehicleID: vehicle.id, request: F.coolant, isSupported: true, isCollectionEnabled: false, discoveredAt: F.epoch)
        ])
        let link = DriveFlowScriptedLink(supported: [F.rpm, F.coolant])
        let pids = try await makeUseCase(settings).execute(vehicle: vehicle, link: link)
        let coolant = try XCTUnwrap(pids.first { $0.request == F.coolant })
        XCTAssertFalse(coolant.isCollectionEnabled)
        XCTAssertFalse(coolant.isPolled)
        XCTAssertTrue(try XCTUnwrap(pids.first { $0.request == F.rpm }).isPolled)
    }

    func testSupportedButUndecodableAndUncataloguedPIDsAreListedDisabled() async throws {
        let undecodable = try XCTUnwrap(OBDPIDCatalog.definitions(forVehicleModelCode: nil).first { !$0.isDecodable })
        let uncatalogued = OBDPIDRequest(service: 0x01, pid: 0xFE)
        XCTAssertNil(OBDPIDCatalog.definition(for: uncatalogued, vehicleModelCode: nil))
        let link = DriveFlowScriptedLink(supported: [F.rpm, undecodable.request, uncatalogued])
        let pids = try await makeUseCase(DriveFlowPIDSettingRepository()).execute(vehicle: F.vehicle(), link: link)

        let undecodablePID = try XCTUnwrap(pids.first { $0.request == undecodable.request })
        XCTAssertEqual(undecodablePID.support, .supported)
        XCTAssertFalse(undecodablePID.isCollectionEnabled)
        XCTAssertNil(undecodablePID.formula)
        let unknownPID = try XCTUnwrap(pids.first { $0.request == uncatalogued })
        XCTAssertFalse(unknownPID.isPolled)
        XCTAssertEqual(pids.last?.request, uncatalogued, "uncatalogued PIDs follow the catalogued ones")
        XCTAssertEqual(pids.map(\.ordinal), Array(0..<pids.count))
    }

    func testZD8VehicleProbesSpecificPIDsOncePerDefinitionWithHeaders() async throws {
        let link = DriveFlowScriptedLink(supported: [F.rpm], script: { request, _, _ in
            request == F.zd8Odometer ? OBDQueryResult(outcome: .responded, payload: [0, 0, 1, 0]) : OBDQueryResult(outcome: .noData)
        })
        let vehicle = F.vehicle(vin: zd8VIN)
        let settings = DriveFlowPIDSettingRepository()
        let pids = try await makeUseCase(settings).execute(vehicle: vehicle, link: link)

        XCTAssertEqual(Set(link.queries), [
            DriveFlowScriptedLink.Query(request: F.zd8Odometer, header: 0x7E0),
            DriveFlowScriptedLink.Query(request: OBDPIDRequest(service: 0x21, pid: 0x17), header: 0x7E1)
        ])
        XCTAssertEqual(link.queries.count, 2)
        let odometer = try XCTUnwrap(pids.first { $0.request == F.zd8Odometer })
        XCTAssertEqual(odometer.header, 0x7E0)
        XCTAssertTrue(odometer.isPolled)
        XCTAssertFalse(odometer.isFastGroup)
        XCTAssertNil(pids.first { $0.request.service == 0x21 && $0.request.pid == 0x17 })
        let merged = settings.mergedSets
        XCTAssertEqual(merged, [[F.rpm, F.zd8Odometer]])
    }

    func testNoPollablePIDsThrows() async throws {
        let link = DriveFlowScriptedLink(supported: [])
        do {
            _ = try await makeUseCase(DriveFlowPIDSettingRepository()).execute(vehicle: F.vehicle(), link: link)
            XCTFail("expected noPollablePIDs")
        } catch {
            XCTAssertEqual(error as? PrepareSessionPIDsUseCase.Failure, .noPollablePIDs)
        }
    }

    func testLinkErrorsPropagate() async throws {
        let link = DriveFlowScriptedLink(supported: [], script: { _, _, _ in throw OBDLinkError.connectionLost })
        do {
            _ = try await makeUseCase(DriveFlowPIDSettingRepository()).execute(vehicle: F.vehicle(vin: zd8VIN), link: link)
            XCTFail("expected connectionLost")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .connectionLost)
        }
    }
}
