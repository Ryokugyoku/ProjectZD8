import Foundation
import XCTest
@testable import ProjectZD8

/// 正応答payloadの評価が、値の分類と表示用観測を仕様どおりに返すことを検証します。
final class OBDPIDPayloadDecoderTests: XCTestCase {
    /// 観測日時の固定値です。
    private let observedAt = Date(timeIntervalSince1970: 42)

    /// 範囲内の値は有効値として、定義の表示metadata付きの観測を返します。
    ///
    /// 責務: 有効値の分類と観測の全項目を確認します。
    func testValueInsideRangeIsValidWithSample() {
        let definition = makeDefinition(minimum: 0, maximum: 100, vehicleModelCode: "ZD8")

        let decoding = OBDPIDPayloadDecoder().decode([50], definition: definition, observedAt: observedAt)

        XCTAssertEqual(decoding.valueOutcome, .decodedValid)
        XCTAssertEqual(decoding.sample, OBDPIDSample(
            request: OBDPIDRequest(service: 0x01, pid: 0x0C),
            nameKey: "test.name",
            value: 50,
            unit: "unit",
            vehicleModelCode: "ZD8",
            observedAt: observedAt,
            summaryKey: "test.summary",
            highValueKey: "test.high",
            lowValueKey: "test.low",
            correlationKey: "test.correlation"
        ))
    }

    /// 範囲の両端ちょうどの値は有効値です。
    ///
    /// 責務: 下限・上限を含む閉区間として判定することを確認します。
    func testRangeBoundsAreInclusive() {
        let definition = makeDefinition(minimum: 10, maximum: 100)

        let lower = OBDPIDPayloadDecoder().decode([10], definition: definition, observedAt: observedAt)
        let upper = OBDPIDPayloadDecoder().decode([100], definition: definition, observedAt: observedAt)

        XCTAssertEqual(lower.valueOutcome, .decodedValid)
        XCTAssertEqual(upper.valueOutcome, .decodedValid)
    }

    /// 範囲外の有限値は不正値に分類しつつ、観測は返します。
    ///
    /// 責務: 上限+1と下限-1が不正値になり、値を捨てずに観測へ残すことを確認します。
    func testFiniteValueOutsideRangeIsInvalidButKeepsSample() {
        let definition = makeDefinition(minimum: 10, maximum: 100)

        let above = OBDPIDPayloadDecoder().decode([101], definition: definition, observedAt: observedAt)
        let below = OBDPIDPayloadDecoder().decode([9], definition: definition, observedAt: observedAt)

        XCTAssertEqual(above.valueOutcome, .invalidValue)
        XCTAssertEqual(above.sample?.value, 101)
        XCTAssertEqual(below.valueOutcome, .invalidValue)
        XCTAssertEqual(below.sample?.value, 9)
    }

    /// 範囲を宣言しない、または片側だけの定義は範囲判定をせず有効値です。
    ///
    /// 責務: 両端が揃わない範囲を判定に使わないことを確認します。
    func testMissingOrHalfRangeSkipsRangeCheck() {
        let cases: [(Double?, Double?)] = [(nil, nil), (200, nil), (nil, 1)]
        for (minimum, maximum) in cases {
            let definition = makeDefinition(minimum: minimum, maximum: maximum)

            let decoding = OBDPIDPayloadDecoder().decode([50], definition: definition, observedAt: observedAt)

            XCTAssertEqual(decoding.valueOutcome, .decodedValid, "\(String(describing: minimum)) \(String(describing: maximum))")
            XCTAssertEqual(decoding.sample?.value, 50)
        }
    }

    /// バイト数不足・不正な式・ゼロ除算はデコード失敗で、観測を返しません。
    ///
    /// 責務: 数式評価の失敗を正応答消失や不正値と混同しないことを確認します。
    func testEvaluationFailuresAreDecodeFailureWithoutSample() {
        let cases: [(OBDPIDDefinition, [UInt8])] = [
            (makeDefinition(requiredByteCount: 2, formula: "A + B"), [1]),
            (makeDefinition(formula: "A +"), [1]),
            (makeDefinition(requiredByteCount: 2, formula: "A / B"), [1, 0])
        ]
        for (definition, payload) in cases {
            let decoding = OBDPIDPayloadDecoder().decode(payload, definition: definition, observedAt: observedAt)

            XCTAssertEqual(decoding.valueOutcome, .decodeFailure, definition.formula ?? "")
            XCTAssertNil(decoding.sample)
        }
    }

    /// 必要バイト数ちょうどのpayloadはデコードできます。
    ///
    /// 責務: バイト数不足の境界で、ちょうどの件数を失敗にしないことを確認します。
    func testPayloadWithExactRequiredBytesDecodes() {
        let definition = makeDefinition(requiredByteCount: 2, formula: "A * 256 + B", maximum: 70_000)

        let decoding = OBDPIDPayloadDecoder().decode([1, 2], definition: definition, observedAt: observedAt)

        XCTAssertEqual(decoding.valueOutcome, .decodedValid)
        XCTAssertEqual(decoding.sample?.value, 258)
    }

    /// 非有限の結果は不正値で、観測を返しません。
    ///
    /// 責務: 無限大になる式を表示へ流さないことを確認します。
    func testNonFiniteResultIsInvalidWithoutSample() {
        let formula = Array(repeating: "A", count: 140).joined(separator: " * ")
        let definition = makeDefinition(formula: formula, minimum: nil, maximum: nil)

        let decoding = OBDPIDPayloadDecoder().decode([255], definition: definition, observedAt: observedAt)

        XCTAssertEqual(decoding.valueOutcome, .invalidValue)
        XCTAssertNil(decoding.sample)
    }

    /// テスト用のPID定義を生成します。
    ///
    /// 責務: 式・必要バイト数・範囲・型式コードだけを差し替えた Service 01 PID 0x0C 定義を返します。
    /// - Parameters:
    ///   - requiredByteCount: 必要バイト数。
    ///   - formula: 評価する式。
    ///   - minimum: 範囲の下限。
    ///   - maximum: 範囲の上限。
    ///   - vehicleModelCode: 型式コード。
    /// - Returns: 表示metadataを持つ定義。
    private func makeDefinition(
        requiredByteCount: Int = 1,
        formula: String = "A",
        minimum: Double? = 0,
        maximum: Double? = 255,
        vehicleModelCode: String? = nil
    ) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01, pid: 0x0C, vehicleModelCode: vehicleModelCode, nameKey: "test.name",
            requiredByteCount: requiredByteCount, formula: formula, unit: "unit",
            minimumValue: minimum, maximumValue: maximum, sourceURI: "test://pid", revision: 1,
            summaryKey: "test.summary", highValueKey: "test.high", lowValueKey: "test.low",
            correlationKey: "test.correlation"
        )
    }
}
