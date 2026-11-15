import XCTest
@testable import ProjectZD8

/// manifestへ記録する取得契約のversion一式を検証します。
final class AcquisitionManifestVersionsTests: XCTestCase {
    /// 4つのversionを渡した値のまま保持します。
    ///
    /// 責務: 各versionが入れ替わらずに保持されることを確認します。
    func testKeepsEachVersion() {
        let versions = AcquisitionManifestVersions(
            manifestVersion: 1, pollingPolicyVersion: 2, modelInputManifestVersion: 3, formulaCanonicalizationVersion: 4
        )

        XCTAssertEqual(versions.manifestVersion, 1)
        XCTAssertEqual(versions.pollingPolicyVersion, 2)
        XCTAssertEqual(versions.modelInputManifestVersion, 3)
        XCTAssertEqual(versions.formulaCanonicalizationVersion, 4)
    }
}
