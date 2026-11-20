import Foundation
import XCTest
@testable import ProjectZD8

/// DB 準備不可時の交通規制の版 Repository が、すべての操作を明示的な利用不能として失敗させることを検証します。
@MainActor
final class UnavailableRoadRegulationDatasetRepositoryTests: XCTestCase {
    /// 7つの操作はすべて `unavailable` で失敗します。
    ///
    /// 責務: 読出し・取り込み・有効化・破棄・退役・掃除が、成功や空の結果を返さないことを確認します。
    func testAllOperationsThrowUnavailable() throws {
        let repository = UnavailableRoadRegulationDatasetRepository()
        let id = RoadRegulationDatasetID(rawValue: UUID())
        let prefecture = GRDBRoadRegulationFixtures.prefecture(47)

        assertUnavailable { _ = try repository.activeDatasets() }
        assertUnavailable { _ = try repository.beginImport(GRDBRoadRegulationFixtures.datasetDraft()) }
        assertUnavailable { _ = try repository.appendRegulations([], to: id) }
        assertUnavailable { _ = try repository.activate(id, summary: GRDBRoadRegulationFixtures.summary(), activatedAt: Date()) }
        assertUnavailable { try repository.discard(id) }
        assertUnavailable { _ = try repository.retireActiveDataset(for: prefecture) }
        assertUnavailable { try repository.purgeInactiveDatasets() }
    }

    /// 処理が利用不能で失敗することを検証します。
    ///
    /// 責務: 送出されたエラーが `RoadRegulationRepositoryError.unavailable` であることを確認します。
    private func assertUnavailable(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .unavailable, file: file, line: line)
        }
    }
}
