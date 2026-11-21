import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationEventKind` の rawValue(DB の CHECK に固定される値)を検証します。
final class ConnectionSessionLocationEventKindTests: XCTestCase {
    /// 責務: 9個の rawValue が DB に固定された文字列であることを確かめます。
    func testRawValuesAreFixedForDatabase() {
        let expected: [(ConnectionSessionLocationEventKind, String)] = [
            (.recording, "recording"),
            (.recordingWithReducedAccuracy, "recordingWithReducedAccuracy"),
            (.disabledBySetting, "disabledBySetting"),
            (.authorizationNotDetermined, "authorizationNotDetermined"),
            (.authorizationDenied, "authorizationDenied"),
            (.authorizationRestricted, "authorizationRestricted"),
            (.backgroundWithoutAlwaysAuthorization, "backgroundWithoutAlwaysAuthorization"),
            (.locationUnavailable, "locationUnavailable"),
            (.unsupportedPlatform, "unsupportedPlatform")
        ]
        for (kind, rawValue) in expected {
            XCTAssertEqual(kind.rawValue, rawValue)
            XCTAssertEqual(ConnectionSessionLocationEventKind(rawValue: rawValue), kind)
        }
    }

    /// 責務: case が9個ちょうどで、重複がないことを確かめます。
    func testAllCasesCountAndUniqueness() {
        XCTAssertEqual(ConnectionSessionLocationEventKind.allCases.count, 9)
        XCTAssertEqual(Set(ConnectionSessionLocationEventKind.allCases.map(\.rawValue)).count, 9)
    }
}
