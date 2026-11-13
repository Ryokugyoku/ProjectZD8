import XCTest
@testable import ProjectZD8

final class OBDPIDFormulaEvaluatorTests: XCTestCase {
    private func definition(_ pid: UInt8) throws -> OBDPIDDefinition {
        try XCTUnwrap(OBDPIDCatalog.definition(for: OBDPIDRequest(service: 0x01, pid: pid), vehicleModelCode: nil))
    }

    func testEngineSpeedFormula() throws {
        XCTAssertEqual(try OBDPIDFormulaEvaluator().evaluate(try definition(0x0C), bytes: [0x1A, 0xF8]), 1726, accuracy: 0.001)
    }

    func testInsufficientBytesThrows() throws {
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(try definition(0x0C), bytes: [0x1A])) {
            XCTAssertEqual($0 as? OBDPIDFormulaError, .insufficientBytes(required: 2, actual: 1))
        }
    }

    func testUndecodableDefinitionThrows() throws {
        let undecodable = try XCTUnwrap(OBDPIDCatalog.definitions(forVehicleModelCode: nil).first { !$0.isDecodable })
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(undecodable, bytes: [1, 2, 3, 4]))
    }

    func testZD8ModelPolicyMatchesDomesticAndOverseasPrefixes() {
        let policy = ZD8VehicleModelPolicy()
        XCTAssertTrue(policy.matches("ZD8-000001"))
        XCTAssertTrue(policy.matches(" jf1zd8abc "))
        XCTAssertFalse(policy.matches("WVWZZZ1JZXW000001"))
        XCTAssertFalse(policy.matches(nil))
        XCTAssertFalse(policy.matches(""))
    }
}
