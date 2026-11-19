import XCTest
@testable import ProjectZD8

/// PID 説明の見出しと4項目の並び・文言キーの規則を検証します。
@MainActor
final class LiveTelemetryPIDHelpContentTests: XCTestCase {
    private let sample = LiveTelemetryPanelTestFixture.sample(pid: 0x0C)

    /// 見出しはサンプルの名前キーです。
    ///
    /// 責務: `titleKey` を確かめます。
    func testTitleKeyIsSampleNameKey() {
        XCTAssertEqual(LiveTelemetryPIDHelpContent(sample: sample).titleKey, "test.pid.01.0C.name")
    }

    /// 行は概要→高い時→低い時→相関の順の4件で、本文はサンプルの対応するキーです。
    ///
    /// 責務: `rows` の件数・順序・見出しキー・本文キーを確かめます。
    func testRowsOrderAndKeys() {
        let rows = LiveTelemetryPIDHelpContent(sample: sample).rows

        XCTAssertEqual(rows.map(\.titleKey), [
            "telemetry.help.summary",
            "telemetry.help.high",
            "telemetry.help.low",
            "telemetry.help.correlation"
        ])
        XCTAssertEqual(rows.map(\.bodyKey), [
            "test.pid.01.0C.summary",
            "test.pid.01.0C.high",
            "test.pid.01.0C.low",
            "test.pid.01.0C.correlation"
        ])
    }

    /// 行の識別子は見出しキーと同じで、4行で重複しません。
    ///
    /// 責務: `Row.id` を確かめます。
    func testRowIDEqualsTitleKey() {
        let rows = LiveTelemetryPIDHelpContent(sample: sample).rows

        XCTAssertEqual(rows.map(\.id), rows.map(\.titleKey))
        XCTAssertEqual(Set(rows.map(\.id)).count, 4)
        XCTAssertEqual(LiveTelemetryPIDHelpContent.Row(titleKey: "a.title", bodyKey: "a.body").id, "a.title")
    }
}
