import XCTest
@testable import ProjectZD8

/// 主要値と分類に対応する SF Symbol 名の規則を検証します。
@MainActor
final class LiveTelemetrySampleSymbolsTests: XCTestCase {
    /// 回転数(01 0C)は針のゲージの記号です。
    ///
    /// 責務: 回転数の分岐を確かめます。
    func testPrimarySymbolForEngineSpeed() {
        XCTAssertEqual(
            LiveTelemetrySampleSymbols.primarySymbol(for: OBDPIDRequest(service: 0x01, pid: 0x0C)),
            "gauge.with.dots.needle.67percent"
        )
    }

    /// 車速(01 0D)は道路の記号です。
    ///
    /// 責務: 車速の分岐を確かめます。
    func testPrimarySymbolForVehicleSpeed() {
        XCTAssertEqual(LiveTelemetrySampleSymbols.primarySymbol(for: OBDPIDRequest(service: 0x01, pid: 0x0D)), "road.lanes")
    }

    /// それ以外は、サービス番号だけが違う 0C / 0D も含めて波形の記号です。
    ///
    /// 責務: その他の分岐とサービス番号の境界を確かめます。
    func testPrimarySymbolForOtherRequests() {
        let requests = [
            OBDPIDRequest(service: 0x01, pid: 0x05),
            OBDPIDRequest(service: 0x22, pid: 0x0C),
            OBDPIDRequest(service: 0x22, pid: 0x0D)
        ]
        for request in requests {
            XCTAssertEqual(LiveTelemetrySampleSymbols.primarySymbol(for: request), "waveform.path.ecg", "\(request)")
        }
    }

    /// 5つの分類はそれぞれ固有の記号に対応します。
    ///
    /// 責務: `categorySymbol(for:)` の全分類を確かめます。
    func testCategorySymbolForEachCategory() {
        let expected: [OBDPIDCategory: String] = [
            .engine: "engine.combustion",
            .temperature: "thermometer.medium",
            .fuelAndAir: "wind",
            .driving: "steeringwheel",
            .diagnostics: "stethoscope"
        ]
        XCTAssertEqual(expected.count, OBDPIDCategory.allCases.count)
        for category in OBDPIDCategory.allCases {
            XCTAssertEqual(LiveTelemetrySampleSymbols.categorySymbol(for: category), expected[category], "\(category)")
        }
    }
}
