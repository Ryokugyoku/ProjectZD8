import Foundation
import XCTest
@testable import ProjectZD8

/// DB 準備不可時の交通規制の検索 Repository が、検索を明示的な利用不能として失敗させることを検証します。
@MainActor
final class UnavailableRoadRegulationQueryRepositoryTests: XCTestCase {
    /// 検索は、空の升目でも `unavailable` で失敗し、空の結果を返しません。
    ///
    /// 責務: 升目が空・非空のどちらでも成功や空配列にならないことを確認します。
    func testRegulationsThrowUnavailable() {
        let repository = UnavailableRoadRegulationQueryRepository()

        for cells: Set<RoadRegulationCellKey> in [[], [GRDBRoadRegulationFixtures.cell(1)]] {
            XCTAssertThrowsError(try repository.regulations(inCells: cells)) {
                XCTAssertEqual($0 as? RoadRegulationRepositoryError, .unavailable)
            }
        }
    }
}
