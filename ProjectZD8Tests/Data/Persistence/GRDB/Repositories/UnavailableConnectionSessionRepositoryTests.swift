import Foundation
import XCTest
@testable import ProjectZD8

/// DB準備不可時のセッションRepositoryが、段階4で足したプロセス復帰の操作を明示的な利用不能として失敗させることを検証します。
final class UnavailableConnectionSessionRepositoryTests: XCTestCase {
    /// 中断batchの確定と中断セッションの終了は、どちらも利用不能で失敗します。
    ///
    /// 責務: プロセス復帰の2つの操作が空の成功を返さないことを確認します。
    func testInterruptedAcquisitionOperationsThrowUnavailable() {
        let repository = UnavailableConnectionSessionRepository()
        let session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1))

        XCTAssertThrowsError(try repository.sealInterruptedBatches(for: session.id, completedAt: Date(timeIntervalSince1970: 2))) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
        XCTAssertThrowsError(try repository.finishInterruptedSessionAcquisition(session, endedAt: Date(timeIntervalSince1970: 2))) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
    }
}
