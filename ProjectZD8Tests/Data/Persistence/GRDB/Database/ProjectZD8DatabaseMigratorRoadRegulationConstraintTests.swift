import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 交通規制の表の CHECK・一意制約・外部キー・CASCADE を、直接 INSERT で検証します。
@MainActor
final class ProjectZD8DatabaseMigratorRoadRegulationConstraintTests: XCTestCase {
    private typealias Rows = RoadRegulationSchemaRows
    private let datasetA = "00000000-0000-0000-0000-0000000000a1"
    private let datasetB = "00000000-0000-0000-0000-0000000000b2"

    /// 対照: 既定の importing の行と、すべて埋めた active の行は挿入できます。
    ///
    /// 責務: 以降の拒否テストの前提となる、受け入れられる行を確認します。
    func testDefaultImportingAndFullActiveRowsAreAccepted() throws {
        let rows = try Rows()

        rows.assertAccepted("importing") { try rows.insert($0, Rows.Dataset()) }
        rows.assertAccepted("active") { try rows.insert($0, Rows.Dataset.active(id: datasetB, prefecture: 13)) }
        rows.assertAccepted("regulation") { try rows.insert($0, Rows.Regulation(id: 1)) }
    }

    /// 都道府県コード・状態・公開の印・年月の範囲外の版の行は拒否されます。
    ///
    /// 責務: 境界の外の値が CHECK で拒否され、境界の値は受け入れられることを確認します。
    func testDatasetRangeChecks() throws {
        let rows = try Rows()

        rows.assertRejected("prefecture 0") { try rows.insert($0, Rows.Dataset(prefecture: 0)) }
        rows.assertRejected("prefecture 48") { try rows.insert($0, Rows.Dataset(prefecture: 48)) }
        rows.assertRejected("state") { try rows.insert($0, Rows.Dataset(state: "done")) }
        rows.assertRejected("stamp 11") { try rows.insert($0, Rows.Dataset(stamp: String(repeating: "1", count: 11))) }
        rows.assertRejected("stamp 13") { try rows.insert($0, Rows.Dataset(stamp: String(repeating: "1", count: 13))) }
        rows.assertRejected("year 1999") { try rows.insert($0, Rows.Dataset(dataYear: 1999, dataMonth: 1)) }
        rows.assertRejected("year 3000") { try rows.insert($0, Rows.Dataset(dataYear: 3000, dataMonth: 1)) }
        rows.assertRejected("month 0") { try rows.insert($0, Rows.Dataset(dataYear: 2026, dataMonth: 0)) }
        rows.assertRejected("month 13") { try rows.insert($0, Rows.Dataset(dataYear: 2026, dataMonth: 13)) }
        rows.assertAccepted("pref 1, 2000/1") { try rows.insert($0, Rows.Dataset(id: datasetA, prefecture: 1, dataYear: 2000, dataMonth: 1)) }
        rows.assertAccepted("pref 47, 2999/12") { try rows.insert($0, Rows.Dataset(id: datasetB, prefecture: 47, dataYear: 2999, dataMonth: 12)) }
    }

    /// 件数の列は負の値を拒否します。
    ///
    /// 責務: 4つの件数の列それぞれで負の値が CHECK で拒否されることを確認します。
    func testNegativeCountsAreRejected() throws {
        let rows = try Rows()

        rows.assertRejected("total") { try rows.insert($0, Rows.Dataset(totalRows: -1)) }
        rows.assertRejected("imported") { try rows.insert($0, Rows.Dataset(importedCount: -1)) }
        rows.assertRejected("skippedOutOfScope") { try rows.insert($0, Rows.Dataset(skippedOutOfScope: -1)) }
        rows.assertRejected("skippedAbolished") { try rows.insert($0, Rows.Dataset(skippedAbolished: -1)) }
    }

    /// active の行は、必要な欄が1つでも欠けると拒否されます。
    ///
    /// 責務: 有効化時刻・年・月・形式の版・範囲の4つの欄を1つずつ欠けさせて拒否を確認します。
    func testActiveRowRequiresAllColumns() throws {
        let rows = try Rows()
        var missing: [(String, Rows.Dataset)] = []
        var row = Rows.Dataset.active(); row.activatedAt = nil; missing.append(("activatedAt", row))
        row = Rows.Dataset.active(); row.dataYear = nil; missing.append(("dataYear", row))
        row = Rows.Dataset.active(); row.dataMonth = nil; missing.append(("dataMonth", row))
        row = Rows.Dataset.active(); row.formatVersion = nil; missing.append(("formatVersion", row))
        for index in 0..<4 {
            row = Rows.Dataset.active(); row.coverage[index] = nil; missing.append(("coverage\(index)", row))
        }

        for (label, row) in missing {
            rows.assertRejected(label) { try rows.insert($0, row) }
        }
    }

