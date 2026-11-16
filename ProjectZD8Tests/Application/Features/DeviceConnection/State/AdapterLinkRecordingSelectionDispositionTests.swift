import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingSelectionDisposition` の判定結果が、扱い方と捨てる理由を区別できることを検証します。
final class AdapterLinkRecordingSelectionDispositionTests: XCTestCase {
    /// 3つの扱い方は互いに等しくなく、捨てる場合は理由ごとに区別されます。
    ///
    /// 責務: 理由の違う `.reject` を同じ結果として扱わないことを確認します(U4 受け入れ条件 7)。
    func testDispositionsAreDistinguishable() {
        let reasons = AdapterLinkRecordingStartFailureReason.allCases
        let all: [AdapterLinkRecordingSelectionDisposition] = [.forwardToTransition, .keepAsIntent] + reasons.map { .reject($0) }
        for (index, lhs) in all.enumerated() {
            for (otherIndex, rhs) in all.enumerated() {
                XCTAssertEqual(lhs == rhs, index == otherIndex, "\(lhs) / \(rhs)")
            }
        }
    }
}
