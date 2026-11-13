import XCTest
@testable import ProjectZD8

/// `ArcGaugeGeometry` の割合・角度・ゾーン写像の検証。
final class ArcGaugeGeometryTests: XCTestCase {
    func testFractionMapsValueWithinRange() {
        XCTAssertEqual(ArcGaugeGeometry.fraction(value: 50, range: 0...100), 0.5)
        XCTAssertEqual(ArcGaugeGeometry.fraction(value: 10, range: 10...20), 0)
        XCTAssertEqual(ArcGaugeGeometry.fraction(value: 20, range: 10...20), 1)
    }

    func testFractionClampsOutOfRangeValues() {
        XCTAssertEqual(ArcGaugeGeometry.fraction(value: -5, range: 0...100), 0)
        XCTAssertEqual(ArcGaugeGeometry.fraction(value: 500, range: 0...100), 1)
    }

    func testFractionIsNilForMissingOrInvalidInput() {
        XCTAssertNil(ArcGaugeGeometry.fraction(value: nil, range: 0...100))
        XCTAssertNil(ArcGaugeGeometry.fraction(value: .nan, range: 0...100))
        XCTAssertNil(ArcGaugeGeometry.fraction(value: .infinity, range: 0...100))
        XCTAssertNil(ArcGaugeGeometry.fraction(value: 5, range: 5...5))
    }

    func testDegreesCoverTwoHundredSeventySweepAndClamp() {
        XCTAssertEqual(ArcGaugeGeometry.degrees(forFraction: 0), 135)
        XCTAssertEqual(ArcGaugeGeometry.degrees(forFraction: 0.5), 270)
        XCTAssertEqual(ArcGaugeGeometry.degrees(forFraction: 1), 405)
        XCTAssertEqual(ArcGaugeGeometry.degrees(forFraction: 2), 405)
        XCTAssertEqual(ArcGaugeGeometry.degrees(forFraction: -1), 135)
    }

    func testZoneFractionsClampToRangeAndRejectDisjointZones() {
        XCTAssertEqual(ArcGaugeGeometry.zoneFractions(zone: 75...100, range: 0...100), 0.75...1)
        XCTAssertEqual(ArcGaugeGeometry.zoneFractions(zone: 80...200, range: 0...100), 0.8...1)
        XCTAssertEqual(ArcGaugeGeometry.zoneFractions(zone: -50...20, range: 0...100), 0...0.2)
        XCTAssertNil(ArcGaugeGeometry.zoneFractions(zone: 150...200, range: 0...100))
        XCTAssertNil(ArcGaugeGeometry.zoneFractions(zone: nil, range: 0...100))
        XCTAssertNil(ArcGaugeGeometry.zoneFractions(zone: 10...10, range: 0...100))
    }
}
