import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBRoadRegulationQueryRepository` の升目の key による検索を検証します(有効な版だけ・重複なし・id 昇順・分割して問い合わせ)。
@MainActor
final class GRDBRoadRegulationQueryRepositoryTests: XCTestCase {
    private typealias Fixtures = GRDBRoadRegulationFixtures

    /// 升目の番号から key の集合を作ります。
    private func cells(_ numbers: [Int]) -> Set<RoadRegulationCellKey> {
        Set(numbers.map(Fixtures.cell))
    }

    /// 検索結果のユニークキーを id 昇順の並びのまま返します。
    private func keys(_ regulations: [RoadRegulation]) -> [String] {
        regulations.map(\.uniqueKey)
    }

    /// 升目が空なら結果も空で、該当しない升目でも空です。
    ///
    /// 責務: 空集合と、規制の無い升目の検索が空配列を返すことを確認します。
    func testEmptyAndUnrelatedCellsReturnNothing() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])

        XCTAssertEqual(try fixtures.query.regulations(inCells: []), [])
        XCTAssertEqual(try fixtures.query.regulations(inCells: cells([2, 3])), [])
    }

    /// 要求した升目に載る規制だけを返します。
    ///
    /// 責務: 別の升目にだけ載る規制が混ざらないことを確認します。
    func testOnlyRegulationsInRequestedCellsAreReturned() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [
            Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1]), Fixtures.indexed(Fixtures.draft(key: "b"), cells: [2]),
            Fixtures.indexed(Fixtures.draft(key: "c"), cells: [2, 3])
        ])

        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["a"])
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([2]))), ["b", "c"])
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([3, 9]))), ["c"])
    }

    /// 保存した規制のすべての項目が、版の識別子とともに復元されます。
    ///
    /// 責務: 全種類について、種類・速度・片側・並び・外周・条件・形状(1e-7 度以内)・ユニークキー・版の id を確認します。
    func testRegulationsAreRestoredWithAllFields() throws {
        let fixtures = try Fixtures()
        let conditions = RoadRegulationConditions(
            targets: [RoadRegulationConditionSet(periodStart: "0401", periodEnd: "0930", timeStart: "2200", timeEnd: "400", dayCode: "5")],
            exclusions: [RoadRegulationConditionSet(vehicleCodeA: "1"), .empty, RoadRegulationConditionSet(vehicleCodeD: "1000")]
        )
        let drafts = RoadRegulationKind.allCases.enumerated().map { index, kind in
            Fixtures.draft(key: "k\(index)", kind: kind, speed: 20 + index, conditions: index.isMultiple(of: 2) ? conditions : .unconditional)
        }
        let dataset = try fixtures.importActive(regulations: drafts.map { Fixtures.indexed($0, cells: [1]) })

        let restored = try fixtures.query.regulations(inCells: cells([1]))

        XCTAssertEqual(restored.count, drafts.count)
        for (draft, regulation) in zip(drafts, restored) {
            XCTAssertEqual(regulation.datasetID, dataset.id)
            XCTAssertEqual(regulation.uniqueKey, draft.uniqueKey)
            XCTAssertEqual(regulation.kind, draft.kind)
            XCTAssertEqual(regulation.speedLimitKph, draft.speedLimitKph)
            XCTAssertEqual(regulation.side, draft.side)
            XCTAssertEqual(regulation.oneWayOrder, draft.oneWayOrder)
            XCTAssertEqual(regulation.perimeterRoadIncluded, draft.perimeterRoadIncluded)
            XCTAssertEqual(regulation.conditions, draft.conditions)
            assertGeometry(regulation.geometry, matches: draft.geometry)
        }
    }

    /// 取り込み中の版は検索に現れず、有効化で新しい版へ入れ替わります。
    ///
    /// 責務: 取り込み途中は旧版だけ、有効化後は新版だけ(旧版は retired)が返ることを確認します。
    func testImportingVersionIsInvisibleUntilActivationThenReplacesOldVersion() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(stamp: "202610010000", regulations: [Fixtures.indexed(Fixtures.draft(key: "old"), cells: [1])])
        let importing = try fixtures.beginAndAppend(stamp: "202611010000", regulations: [Fixtures.indexed(Fixtures.draft(key: "new"), cells: [1])])
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["old"])

        _ = try fixtures.datasets.activate(importing, summary: Fixtures.summary(), activatedAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["new"])
    }

    /// 途中で放棄・失敗した取り込みの後も、前の版が検索できます。
    ///
    /// 責務: 破棄した後と、有効化に失敗した後に、旧版の規制が返ることを確認します。
    func testPreviousVersionStaysSearchableAfterAbandonedOrFailedImport() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(stamp: "202610010000", regulations: [Fixtures.indexed(Fixtures.draft(key: "old"), cells: [1])])
        let abandoned = try fixtures.beginAndAppend(stamp: "202611010000", regulations: [Fixtures.indexed(Fixtures.draft(key: "new"), cells: [1])])
        let valid = Fixtures.summary()
        let broken = RoadRegulationImportSummary(
            dataMonth: valid.dataMonth, formatVersion: valid.formatVersion,
            counts: RoadRegulationImportCounts(totalRows: -1, importedRegulations: 0, skippedOutOfScope: 0, skippedAbolished: 0, rejectedByReason: [:]),
            coverage: valid.coverage
        )

        XCTAssertThrowsError(try fixtures.datasets.activate(abandoned, summary: broken, activatedAt: Date()))
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["old"])
        try fixtures.datasets.discard(abandoned)
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["old"])
        try fixtures.datasets.purgeInactiveDatasets()
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells([1]))), ["old"])
    }

    /// 退役した版の規制は検索に出ません。
    ///
    /// 責務: `retireActiveDataset` の後に、行が残っていても結果が空になることを確認します。
    func testRetiredDatasetIsNotSearched() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])

        XCTAssertTrue(try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(47)))

        XCTAssertEqual(try fixtures.count("road_regulations"), 1)
        XCTAssertEqual(try fixtures.query.regulations(inCells: cells([1])), [])
    }

    /// 別の県の版と混ざりません。同じ升目に両方があれば両方、片方の升目だけならその県の規制だけです。
    ///
    /// 責務: 2つの有効な版の規制が、升目ごとに正しい版の id で返ることを確認します。
    func testRegulationsOfDifferentPrefecturesAreNotMixed() throws {
        let fixtures = try Fixtures()
        let okinawa = try fixtures.importActive(prefecture: 47, regulations: [
            Fixtures.indexed(Fixtures.draft(key: "o1"), cells: [1]), Fixtures.indexed(Fixtures.draft(key: "shared"), cells: [5])
        ])
        let tokyo = try fixtures.importActive(prefecture: 13, regulations: [
            Fixtures.indexed(Fixtures.draft(key: "t1"), cells: [2]), Fixtures.indexed(Fixtures.draft(key: "shared"), cells: [5])
        ])

        let first = try fixtures.query.regulations(inCells: cells([1]))
        let second = try fixtures.query.regulations(inCells: cells([2]))
        let both = try fixtures.query.regulations(inCells: cells([5]))

        XCTAssertEqual(first.map(\.datasetID), [okinawa.id])
        XCTAssertEqual(second.map(\.datasetID), [tokyo.id])
        XCTAssertEqual(both.map(\.datasetID), [okinawa.id, tokyo.id])
        XCTAssertEqual(try fixtures.query.regulations(inCells: cells([1, 2])).count, 2)
    }

    /// 同じ規制が複数の升目に載っていても、重複して返りません。
    ///
    /// 責務: 3つの升目を一度に問い合わせて、1件だけ返ることを確認します。
    func testRegulationInManyCellsIsReturnedOnce() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [
            Fixtures.indexed(Fixtures.draft(key: "wide"), cells: [1, 2, 3]), Fixtures.indexed(Fixtures.draft(key: "narrow"), cells: [3])
        ])

        let result = try fixtures.query.regulations(inCells: cells([1, 2, 3]))

        XCTAssertEqual(keys(result), ["wide", "narrow"])
    }

    /// 結果は id の昇順です。
    ///
    /// 責務: 挿入順と升目の番号の順が逆でも、id 昇順で返ることを確認します。
    func testResultsAreOrderedByIdAscending() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [
            Fixtures.indexed(Fixtures.draft(key: "first"), cells: [9]), Fixtures.indexed(Fixtures.draft(key: "second"), cells: [1]),
            Fixtures.indexed(Fixtures.draft(key: "third"), cells: [5])
        ])

        let result = try fixtures.query.regulations(inCells: cells([1, 5, 9]))

        XCTAssertEqual(keys(result), ["first", "second", "third"])
        XCTAssertEqual(result.map(\.id), result.map(\.id).sorted())
    }

    /// 升目が多い時は分けて問い合わせても、結果は漏れも重複もなく id 昇順です。
    ///
    /// 責務: 1回3升目に設定して10升目を問い合わせ、境界をまたぐ規制が1件ずつ・id 昇順で返ることを確認します。
    func testSplitQueriesKeepCompletenessUniquenessAndOrder() throws {
        let fixtures = try Fixtures(cellsPerQuery: 3)
        try fixtures.importActive(regulations: [
            Fixtures.indexed(Fixtures.draft(key: "far"), cells: [9, 0]), Fixtures.indexed(Fixtures.draft(key: "mid"), cells: [4]),
            Fixtures.indexed(Fixtures.draft(key: "spread"), cells: [1, 5, 8]), Fixtures.indexed(Fixtures.draft(key: "outside"), cells: [50])
        ])

        let result = try fixtures.query.regulations(inCells: cells(Array(0...9)))

        XCTAssertEqual(keys(result), ["far", "mid", "spread"])
    }

    /// 既定の分割(500升目)をまたぐ600升目・1,200升目の問い合わせでも、漏れなく id 昇順です。
    ///
    /// 責務: 先頭・中ほど・末尾の升目に載る規制が、挿入順(= id 昇順)で返ることを確認します。
    func testDefaultSplitAcrossSixHundredAndTwelveHundredCells() throws {
        let fixtures = try Fixtures()
        try fixtures.importActive(regulations: [
            Fixtures.indexed(Fixtures.draft(key: "tail"), cells: [1_199]), Fixtures.indexed(Fixtures.draft(key: "head"), cells: [0]),
            Fixtures.indexed(Fixtures.draft(key: "middle"), cells: [550, 599]), Fixtures.indexed(Fixtures.draft(key: "beyond"), cells: [5_000])
        ])

        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells(Array(0..<600)))), ["head", "middle"])
        XCTAssertEqual(keys(try fixtures.query.regulations(inCells: cells(Array(0..<1_200)))), ["tail", "head", "middle"])
    }

    /// 壊れた形状の BLOB と、壊れた条件の JSON は `integrityConflict` です。
    ///
    /// 責務: 版違い・途中で切れた BLOB と、JSON でない条件が、成功や空の結果にならないことを確認します。
    func testCorruptStoredValuesThrowIntegrityConflict() throws {
        let corruptions: [(String, any DatabaseValueConvertible)] = [
            ("geometry", Data([9, 0, 0])), ("geometry", Data([1, 1, 0, 0])), ("conditions", "not json")
        ]
        for (column, value) in corruptions {
            let fixtures = try Fixtures()
            try fixtures.importActive(regulations: [Fixtures.indexed(Fixtures.draft(key: "a"), cells: [1])])
            let sql = column == "geometry" ? "UPDATE road_regulations SET geometry = ?" : "UPDATE road_regulations SET conditions = ?"
            try fixtures.queue.write { try $0.execute(sql: sql, arguments: [value]) }

            XCTAssertThrowsError(try fixtures.query.regulations(inCells: cells([1])), column) {
                XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict, column)
            }
        }
    }

    /// 形状が1e-7 度以内で一致することを確認します。
    private func assertGeometry(
        _ actual: RoadRegulationGeometry, matches expected: RoadRegulationGeometry, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.parts.map(\.role), expected.parts.map(\.role), file: file, line: line)
        let pairs = zip(actual.parts.flatMap(\.coordinates), expected.parts.flatMap(\.coordinates))
        XCTAssertEqual(actual.parts.flatMap(\.coordinates).count, expected.parts.flatMap(\.coordinates).count, file: file, line: line)
        for (restored, original) in pairs {
            XCTAssertEqual(restored.latitude, original.latitude, accuracy: 1e-7, file: file, line: line)
            XCTAssertEqual(restored.longitude, original.longitude, accuracy: 1e-7, file: file, line: line)
        }
    }
}
