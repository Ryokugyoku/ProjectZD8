import Foundation
import XCTest
@testable import ProjectZD8

/// 標準PID探索の最後の範囲(PID E0 のビットマップ)の境界で、PID 0xFF を結果に含め、0xFF を超えるPIDを作らないことを検証します。
@MainActor
final class DiscoverSupportedStandardPIDsUseCaseLastRangeTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fake = BitmapOBDPIDTelemetryFake

    /// E0 のビットマップで 0xFF のビット(位置31)が立っていれば、0xFF を結果に含めます。
    ///
    /// 責務: 00〜C0 を続きのビットでたどり、最後の範囲の最大PIDが落ちないことを確認します。
    func testLastRangeIncludesPIDFF() async throws {
        let telemetry = Fake(bitmaps: chainedBitmaps(last: Fake.bitmap(supporting: [0xE1, 0xFF], base: 0xE0, continues: false)))

        let supported = try await discover(telemetry)

        XCTAssertEqual(supported.map(\.pid), [0xE1, 0xFF])
        XCTAssertEqual(telemetry.queriedPIDs.last, 0xE0)
    }

    /// E0 のビットマップで続きのビット(位置32)も立っていても、0x100 にあたるPIDを作らず、E0 より先を問い合わせません。
    ///
    /// 責務: 0xFF だけが立つ場合に 0xFF を含め、続きのビットを範囲外として扱うことを確認します。
    func testLastRangeContinuationBitDoesNotOverflowPastFF() async throws {
        let telemetry = Fake(bitmaps: chainedBitmaps(last: Fake.bitmap(supporting: [0xFF], base: 0xE0, continues: true)))

        let supported = try await discover(telemetry)

        XCTAssertEqual(supported.map(\.pid), [0xFF])
        XCTAssertEqual(telemetry.queriedPIDs, [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0])
    }

    /// 00〜C0 を対応PIDなし・続きありで並べ、最後に指定の E0 ビットマップを置いたビットマップ一式を返します。
    ///
    /// 責務: 最後の範囲だけを変えた探索の入力を作ります。
    /// - Parameter last: PID E0 のビットマップ。
    /// - Returns: 問い合わせPIDごとのビットマップ。
    private func chainedBitmaps(last: [UInt8]) -> [UInt8: [UInt8]] {
        var bitmaps: [UInt8: [UInt8]] = [0xE0: last]
        for base in stride(from: 0x00, through: 0xC0, by: 0x20) {
            bitmaps[UInt8(base)] = Fake.bitmap(supporting: [], base: UInt8(base), continues: true)
        }
        return bitmaps
    }

    /// 探索を実行します。
    ///
    /// 責務: 固定の終端で標準PIDの探索を行います。
    /// - Parameter telemetry: ビットマップを返すフェイク。
    /// - Returns: 対応を返した標準PID。
    /// - Throws: 探索の失敗。
    private func discover(_ telemetry: Fake) async throws -> [OBDPIDRequest] {
        try await DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry).execute(using: LiveTelemetryTestDefinitions.endpoint)
    }
}
