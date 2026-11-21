import Foundation
import XCTest
@testable import ProjectZD8

/// 設定の画面のモデルを、偽物(配布元・読み取り・空き容量・版の Repository)から作った本物のユースケースで組み立てる補助です。
///
/// 版を種として入れてから `makeModel()` でモデルを作ります。`tearDown()` で門を開き、一時フォルダを消します。
@MainActor
final class RoadRegulationSettingsModelHarness {
    /// 取り込みの偽物一式です。
    let imports: RoadRegulationImportHarness
    /// 作ったモデルです(`makeModel()` の前は `nil`)。
    private(set) var model: RoadRegulationSettingsModel!

    /// 責務: 偽物一式を用意します(一覧は北海道・東京・大阪・沖縄)。
    init() throws {
        imports = try RoadRegulationImportHarness()
        imports.source.replaceCatalog(with: Self.catalog())
    }

    /// 責務: 止めた偽物を再開させ、一時フォルダを消します。
    func tearDown() {
        imports.tearDown()
        model = nil
    }

    /// 責務: 北海道・東京・大阪・沖縄の行を持つ一覧(公開の印・基準月は指定の値)を作ります。
    static func catalog(
        stamp: String = RoadRegulationTestValues.publicationStamp,
        dataMonth: RoadRegulationDataMonth? = RoadRegulationTestValues.catalogMonth
    ) -> RoadRegulationCatalog {
        RoadRegulationTestValues.catalog([1, 13, 27, 47].map(RoadRegulationTestValues.prefecture), stamp: stamp, dataMonth: dataMonth)
    }

    /// 責務: 種として有効な版を入れます。
    func seed(_ datasets: [RoadRegulationDataset]) {
        datasets.forEach(imports.datasets.seedActive)
    }

    /// 責務: 本物のユースケースからモデルを作ります(時刻は固定)。
    @discardableResult
    func makeModel() -> RoadRegulationSettingsModel {
        let datasets = imports.datasets
        let source = imports.source
        let created = RoadRegulationSettingsModel(
            list: ListRoadRegulationDatasetsUseCase(datasets: datasets),
            importer: imports.makeUseCase(),
            remover: RemoveRoadRegulationDatasetUseCase(datasets: datasets),
            catalog: FetchRoadRegulationCatalogUseCase(source: source),
            purge: PurgeRoadRegulationLeftoversUseCase(datasets: datasets, source: source),
            now: { RoadRegulationTestValues.fixedNow }
        )
        model = created
        return created
    }

    /// 責務: モデルを作って画面の表示を送り、種の版が行に出るまで期限つきで待ちます。
    @discardableResult
    func makeAppearedModel(file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        let expected = imports.datasets.currentActiveDatasets
        makeModel().send(.appeared)
        return await waitUntil("種の版が行に出る", file: file, line: line) {
            expected.allSatisfy { dataset in self.row(dataset.prefecture.rawValue).dataset == dataset }
        }
    }

    /// 責務: 県の行を返します。
    func row(_ number: Int) -> RoadRegulationPrefectureRow {
        model.state.rows[number - 1]
    }

    /// 責務: 条件が成り立つまで期限(2秒)つきで待ちます。
    func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async -> Bool {
        await LocationRecordingBoundedWaiter.waitUntil(description, file: file, line: line, condition: condition)
    }

    /// 責務: 取り込みが始まり、ダウンロードの門で止まるまで期限つきで待ちます(門は先に閉じておく)。
    func waitUntilImportIsBlocked(_ number: Int, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await waitUntil("取り込みがダウンロードで止まる", file: file, line: line) {
            imports.source.downloadGate.isWaiting && row(number).activeImport != nil
        }
    }

    /// 責務: 取り込み中の県が無くなるまで期限つきで待ちます。
    func waitUntilIdle(file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await waitUntil("取り込みが終わる", file: file, line: line) {
            model.state.importingPrefecture == nil && model.state.rows.allSatisfy { $0.activeImport == nil }
        }
    }
}