    /// 同じ県の active が2つ・importing が2つは一意制約違反で、別の組み合わせは許されます。
    ///
    /// 責務: 部分一意索引の効き方(同じ状態の重複だけ拒否)を確認します。
    func testOnlyOneActiveAndOneImportingPerPrefecture() throws {
        let rows = try Rows()
        let ids = (0..<4).map { String(format: "00000000-0000-0000-0000-00000000000%d", $0) }
        try rows.queue.write {
            try rows.insert($0, Rows.Dataset.active(id: ids[0], prefecture: 47))
            try rows.insert($0, Rows.Dataset(id: ids[1], prefecture: 47, state: "importing"))
        }

        rows.assertRejected("second active", code: .SQLITE_CONSTRAINT_UNIQUE) { try rows.insert($0, Rows.Dataset.active(id: ids[2], prefecture: 47)) }
        let secondImporting = Rows.Dataset(id: ids[2], prefecture: 47, state: "importing")
        rows.assertRejected("second importing", code: .SQLITE_CONSTRAINT_UNIQUE) { try rows.insert($0, secondImporting) }
        rows.assertAccepted("active elsewhere") { try rows.insert($0, Rows.Dataset.active(id: ids[2], prefecture: 13)) }
        var retired = Rows.Dataset.active(id: ids[3], prefecture: 47)
        retired.state = "retired"
        rows.assertAccepted("retired alongside") { try rows.insert($0, retired) }
        retired.id = "00000000-0000-0000-0000-000000000009"
        rows.assertAccepted("many retired") { try rows.insert($0, retired) }
    }

    /// 規制の行の CHECK: 種類・速度・片側・並び・外周・ユニークキーの長さ・形状の長さ。
    ///
    /// 責務: 範囲外の値が拒否されることを確認します。
    func testRegulationValueChecks() throws {
        let rows = try Rows()
        try rows.queue.write { try rows.insert($0, Rows.Dataset()) }

        rows.assertRejected("kind") { try rows.insert($0, Rows.Regulation(kind: "unknown")) }
        rows.assertRejected("speed 0") { try rows.insert($0, Rows.Regulation(speed: 0)) }
        rows.assertRejected("speed 121") { try rows.insert($0, Rows.Regulation(speed: 121)) }
        rows.assertRejected("side 4") { try rows.insert($0, Rows.Regulation(side: 4)) }
        rows.assertRejected("side 0") { try rows.insert($0, Rows.Regulation(side: 0)) }
        rows.assertRejected("perimeter 2") { try rows.insert($0, Rows.Regulation(perimeter: 2)) }
        rows.assertRejected("key empty") { try rows.insert($0, Rows.Regulation(uniqueKey: "")) }
        rows.assertRejected("key 65") { try rows.insert($0, Rows.Regulation(uniqueKey: String(repeating: "k", count: 65))) }
        rows.assertRejected("geometry 2 bytes") { try rows.insert($0, Rows.Regulation(geometry: Data([1, 0]))) }
        rows.assertAccepted("speed 1") { try rows.insert($0, Rows.Regulation(id: 1, uniqueKey: "a", speed: 1)) }
        rows.assertAccepted("speed 120") { try rows.insert($0, Rows.Regulation(id: 2, uniqueKey: "b", speed: 120)) }
        rows.assertAccepted("key 64") { try rows.insert($0, Rows.Regulation(id: 3, uniqueKey: String(repeating: "k", count: 64))) }
    }

    /// 速度と種類の組・一方通行と並びの組が合わない行は拒否されます。
    ///
    /// 責務: 速度の区間・区域は速度が必須、他の種類は速度なし、一方通行だけが並びを持つことを確認します。
    func testKindSpeedAndOneWayPairingChecks() throws {
        let rows = try Rows()
        try rows.queue.write { try rows.insert($0, Rows.Dataset()) }

        rows.assertRejected("section without speed") { try rows.insert($0, Rows.Regulation(speed: nil)) }
        rows.assertRejected("zone without speed") { try rows.insert($0, Rows.Regulation(kind: "speedLimitZone", speed: nil)) }
        for kind in ["stop", "slowDown", "oneWay", "speedLimitVariableSection"] {
            rows.assertRejected("\(kind) with speed") { try rows.insert($0, Rows.Regulation(kind: kind, speed: 30, oneWay: kind == "oneWay" ? 1 : nil)) }
        }
        rows.assertRejected("oneWay without order") { try rows.insert($0, Rows.Regulation(kind: "oneWay", speed: nil, oneWay: nil)) }
        rows.assertRejected("stop with order") { try rows.insert($0, Rows.Regulation(kind: "stop", speed: nil, oneWay: 1)) }
        rows.assertRejected("section with order") { try rows.insert($0, Rows.Regulation(oneWay: 1)) }
        rows.assertRejected("order 3") { try rows.insert($0, Rows.Regulation(kind: "oneWay", speed: nil, oneWay: 3)) }
    }

