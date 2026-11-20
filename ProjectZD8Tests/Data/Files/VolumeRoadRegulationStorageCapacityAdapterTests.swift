import Foundation
import XCTest
@testable import ProjectZD8

/// `VolumeRoadRegulationStorageCapacityAdapter` が空き容量のバイト数を返し、読めない時は失敗にすることを検証します。
@MainActor
final class VolumeRoadRegulationStorageCapacityAdapterTests: XCTestCase {
    /// 存在するフォルダのボリュームでは、正の空き容量を返します。
    ///
    /// 責務: 一時フォルダの空き容量が、システムの報告する重要用途の空き容量と一致する(読めない時の代替でも正)ことを確認します。
    func testExistingVolumeReturnsPositiveCapacityMatchingSystemValue() throws {
        let url = FileManager.default.temporaryDirectory
        let adapter = VolumeRoadRegulationStorageCapacityAdapter(volumeURL: url)

        let capacity = try adapter.availableCapacityBytes()

        XCTAssertGreaterThan(capacity, 0)
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let reference = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        XCTAssertLessThan(abs(capacity - reference), 100 * 1_024 * 1_024)
    }

    /// 存在しない場所では `storageUnavailable` で失敗し、0 や成功にしません。
    ///
    /// 責務: 読めない時のエラー分類を確認します。
    func testMissingLocationThrowsStorageUnavailable() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)/file")
        let adapter = VolumeRoadRegulationStorageCapacityAdapter(volumeURL: missing)

        XCTAssertThrowsError(try adapter.availableCapacityBytes()) {
            XCTAssertEqual($0 as? RoadRegulationImportError, .storageUnavailable)
        }
    }
}
