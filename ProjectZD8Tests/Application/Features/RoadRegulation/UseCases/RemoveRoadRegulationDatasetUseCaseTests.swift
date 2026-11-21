import Foundation
import XCTest
@testable import ProjectZD8

/// `RemoveRoadRegulationDatasetUseCase` が、指定の県の有効な版を退役させてから掃除し、他の県の版に触れないことを検証します。
///
/// 取り込み中に削除できないことは、画面のモデルの側(`RoadRegulationSettingsModelRemovalTests`)で検証します。
@MainActor
final class RemoveRoadRegulationDatasetUseCaseTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    /// 責務: 削除を期限つきで実行し、結果を返します。
    private func remove(
        _ prefecture: JapanesePrefectureCode,
        from repository: RoadRegulationDatasetRepositorySpy
    ) async -> Result<Void, any Error>? {
        let useCase = RemoveRoadRegulationDatasetUseCase(datasets: repository)
        return await TestBoundedAsyncRun { try await useCase.execute(prefecture: prefecture) }.result(on: self)
    }

    /// 有効な版を退役させてから掃除するので、その県の版は残らず、他の県の版はそのままです。
    ///
    /// 責務: 退役 → 掃除の順と、削除後の有効な版を確認します。
    func testRetiresThenPurgesOnlyTheRequestedPrefecture() async throws {
        let repository = RoadRegulationDatasetRepositorySpy()
        let okinawa = Values.dataset(Values.prefecture(47))
        let tokyo = Values.dataset(Values.prefecture(13))
        repository.seedActive(okinawa)
        repository.seedActive(tokyo)

        let finished = await remove(Values.prefecture(47), from: repository)
        let result = try XCTUnwrap(finished)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(repository.retiredPrefectures, [Values.prefecture(47)])
        let retire = try XCTUnwrap(repository.log.firstIndex(of: .retireActiveDataset))
        let purge = try XCTUnwrap(repository.log.lastIndex(of: .purgeInactiveDatasets))
        XCTAssertLessThan(retire, purge)
        XCTAssertEqual(repository.currentActiveDatasets, [tokyo])
        XCTAssertTrue(repository.retiredDatasetIDs.isEmpty, "退役した版が掃除されていません")
    }

    /// 有効な版が無い県を削除しても失敗しません。
    ///
    /// 責務: 退役の対象が無い時の結果を確認します。
    func testRemovingPrefectureWithoutDatasetSucceeds() async throws {
        let repository = RoadRegulationDatasetRepositorySpy()
        let tokyo = Values.dataset(Values.prefecture(13))
        repository.seedActive(tokyo)

        let finished = await remove(Values.prefecture(47), from: repository)
        let result = try XCTUnwrap(finished)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(repository.currentActiveDatasets, [tokyo])
    }

    /// 退役が保存の失敗なら、失敗を握りつぶさずに `storageUnavailable` として伝え、有効な版はそのままです。
    ///
    /// 責務: 退役の失敗が伝わることを確認します。
    func testRetireFailureIsReported() async throws {
        let repository = RoadRegulationDatasetRepositorySpy()
        let okinawa = Values.dataset(Values.prefecture(47))
        repository.seedActive(okinawa)
        repository.fail(.retireActiveDataset, with: .unavailable)

        let finished = await remove(Values.prefecture(47), from: repository)
        let result = try XCTUnwrap(finished)

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? RoadRegulationImportError, .storageUnavailable)
        }
        XCTAssertEqual(repository.currentActiveDatasets, [okinawa])
    }

    /// 退役の後の掃除が失敗しても、削除は成功として扱い、有効な版は無くなっています。
    ///
    /// 責務: 続く掃除の失敗を無視することを確認します。
    func testPurgeFailureAfterRetireIsIgnored() async throws {
        let repository = RoadRegulationDatasetRepositorySpy()
        repository.seedActive(Values.dataset(Values.prefecture(47)))
        repository.fail(.purgeInactiveDatasets, with: .unavailable)

        let finished = await remove(Values.prefecture(47), from: repository)
        let result = try XCTUnwrap(finished)

        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(repository.currentActiveDatasets.isEmpty)
        XCTAssertEqual(repository.purgeCount, 1)
    }
}
