import Foundation
import XCTest
@testable import ProjectZD8

/// 対応PIDビットマップの問い合わせから、ECUが対応を返した標準PIDを求めることを検証します。
@MainActor
final class DiscoverSupportedStandardPIDsUseCaseTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fake = BitmapOBDPIDTelemetryFake

    /// 続きのビットが無ければ PID 00 だけを問い合わせ、立っているビットのPIDを返します。
    ///
    /// 責務: 1つ目のビットマップの解釈と、問い合わせの打ち切りを確認します。
    func testSingleBitmapReturnsSupportedPIDs() async throws {
        let telemetry = Fake(bitmaps: [0x00: Fake.bitmap(supporting: [0x01, 0x0C, 0x0D, 0x1F], base: 0x00, continues: false)])

        let supported = try await discover(telemetry)

        XCTAssertEqual(supported.map(\.pid), [0x01, 0x0C, 0x0D, 0x1F])
        XCTAssertEqual(supported.map(\.service), [0x01, 0x01, 0x01, 0x01])
        XCTAssertEqual(telemetry.queriedPIDs, [0x00])
    }

    /// 続きのビットが立っていれば次のビットマップを問い合わせ、ビットマップ用PIDは結果に含めません。
    ///
    /// 責務: 2つのビットマップの連結と、PID 20 の除外を確認します。
    func testContinuationQueriesNextBitmapAndExcludesBitmapPIDs() async throws {
        let telemetry = Fake(bitmaps: [
            0x00: Fake.bitmap(supporting: [0x0C], base: 0x00, continues: true),
            0x20: Fake.bitmap(supporting: [0x21, 0x31], base: 0x20, continues: false)
        ])

        let supported = try await discover(telemetry)

        XCTAssertEqual(supported.map(\.pid), [0x0C, 0x21, 0x31])
        XCTAssertEqual(telemetry.queriedPIDs, [0x00, 0x20])
    }

    /// すべてのビットマップが続きを示しても、PID E0 で問い合わせを止め、0xFF を超えるPIDを作りません。
    ///
    /// 責務: 問い合わせの上限(8回)と、最後のビットマップの位置32の扱いを確認します。
    func testStopsAtLastBitmap() async throws {
        var bitmaps: [UInt8: [UInt8]] = [:]
        for base in stride(from: 0x00, through: 0xE0, by: 0x20) {
            bitmaps[UInt8(base)] = Fake.bitmap(supporting: [UInt8(base + 1)], base: UInt8(base), continues: true)
        }
        let telemetry = Fake(bitmaps: bitmaps)

        let supported = try await discover(telemetry)

        XCTAssertEqual(telemetry.queriedPIDs, [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0])
        XCTAssertEqual(supported.map(\.pid), [0x01, 0x21, 0x41, 0x61, 0x81, 0xA1, 0xC1, 0xE1])
    }

    /// 対応ビットが1つも無ければ空を返します。
    ///
    /// 責務: 0件の探索結果をそのまま返すこと(空かどうかの扱いは取得準備が決める)を確認します。
    func testEmptyBitmapReturnsNoPIDs() async throws {
        let supported = try await discover(Fake(bitmaps: [0x00: [0, 0, 0, 0]]))

        XCTAssertEqual(supported, [])
    }

    /// ビットマップの応答が無い、または4バイト未満なら車両無応答で失敗します。
    ///
    /// 責務: 応答欠落と短い応答を、空の成功にせず失敗にすることを確認します。
    func testMissingOrShortBitmapThrowsNoVehicleResponse() async {
        let cases: [[UInt8: [UInt8]]] = [
            [:],
            [0x00: [0xFF, 0xFF, 0xFF]],
            [0x00: Fake.bitmap(supporting: [0x0C], base: 0x00, continues: true)]
        ]
        for bitmaps in cases {
            do {
                _ = try await discover(Fake(bitmaps: bitmaps))
                XCTFail("応答が不足しているのに成功しました: \(bitmaps)")
            } catch {
                XCTAssertEqual(error as? OBDPIDTelemetryError, .noVehicleResponse)
            }
        }
    }

    /// 取得境界の失敗はそのまま送出します。
    ///
    /// 責務: 通信の失敗を握りつぶさないことを確認します。
    func testTelemetryFailurePropagates() async {
        do {
            _ = try await discover(Fake(bitmaps: [:], failure: OBDPIDTelemetryError.connectionLost))
            XCTFail("取得境界の失敗なのに成功しました")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .connectionLost)
        }
    }

    /// テスト終端で探索します。
    ///
    /// 責務: 指定のフェイクで対応PIDを探索します。
    /// - Parameter telemetry: 取得境界のフェイク。
    /// - Returns: 対応PID。
    /// - Throws: 探索の失敗。
    private func discover(_ telemetry: Fake) async throws -> [OBDPIDRequest] {
        try await DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry).execute(using: LiveTelemetryTestDefinitions.endpoint)
    }
}
