import XCTest
@testable import ProjectZD8

final class VehicleEditDraftTests: XCTestCase {
    func testIssuesBoundaries() {
        var draft = VehicleEditDraft(vehicle: RecordsFixtures.vehicle(name: "A"))
        XCTAssertTrue(draft.issues(currentYear: 2026).isEmpty)
        draft.modelYear = 1900
        XCTAssertTrue(draft.issues(currentYear: 2026).isEmpty)
        draft.modelYear = 2027
        XCTAssertTrue(draft.issues(currentYear: 2026).isEmpty)
        draft.modelYear = 2028
        XCTAssertEqual(draft.issues(currentYear: 2026), [.modelYearInvalid])
        draft.modelYear = 1899
        XCTAssertEqual(draft.issues(currentYear: 2026), [.modelYearInvalid])
        draft.modelYear = nil
        draft.tankCapacityLiters = 0
        XCTAssertEqual(draft.issues(currentYear: 2026), [.tankCapacityInvalid])
        draft.tankCapacityLiters = 0.1
        XCTAssertTrue(draft.issues(currentYear: 2026).isEmpty)
    }

    func testToggleEnergySourceAndOptions() {
        var draft = VehicleEditDraft(vehicle: RecordsFixtures.vehicle(powertrain: .hybrid, energySources: [.gasolineRegular]))
        draft.toggleEnergySource(.electricity)
        XCTAssertEqual(draft.energySources, [.gasolineRegular, .electricity])
        draft.toggleEnergySource(.gasolineRegular)
        XCTAssertEqual(draft.energySources, [.electricity])
        XCTAssertEqual(draft.energySourceOptions.filter(\.isSelected).map(\.source), [.electricity])
    }

    func testEditingStartDoesNotDestroyStoredSources() {
        let draft = VehicleEditDraft(vehicle: RecordsFixtures.vehicle(powertrain: .combustion, energySources: [.gasoline]))
        XCTAssertEqual(draft.energySources, [.gasoline])
    }

    func testAppliedNormalizesSourcesForPowertrain() {
        var draft = VehicleEditDraft(vehicle: RecordsFixtures.vehicle(powertrain: .combustion, energySources: [.gasolineRegular]))
        draft.powertrain = .fuelCell
        let applied = draft.applied(to: RecordsFixtures.vehicle(), modifiedAt: RecordsFixtures.referenceDate)
        XCTAssertEqual(applied.energySources, [.hydrogen])
        XCTAssertEqual(applied.powertrain, .fuelCell)
    }
}
