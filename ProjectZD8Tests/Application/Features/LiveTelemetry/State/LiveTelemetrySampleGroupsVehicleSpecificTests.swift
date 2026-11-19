import XCTest
@testable import ProjectZD8

/// 型式コードが nil でも空でもないサンプルだけを車種専用として扱う規則を検証します。
@MainActor
final class LiveTelemetrySampleGroupsVehicleSpecificTests: XCTestCase {
    private typealias Fixture = LiveTelemetryPanelTestFixture

    /// 型式コードが nil と空文字は車種専用ではなく、値があれば車種専用です。
    ///
    /// 責務: `isVehicleSpecific` の3分岐を確かめます。
    func testIsVehicleSpecific() {
        XCTAssertFalse(LiveTelemetrySampleGroups.isVehicleSpecific(Fixture.sample(pid: 0x05, modelCode: nil)))
        XCTAssertFalse(LiveTelemetrySampleGroups.isVehicleSpecific(Fixture.sample(pid: 0x05, modelCode: "")))
        XCTAssertTrue(LiveTelemetrySampleGroups.isVehicleSpecific(Fixture.sample(pid: 0x05, modelCode: "ZD8")))
    }

    /// 車種専用の一覧は nil と空文字を除き、取得順を保ちます。
    ///
    /// 責務: `vehicleSpecificSamples` の抽出と順序を確かめます。
    func testVehicleSpecificSamplesKeepOrderAndExcludeNilAndEmpty() {
        let first = Fixture.sample(pid: 0x40, service: 0x22, modelCode: "ZD8")
        let withoutCode = Fixture.sample(pid: 0x05, modelCode: nil)
        let emptyCode = Fixture.sample(pid: 0x41, service: 0x22, modelCode: "")
        let second = Fixture.sample(pid: 0x42, service: 0x22, modelCode: "ZD8")

        let groups = LiveTelemetrySampleGroups(samples: [first, withoutCode, emptyCode, second])

        XCTAssertEqual(groups.vehicleSpecificSamples, [first, second])
    }

    /// 車種専用が無ければ一覧は空で、型式コードも nil です。
    ///
    /// 責務: 空文字だけの時に対象なしになることを確かめます。
    func testNoVehicleSpecificSamples() {
        let groups = LiveTelemetrySampleGroups(samples: [
            Fixture.sample(pid: 0x05, modelCode: nil),
            Fixture.sample(pid: 0x41, service: 0x22, modelCode: "")
        ])

        XCTAssertEqual(groups.vehicleSpecificSamples, [])
        XCTAssertNil(groups.vehicleSpecificModelCode)
    }

    /// 型式コードは車種専用の先頭のものを使い、前にある空文字のサンプルは飛ばします。
    ///
    /// 責務: `vehicleSpecificModelCode` が車種専用の先頭から取られることを確かめます。
    func testVehicleSpecificModelCodeUsesFirstVehicleSpecificSample() {
        let groups = LiveTelemetrySampleGroups(samples: [
            Fixture.sample(pid: 0x41, service: 0x22, modelCode: ""),
            Fixture.sample(pid: 0x40, service: 0x22, modelCode: "ZD8"),
            Fixture.sample(pid: 0x42, service: 0x22, modelCode: "ZN6")
        ])

        XCTAssertEqual(groups.vehicleSpecificModelCode, "ZD8")
    }

    /// サンプルが無ければ車種専用も型式コードもありません。
    ///
    /// 責務: 空入力の境界を確かめます。
    func testEmptySamples() {
        let groups = LiveTelemetrySampleGroups(samples: [])

        XCTAssertEqual(groups.vehicleSpecificSamples, [])
        XCTAssertNil(groups.vehicleSpecificModelCode)
    }
}
