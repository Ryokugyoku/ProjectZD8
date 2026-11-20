import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationAttribution` が、出典(データ名と JARTIC の名称)・ページ URL・利用日・加工した旨・注意書きを必ず持つことを検証します。
@MainActor
final class RoadRegulationAttributionTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    /// 出典・利用日・加工した旨・注意書きのキーは、A11 の出典のキーです。
    ///
    /// 責務: 4つのキーの値を確認します。
    func testKeysAreAttributionKeys() {
        XCTAssertEqual(RoadRegulationAttribution.sourceKey, "road_regulation.attribution.source")
        XCTAssertEqual(RoadRegulationAttribution.usedOnKey, "road_regulation.attribution.used_on")
        XCTAssertEqual(RoadRegulationAttribution.processedKey, "road_regulation.attribution.processed")
        XCTAssertEqual(RoadRegulationAttribution.disclaimerKey, "road_regulation.attribution.disclaimer")
        let all = [RoadRegulationAttribution.sourceKey, RoadRegulationAttribution.usedOnKey,
                   RoadRegulationAttribution.processedKey, RoadRegulationAttribution.disclaimerKey]
        XCTAssertEqual(Set(all), Set(RoadRegulationSettingsKeyCatalog.attributionKeys))
    }

    /// ページ URL は JARTIC のオープンデータの配布ページの `https://www.jartic.or.jp/service/opendata/` です。
    ///
    /// 責務: `sourceURLString` の形を確認します。
    func testSourceURLIsJARTICOpenDataPage() throws {
        XCTAssertEqual(RoadRegulationAttribution.sourceURLString, "https://www.jartic.or.jp/service/opendata/")
        let url = try XCTUnwrap(URL(string: RoadRegulationAttribution.sourceURLString))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.jartic.or.jp")
    }

    /// 利用日は、取得済みの版の中で最新の取得日です。
    ///
    /// 責務: 複数の版から取得日の最大を選ぶことを確認します(並びに依存しない)。
    func testUsedOnIsLatestDownloadDate() {
        let older = Values.dataset(Values.prefecture(13), downloadedAt: Values.fixedNow.addingTimeInterval(-10 * 86_400))
        let newest = Values.dataset(Values.prefecture(47), downloadedAt: Values.fixedNow.addingTimeInterval(-86_400))
        let middle = Values.dataset(Values.prefecture(1), downloadedAt: Values.fixedNow.addingTimeInterval(-5 * 86_400))

        XCTAssertEqual(RoadRegulationAttribution(datasets: [older, newest, middle]).usedOn, newest.downloadedAt)
        XCTAssertEqual(RoadRegulationAttribution(datasets: [newest, middle, older]).usedOn, newest.downloadedAt)
    }

    /// 版が1つなら、その取得日が利用日です。
    ///
    /// 責務: 1件の時の利用日を確認します。
    func testUsedOnWithSingleDataset() {
        let dataset = Values.dataset(Values.prefecture(47))

        XCTAssertEqual(RoadRegulationAttribution(datasets: [dataset]).usedOn, dataset.downloadedAt)
    }

    /// 版が無ければ利用日は `nil` です(推測の日付を出しません)。
    ///
    /// 責務: 0件の時の利用日を確認します。
    func testUsedOnIsNilWithoutDatasets() {
        XCTAssertNil(RoadRegulationAttribution(datasets: []).usedOn)
    }
}
