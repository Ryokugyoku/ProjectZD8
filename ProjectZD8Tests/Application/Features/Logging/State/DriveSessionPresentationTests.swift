import XCTest
@testable import ProjectZD8

final class DriveSessionPresentationTests: XCTestCase {
    func testElapsedText() {
        XCTAssertEqual(DriveSessionPresentation.elapsedText(microseconds: 0), "0:00")
        XCTAssertEqual(DriveSessionPresentation.elapsedText(microseconds: 65_900_000), "1:05")
        XCTAssertEqual(DriveSessionPresentation.elapsedText(microseconds: 3_725_000_000), "1:02:05")
        XCTAssertEqual(DriveSessionPresentation.elapsedText(microseconds: -5), "0:00")
    }

    func testDistanceTextUsesLocaleRoadUnit() {
        let text = DriveSessionPresentation.distanceText(kilometers: 12.34, locale: Locale(identifier: "ja_JP"))
        XCTAssertTrue(text.contains("12.3"), text)
        XCTAssertTrue(text.contains("km"), text)
    }

    func testResponseRateText() {
        XCTAssertEqual(DriveSessionPresentation.responseRateText(0.876, locale: Locale(identifier: "en_US")), "88%")
    }

    func testFailureKeys() {
        XCTAssertEqual(DriveSessionFailure(phase: .connecting, kind: .link(.timedOut)).localizationKey, "drive.failure.link.timedOut")
        XCTAssertEqual(DriveSessionFailure(phase: .identifying, kind: .link(.vinUnavailable)).localizationKey, "drive.failure.vinMissing")
        XCTAssertEqual(DriveSessionFailure(phase: .identifying, kind: .vinMissing).localizationKey, "drive.failure.vinMissing")
        XCTAssertEqual(DriveSessionFailure(phase: .preparing, kind: .store).localizationKey, "drive.failure.store")
        XCTAssertEqual(DriveSessionPresentation.endReasonKey(.vehicleNoResponse), "drive.endReason.vehicleNoResponse")
        XCTAssertEqual(AdapterDiscoveryError.bluetoothPoweredOff.localizationKey, "device.discovery.failure.bluetoothPoweredOff")
    }
}