    /// すべての種類と拒否理由の rawValue が、CHECK に受け入れられます。
    ///
    /// 責務: `RoadRegulationKind` と `RoadRegulationRowRejection` の全 case を、整合する値で挿入できることを確認します。
    func testEveryKindAndRejectionReasonIsAccepted() throws {
        let rows = try Rows()
        try rows.queue.write { try rows.insert($0, Rows.Dataset()) }

        for (index, kind) in RoadRegulationKind.allCases.enumerated() {
            let hasSpeed = kind == .speedLimitSection || kind == .speedLimitZone
            let regulation = Rows.Regulation(
                id: Int64(index + 1), uniqueKey: "k\(index)", kind: kind.rawValue, speed: hasSpeed ? 40 : nil, oneWay: kind == .oneWay ? 2 : nil
            )
            rows.assertAccepted(kind.rawValue) { try rows.insert($0, regulation) }
        }
        for reason in RoadRegulationRowRejection.allCases {
            rows.assertAccepted(reason.rawValue) { try rows.insertRejection($0, reason: reason.rawValue) }
        }
        rows.assertRejected("unknown reason") { try rows.insertRejection($0, reason: "somethingElse") }
        rows.assertRejected("count 0") { try rows.insertRejection($0, reason: "x", count: 0) }
    }

    /// 同じ版でユニークキーが重複する行は拒否され、別の版なら許されます。親の無い行は外部キー違反です。
    ///
    /// 責務: UNIQUE(datasetID, uniqueKey)・升目の主キー・3つの子の表の外部キーを確認します。
    func testUniqueKeyPrimaryKeyAndForeignKeyViolations() throws {
        let rows = try Rows()
        try rows.queue.write {
            try rows.insert($0, Rows.Dataset(id: datasetA, prefecture: 47))
            try rows.insert($0, Rows.Dataset(id: datasetB, prefecture: 13))
            try rows.insert($0, Rows.Regulation(id: 1, dataset: datasetA))
            try rows.insertCell($0)
            try rows.insertRejection($0)
        }

        rows.assertRejected("duplicate key", code: .SQLITE_CONSTRAINT_UNIQUE) { try rows.insert($0, Rows.Regulation(id: 2, dataset: datasetA)) }
        rows.assertAccepted("same key other dataset") { try rows.insert($0, Rows.Regulation(id: 3, dataset: datasetB)) }
        rows.assertRejected("duplicate cell", code: .SQLITE_CONSTRAINT_PRIMARYKEY) { try rows.insertCell($0) }
        rows.assertRejected("duplicate rejection", code: .SQLITE_CONSTRAINT_PRIMARYKEY) { try rows.insertRejection($0) }
        let missing = "00000000-0000-0000-0000-00000000ffff"
        rows.assertRejected("regulation parent", code: .SQLITE_CONSTRAINT_FOREIGNKEY) { try rows.insert($0, Rows.Regulation(id: 9, dataset: missing)) }
        rows.assertRejected("cell parent", code: .SQLITE_CONSTRAINT_FOREIGNKEY) { try rows.insertCell($0, dataset: missing) }
        let reason = RoadRegulationRowRejection.invalidSpeed.rawValue
        rows.assertRejected("rejection parent", code: .SQLITE_CONSTRAINT_FOREIGNKEY) { try rows.insertRejection($0, dataset: missing, reason: reason) }
    }

    /// 升目は、存在しない規制の id でも入ります(規制への外部キーは付けない設計)。
    ///
    /// 責務: 整合を repository が守る前提で、表の側は規制の存在を検査しないことを確認します。
    func testCellDoesNotRequireExistingRegulation() throws {
        let rows = try Rows()
        try rows.queue.write { try rows.insert($0, Rows.Dataset()) }

        rows.assertAccepted("orphan cell") { try rows.insertCell($0, cell: 5, regulation: 999) }
    }

    /// 版を削除すると、規制・升目・拒否件数の行も消え、他の版の行は残ります。
    ///
    /// 責務: ON DELETE CASCADE の実際の動作を確認します。
    func testDeletingDatasetCascadesToChildren() throws {
        let rows = try Rows()
        try rows.queue.write {
            try rows.insert($0, Rows.Dataset(id: datasetA, prefecture: 47))
            try rows.insert($0, Rows.Dataset(id: datasetB, prefecture: 13))
            for dataset in [datasetA, datasetB] {
                try rows.insert($0, Rows.Regulation(id: dataset == datasetA ? 1 : 2, dataset: dataset))
                try rows.insertCell($0, dataset: dataset, regulation: dataset == datasetA ? 1 : 2)
                try rows.insertRejection($0, dataset: dataset)
            }
        }

        try rows.queue.write { try $0.execute(sql: "DELETE FROM road_regulation_datasets WHERE id = ?", arguments: [datasetA]) }

        for table in ["road_regulations", "road_regulation_cells", "road_regulation_dataset_rejections"] {
            let remaining = try rows.queue.read { try String.fetchAll($0, sql: "SELECT datasetID FROM \(table)") }
            XCTAssertEqual(remaining, [datasetB], table)
        }
    }
}
