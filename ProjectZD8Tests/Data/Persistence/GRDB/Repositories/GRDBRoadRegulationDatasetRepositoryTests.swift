import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBRoadRegulationDatasetRepository` の取り込み(開始・追記・有効化)と、有効な版の見え方を検証します。
@MainActor
final class GRDBRoadRegulationDatasetRepositoryTests: XCTestCase {
    private typealias Fixtures = GRDBRoadRegulationFixtures

    /// 取り込みの無い DB では、有効な版は空です。
    ///
    /// 責務: `activeDatasets` が空配列を返すことを確認します。
    func testActiveDatasetsIsEmptyInitially() throws {
        let fixtures = try Fixtures()

        XCTAssertEqual(try fixtures.datasets.activeDatasets(), [])
    }

    /// `beginImport` は importing の行を作り、有効な版には現れません。
    ///
    /// 責務: 保存された状態・県・公開の印・URL・取得時刻(マイクロ秒)・有効化時刻が空であることを確認します。
    func testBeginImportCreatesImportingRowInvisibleToActiveDatasets() throws {
        let fixtures = try Fixtures()

        let id = try fixtures.datasets.beginImport(Fixtures.datasetDraft())

        let row = try XCTUnwrap(fixtures.queue.read {
            try Row.fetchOne($0, sql: "SELECT * FROM road_regulation_datasets WHERE id = ?", arguments: [id.rawValue.uuidString.lowercased()])
        })
        XCTAssertEqual(row["state"] as String, "importing")
        XCTAssertEqual(row["prefectureCode"] as Int, 47)
        XCTAssertEqual(row["publicationStamp"] as String, "202611010000")
        XCTAssertEqual(row["sourceURL"] as String, "https://www.jartic.or.jp/d/opendata/202611010000/typeD_okinawa.zip")
        XCTAssertEqual(row["downloadedAtMicroseconds"] as Int64, 1_700_000_000_500_000)
        XCTAssertNil(row["activatedAtMicroseconds"] as Int64?)
        XCTAssertEqual(try fixtures.datasets.activeDatasets(), [])
    }

    /// 同じ県の取り込みを重ねて始めると `integrityConflict` です。
    ///
    /// 責務: importing が2つになる操作が一意制約違反として分類されることを確認します。
    func testSecondImportForSamePrefectureIsIntegrityConflict() throws {
        let fixtures = try Fixtures()
        _ = try fixtures.datasets.beginImport(Fixtures.datasetDraft())

        XCTAssertThrowsError(try fixtures.datasets.beginImport(Fixtures.datasetDraft(stamp: "202612010000"))) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }
        XCTAssertNoThrow(try fixtures.datasets.beginImport(Fixtures.datasetDraft(prefecture: 13)))
    }

    /// 追記は挿入した件数を返し、重複したユニークキーは数えず、その升目も入れません。
    ///
    /// 責務: 同じ batch 内・batch をまたぐ重複と、規制・升目の表の行数を確認します。
    func testAppendReturnsInsertedCountAndSkipsDuplicateKeys() throws {
        let fixtures = try Fixtures()
        let id = try fixtures.datasets.beginImport(Fixtures.datasetDraft())
        let first = [
            Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1, 2]),
            Fixtures.indexed(Fixtures.draft(key: "b"), cells: [3, 4]),
            Fixtures.indexed(Fixtures.draft(key: "a", speed: 60), cells: [100, 101])
        ]
        let second = [Fixtures.indexed(Fixtures.draft(key: "b"), cells: [200]), Fixtures.indexed(Fixtures.draft(key: "c"), cells: [5])]

        XCTAssertEqual(try fixtures.datasets.appendRegulations(first, to: id), 2)
        XCTAssertEqual(try fixtures.datasets.appendRegulations(second, to: id), 1)

        XCTAssertEqual(try fixtures.count("road_regulations"), 3)
        let cells = try fixtures.queue.read { try Int64.fetchAll($0, sql: "SELECT cellKey FROM road_regulation_cells ORDER BY cellKey") }
        XCTAssertEqual(cells, [1, 2, 3, 4, 5].map { Fixtures.cell($0).rawValue })
        XCTAssertEqual(try fixtures.datasets.appendRegulations([], to: id), 0)
    }

    /// 規制の項目が、列へ仕様どおりに保存されます。
    ///
    /// 責務: 種類・速度・片側・並び・外周の列と、条件なしは NULL・条件ありは JSON(復元すると元と一致)・形状の BLOB を確認します。
    func testAppendStoresFieldsInColumns() throws {
        let fixtures = try Fixtures()
        let id = try fixtures.datasets.beginImport(Fixtures.datasetDraft())
        let conditions = RoadRegulationConditions(
            targets: [RoadRegulationConditionSet(timeStart: "700", timeEnd: "1900", dayCode: "1")],
            exclusions: [RoadRegulationConditionSet(vehicleCodeD: "100")]
        )
        let drafts = [
            Fixtures.draft(key: "section"), Fixtures.draft(key: "oneway", kind: .oneWay, conditions: conditions),
            Fixtures.draft(key: "zone", kind: .speedLimitZone, speed: 30), Fixtures.draft(key: "stop", kind: .stop)
        ]
        _ = try fixtures.datasets.appendRegulations(drafts.map { Fixtures.indexed($0, cells: [1]) }, to: id)

        let rows = try fixtures.queue.read { try Row.fetchAll($0, sql: "SELECT * FROM road_regulations ORDER BY id") }

        XCTAssertEqual(rows.map { $0["uniqueKey"] as String }, ["section", "oneway", "zone", "stop"])
        XCTAssertEqual(rows.map { $0["kind"] as String }, ["speedLimitSection", "oneWay", "speedLimitZone", "stop"])
        XCTAssertEqual(rows.map { $0["speedLimitKph"] as Int? }, [40, nil, 30, nil])
        XCTAssertEqual(rows.map { $0["sideCode"] as Int? }, [3, nil, nil, nil])
        XCTAssertEqual(rows.map { $0["oneWayOrder"] as Int? }, [nil, 2, nil, nil])
        XCTAssertEqual(rows.map { $0["perimeterRoadIncluded"] as Int? }, [nil, nil, 1, nil])
        XCTAssertNil(rows[0]["conditions"] as String?)
        let json = try XCTUnwrap(rows[1]["conditions"] as String?)
        XCTAssertEqual(try JSONDecoder().decode(RoadRegulationConditions.self, from: Data(json.utf8)), conditions)
        let geometry = try RoadRegulationGeometryBlobCodec().decode(rows[3]["geometry"] as Data)
        XCTAssertEqual(geometry.parts.map(\.role), [.main, .approach])
    }

    /// 存在しない版への追記と有効化は `notFound` です。
    ///
    /// 責務: id 不在が制約違反や利用不能ではなく `notFound` になることを確認します。
    func testUnknownDatasetIsNotFound() throws {
        let fixtures = try Fixtures()
        let unknown = RoadRegulationDatasetID(rawValue: UUID())

        XCTAssertThrowsError(try fixtures.datasets.appendRegulations([Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])], to: unknown)) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .notFound)
        }
        XCTAssertThrowsError(try fixtures.datasets.activate(unknown, summary: Fixtures.summary(), activatedAt: Date())) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .notFound)
        }
        XCTAssertEqual(try fixtures.count("road_regulations"), 0)
    }

    /// 取り込み中でない版への追記と有効化は `integrityConflict` で、何も変わりません。
    ///
    /// 責務: active の版への追記、active・retired の版の再有効化が拒否され、行数と状態が不変であることを確認します。
    func testNonImportingDatasetRejectsAppendAndActivate() throws {
        let fixtures = try Fixtures()
        let active = try fixtures.importActive(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])
        let extra = [Fixtures.indexed(Fixtures.draft(key: "b"), cells: [2])]
        let summary = Fixtures.summary()

        XCTAssertThrowsError(try fixtures.datasets.appendRegulations(extra, to: active.id)) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }
        XCTAssertThrowsError(try fixtures.datasets.activate(active.id, summary: summary, activatedAt: Date())) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }
        XCTAssertTrue(try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(47)))
        XCTAssertThrowsError(try fixtures.datasets.appendRegulations(extra, to: active.id)) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }
        XCTAssertThrowsError(try fixtures.datasets.activate(active.id, summary: summary, activatedAt: Date())) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }
        XCTAssertEqual(try fixtures.count("road_regulations"), 1)
        XCTAssertEqual(try fixtures.state(of: active.id), "retired")
    }

    /// CHECK に反する規制は黙って飛ばさず `integrityConflict` で、その batch の行は1つも残りません。
    ///
    /// 責務: 速度 0 の規制を含む batch が失敗し、同じ batch の正しい規制も保存されない(1トランザクション)ことを確認します。
    func testConstraintViolatingRegulationFailsWholeBatch() throws {
        let fixtures = try Fixtures()
        let id = try fixtures.datasets.beginImport(Fixtures.datasetDraft())
        let batch = [
            Fixtures.indexed(Fixtures.draft(key: "good"), cells: [1]),
            Fixtures.indexed(Fixtures.draft(key: "bad", speed: 0), cells: [2])
        ]

        XCTAssertThrowsError(try fixtures.datasets.appendRegulations(batch, to: id)) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }

        XCTAssertEqual(try fixtures.count("road_regulations"), 0)
        XCTAssertEqual(try fixtures.count("road_regulation_cells"), 0)
    }

    /// 有効化は、版の内容と取り込みの結果を保存し、返した版が有効な版として読めます。
    ///
    /// 責務: 返り値の全項目・`activeDatasets`・拒否件数の表(0件の理由は行にしない)を確認します。
    func testActivateStoresSummaryAndReturnsActiveDataset() throws {
        let fixtures = try Fixtures()
        let summary = Fixtures.summary()
        let id = try fixtures.beginAndAppend(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])

        let dataset = try fixtures.datasets.activate(id, summary: summary, activatedAt: Date(timeIntervalSince1970: 1_700_000_100.25))

        let expected = RoadRegulationDataset(
            id: id, prefecture: Fixtures.prefecture(47), state: .active, dataMonth: summary.dataMonth, publicationStamp: "202611010000",
            sourceURL: URL(string: "https://www.jartic.or.jp/d/opendata/202611010000/typeD_okinawa.zip")!,
            downloadedAt: Date(timeIntervalSince1970: 1_700_000_000.5), activatedAt: Date(timeIntervalSince1970: 1_700_000_100.25),
            formatVersion: "2.1", counts: summary.counts, coverage: summary.coverage
        )
        XCTAssertEqual(dataset, expected)
        XCTAssertEqual(try fixtures.datasets.activeDatasets(), [expected])
        let rejections = try fixtures.queue.read { try Row.fetchAll($0, sql: "SELECT reason, count FROM road_regulation_dataset_rejections ORDER BY reason") }
        XCTAssertEqual(rejections.map { $0["reason"] as String }, ["invalidSpeed", "shapeMismatch"])
        XCTAssertEqual(rejections.map { $0["count"] as Int }, [2, 1])
    }

    /// 有効化で、同じ県の旧 active は retired になり、他の県の active は変わりません。
    ///
    /// 責務: 旧版・他県・新版の状態と、`activeDatasets` が県の昇順で新版だけを返すことを確認します。
    func testActivateRetiresPreviousActiveOfSamePrefectureOnly() throws {
        let fixtures = try Fixtures()
        let old = try fixtures.importActive(prefecture: 47, stamp: "202610010000", regulations: [])
        let other = try fixtures.importActive(prefecture: 13, regulations: [])

        let new = try fixtures.importActive(prefecture: 47, stamp: "202611010000", regulations: [])

        XCTAssertEqual(try fixtures.state(of: old.id), "retired")
        XCTAssertEqual(try fixtures.state(of: other.id), "active")
        XCTAssertEqual(try fixtures.state(of: new.id), "active")
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [other.id, new.id])
    }

    /// 有効な版は都道府県コードの昇順で返ります。
    ///
    /// 責務: 47・13・1 の順に有効化しても、1・13・47 の順で返ることを確認します。
    func testActiveDatasetsAreOrderedByPrefecture() throws {
        let fixtures = try Fixtures()
        for number in [47, 13, 1] { try fixtures.importActive(prefecture: number, regulations: []) }

        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.prefecture.rawValue), [1, 13, 47])
    }

    /// 取り込み中の新しい版は、有効化されるまで有効な版に現れず、古い版が有効なままです。
    ///
    /// 責務: 取り込み途中の `activeDatasets` が旧版だけであることを確認します。
    func testImportingVersionNeverReplacesActiveBeforeActivation() throws {
        let fixtures = try Fixtures()
        let old = try fixtures.importActive(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])

        let importing = try fixtures.beginAndAppend(stamp: "202612010000", regulations: [Fixtures.indexed(Fixtures.draft(key: "b"), cells: [1])])

        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [old.id])
        XCTAssertEqual(try fixtures.state(of: importing), "importing")
    }

    /// 有効化が途中で失敗しても、旧 active は active のまま、新版は importing のままです。
    ///
    /// 責務: 制約に反する取り込み結果(負の件数)で `integrityConflict` になり、状態が1つも変わらないことを確認します。
    func testFailedActivationLeavesPreviousActiveUntouched() throws {
        let fixtures = try Fixtures()
        let old = try fixtures.importActive(regulations: [])
        let importing = try fixtures.beginAndAppend(stamp: "202612010000", regulations: [])
        let valid = Fixtures.summary()
        let broken = RoadRegulationImportSummary(
            dataMonth: valid.dataMonth, formatVersion: valid.formatVersion,
            counts: RoadRegulationImportCounts(totalRows: -1, importedRegulations: 0, skippedOutOfScope: 0, skippedAbolished: 0, rejectedByReason: [:]),
            coverage: valid.coverage
        )

        XCTAssertThrowsError(try fixtures.datasets.activate(importing, summary: broken, activatedAt: Date(timeIntervalSince1970: 1))) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict)
        }

        XCTAssertEqual(try fixtures.state(of: old.id), "active")
        XCTAssertEqual(try fixtures.state(of: importing), "importing")
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [old.id])
    }
}
