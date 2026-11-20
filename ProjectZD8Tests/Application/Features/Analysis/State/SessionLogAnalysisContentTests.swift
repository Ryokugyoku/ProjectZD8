import Foundation
import XCTest
@testable import ProjectZD8

/// 解析画面の本文種別の同値性を検証します。
@MainActor
final class SessionLogAnalysisContentTests: XCTestCase {
    /// 異なる種別は等しくありません。
    ///
    /// 責務: 関連値を持たない種別どうしが区別されることを確認します。
    func testDifferentCasesAreNotEqual() {
        XCTAssertNotEqual(SessionLogAnalysisContent.initialLoading, .failedWithoutData)
        XCTAssertNotEqual(SessionLogAnalysisContent.failedWithoutData, .empty)
        XCTAssertNotEqual(SessionLogAnalysisContent.empty, .initialLoading)
        XCTAssertNotEqual(SessionLogAnalysisContent.empty, .results(showsProgress: false))
    }

    /// 関連値が同じなら等しく、違えば等しくありません。
    ///
    /// 責務: 取得率と進捗表示の有無が同値性へ含まれることを確認します。
    func testAssociatedValuesParticipateInEquality() {
        XCTAssertEqual(SessionLogAnalysisContent.downloading(progress: 0.5), .downloading(progress: 0.5))
        XCTAssertNotEqual(SessionLogAnalysisContent.downloading(progress: 0.5), .downloading(progress: 0.6))
        XCTAssertEqual(SessionLogAnalysisContent.results(showsProgress: true), .results(showsProgress: true))
        XCTAssertNotEqual(SessionLogAnalysisContent.results(showsProgress: true), .results(showsProgress: false))
    }
}
