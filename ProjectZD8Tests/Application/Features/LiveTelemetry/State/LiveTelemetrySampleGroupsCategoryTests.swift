import XCTest
@testable import ProjectZD8

/// 分類の表示順・分類内の抽出・代表値・選択中の分類の補正の規則を検証します。
@MainActor
final class LiveTelemetrySampleGroupsCategoryTests: XCTestCase {
    private typealias Fixture = LiveTelemetryPanelTestFixture

    private let rpm = Fixture.sample(pid: 0x0C)
    private let engineLoad = Fixture.sample(pid: 0x04)
    private let coolant = Fixture.sample(pid: 0x05)
    private let intakeTemperature = Fixture.sample(pid: 0x0F)
    private let speed = Fixture.sample(pid: 0x0D)
    private let pidSupport = Fixture.sample(pid: 0x01)

    /// 分類は取得順ではなく分類の定義順で、サンプルの無い分類を除きます。
    ///
    /// 責務: `availableCategories` の順序と空分類の除外を確かめます。
    func testAvailableCategoriesFollowDefinitionOrderAndSkipEmpty() {
        let groups = LiveTelemetrySampleGroups(samples: [pidSupport, speed, coolant, rpm])

        XCTAssertEqual(groups.availableCategories, [.engine, .temperature, .driving, .diagnostics])
    }

    /// サンプルが無ければ分類も空です。
    ///
    /// 責務: 空入力の境界を確かめます。
    func testAvailableCategoriesAreEmptyWithoutSamples() {
        XCTAssertEqual(LiveTelemetrySampleGroups(samples: []).availableCategories, [])
    }

    /// 分類内のサンプルは取得順を保ち、該当が無い分類は空です。
    ///
    /// 責務: `samples(in:)` の抽出・順序・空を確かめます。
    func testSamplesInCategoryKeepOrder() {
        let groups = LiveTelemetrySampleGroups(samples: [rpm, coolant, engineLoad, intakeTemperature])

        XCTAssertEqual(groups.samples(in: .engine), [rpm, engineLoad])
        XCTAssertEqual(groups.samples(in: .temperature), [coolant, intakeTemperature])
        XCTAssertEqual(groups.samples(in: .fuelAndAir), [])
    }

    /// 代表値は分類の代表リクエストに一致するものを、分類内の先頭より優先します。
    ///
    /// 責務: 代表リクエストが分類内の2件目以降にある時の選択を確かめます。
    func testRepresentativeSamplePrefersRepresentativeRequest() {
        let groups = LiveTelemetrySampleGroups(samples: [engineLoad, intakeTemperature, rpm, coolant])

        XCTAssertEqual(groups.representativeSample(in: .engine), rpm)
        XCTAssertEqual(groups.representativeSample(in: .temperature), coolant)
    }

    /// 代表リクエストが無い分類は分類内の先頭を代表値にします。
    ///
    /// 責務: 代表リクエストなしの時の選択を確かめます。
    func testRepresentativeSampleFallsBackToFirstInCategory() {
        let groups = LiveTelemetrySampleGroups(samples: [coolant, intakeTemperature, engineLoad])

        XCTAssertEqual(groups.representativeSample(in: .engine), engineLoad)
    }

    /// サンプルの無い分類には代表値がありません。
    ///
    /// 責務: 空分類で nil を確かめます。
    func testRepresentativeSampleIsNilForEmptyCategory() {
        let groups = LiveTelemetrySampleGroups(samples: [rpm])

        XCTAssertNil(groups.representativeSample(in: .driving))
    }

    /// 選択中の分類にサンプルがあれば、そのまま使います。
    ///
    /// 責務: `resolvedCategory` で選択が available にある分岐を確かめます。
    func testResolvedCategoryKeepsAvailableSelection() {
        let groups = LiveTelemetrySampleGroups(samples: [rpm, speed])

        XCTAssertEqual(groups.resolvedCategory(.driving), .driving)
    }

    /// 選択中の分類にサンプルが無ければ、表示できる先頭の分類に替えます。
    ///
    /// 責務: `resolvedCategory` で available の先頭へ替える分岐を確かめます。
    func testResolvedCategoryFallsBackToFirstAvailable() {
        let groups = LiveTelemetrySampleGroups(samples: [speed, coolant])

        XCTAssertEqual(groups.resolvedCategory(.engine), .temperature)
    }

    /// 表示できる分類が無ければ、選択中の分類をそのまま返します。
    ///
    /// 責務: `resolvedCategory` で available が空の分岐を確かめます。
    func testResolvedCategoryKeepsSelectionWhenNothingAvailable() {
        let groups = LiveTelemetrySampleGroups(samples: [])

        XCTAssertEqual(groups.resolvedCategory(.diagnostics), .diagnostics)
    }
}
