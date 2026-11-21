import Foundation
import XCTest
@testable import ProjectZD8

/// DB準備不可時の位置Repositoryが、すべての操作を明示的な利用不能として失敗させることを検証します。
final class UnavailableConnectionSessionLocationRepositoryTests: XCTestCase {
    /// 追記と読出しの4メソッドはすべて利用不能で失敗します。
    ///
    /// 責務: 位置・事象の追記と読出しが、成功や空配列を返さないことを確認します。
    func testAllOperationsThrowUnavailable() throws {
        let repository = UnavailableConnectionSessionLocationRepository()
        let sessionID = ConnectionSessionID()
        let fix = try XCTUnwrap(
            LocationFix(
                latitude: 35, longitude: 139, altitudeMeters: nil, horizontalAccuracyMeters: 5, verticalAccuracyMeters: nil,
                speedMetersPerSecond: nil, courseDegrees: nil, observedAt: Date(timeIntervalSince1970: 1), monotonicNanoseconds: 1
            )
        )

        assertUnavailable { try repository.appendSample(fix, for: sessionID) }
        assertUnavailable { _ = try repository.samples(for: sessionID) }
        assertUnavailable { try repository.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 2), for: sessionID) }
        assertUnavailable { _ = try repository.events(for: sessionID) }
    }

    /// 処理が利用不能で失敗することを検証します。
    ///
    /// 責務: 送出されたエラーが `ConnectionSessionRepositoryError.unavailable` であることを確認します。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 検証する処理。
    private func assertUnavailable(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable, file: file, line: line)
        }
    }
}
