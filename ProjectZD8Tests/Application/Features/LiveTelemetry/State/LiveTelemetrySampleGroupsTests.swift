import XCTest
@testable import ProjectZD8

/// 回転数(01 0C)→車速(01 0D)を優先し、残りを取得順で補って先頭2件にする主要2値の規則を検証します。
@MainActor
final class LiveTelemetrySampleGroupsTests: XCTestCase {
    private typealias Fixture = LiveTelemetryPanelTestFixture

    private let rpm = Fixture.sample(pid: 0x0C)
    private let speed = Fixture.sample(pid: 0x0D)
    private let coolant = Fixture.sample(pid: 0x05)
    private let intake = Fixture.sample(pid: 0x0F)
    private let maf = Fixture.sample(pid: 0x10)

    /// サンプルが無ければ主要2値も空です。
    ///
    /// 責務: 空入力の境界を確かめます。
    func testPrimarySamplesAreEmptyWithoutSamples() {
        XCTAssertEqual(LiveTelemetrySampleGroups(samples: []).primarySamples, [])
    }

    /// 1件だけなら、それが回転数でも重複させず1件のままです。
    ///
    /// 責務: 1件の入力で回転数を2度入れないことを確かめます。
    func testPrimarySamplesWithSingleSampleHasOneItem() {
        XCTAssertEqual(LiveTelemetrySampleGroups(samples: [rpm]).primarySamples, [rpm])
        XCTAssertEqual(LiveTelemetrySampleGroups(samples: [coolant]).primarySamples, [coolant])
    }

    /// 回転数だけがある時は、回転数の後に取得順で最初の別の値を置きます。
    ///
    /// 責務: 回転数が取得順の途中にあっても先頭へ出し、残りから補うことを確かめます。
    func testPrimarySamplesWithEngineSpeedOnly() {
        let groups = LiveTelemetrySampleGroups(samples: [coolant, rpm, intake])

        XCTAssertEqual(groups.primarySamples, [rpm, coolant])
    }

    /// 車速だけがある時は、車速の後に取得順で最初の別の値を置きます。
    ///
    /// 責務: 車速を先頭へ出し、残りから補うことを確かめます。
    func testPrimarySamplesWithVehicleSpeedOnly() {
        let groups = LiveTelemetrySampleGroups(samples: [coolant, intake, speed])

        XCTAssertEqual(groups.primarySamples, [speed, coolant])
    }

    /// 回転数と車速の両方がある時は、その2件だけを回転数→車速の順で返します。
    ///
    /// 責務: 両方が他の値の後ろにある時に2件を優先することを確かめます。
    func testPrimarySamplesWithBothPreferred() {
        let groups = LiveTelemetrySampleGroups(samples: [coolant, rpm, intake, speed])

        XCTAssertEqual(groups.primarySamples, [rpm, speed])
    }

    /// 取得順が車速→回転数でも、主要2値は回転数→車速の順です。
    ///
    /// 責務: 優先の順序が取得順に依存しないことを確かめます。
    func testPrimarySamplesOrderEngineSpeedBeforeVehicleSpeed() {
        let groups = LiveTelemetrySampleGroups(samples: [speed, rpm])

        XCTAssertEqual(groups.primarySamples, [rpm, speed])
    }

    /// どちらも無い時は取得順の先頭2件です。
    ///
    /// 責務: 3件以上から先頭2件に切り詰めることを確かめます。
    func testPrimarySamplesWithoutPreferredUseFirstTwo() {
        let groups = LiveTelemetrySampleGroups(samples: [maf, coolant, intake])

        XCTAssertEqual(groups.primarySamples, [maf, coolant])
    }

    /// サービス 01 以外の PID 0C / 0D は回転数・車速として優先しません。
    ///
    /// 責務: 優先の判定がサービス番号まで一致した時だけであることを確かめます。
    func testPrimarySamplesRequireServiceOne() {
        let otherServiceRPM = Fixture.sample(pid: 0x0C, service: 0x22)
        let otherServiceSpeed = Fixture.sample(pid: 0x0D, service: 0x22)
        let groups = LiveTelemetrySampleGroups(samples: [coolant, otherServiceRPM, otherServiceSpeed, speed])

        XCTAssertEqual(groups.primarySamples, [speed, coolant])
    }
}
