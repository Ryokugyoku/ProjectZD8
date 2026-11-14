import XCTest
@testable import ProjectZD8

/// STI/ATI応答からのチップ種別判定を検証します。
@MainActor
final class OBDAdapterChipClassificationPolicyTests: XCTestCase {
    /// 検証対象のチップ判定Policyです。
    private let policy = OBDAdapterChipClassificationPolicy()

    /// 判定結果を返します。
    ///
    /// 責務: 3引数を判定へ渡す短縮です。
    private func classify(_ sti: String, _ ati: String, _ probe: Bool?) -> OBDAdapterChipFamily {
        policy.classify(stnIdentityResponse: sti, identityResponse: ati, extendedProbeAccepted: probe)
    }

    /// STN応答はプローブや ATI に関わらずstnです。
    ///
    /// 責務: STNで始まる行がstnになることを確認します。
    func testSTNIdentity() {
        for probe in [true, false, nil] as [Bool?] {
            XCTAssertEqual(classify("STN2120 v5.6.5", "ELM327 v1.5", probe), .stn)
            XCTAssertEqual(classify("STN2120 v5.6.5", "", probe), .stn)
        }
        XCTAssertEqual(classify("STI\rSTN2120 v5.6.5\r\r>", "ATI\rELM327 v1.5\r\r>", nil), .stn)
        XCTAssertEqual(classify("stn2120 v5.6.5", "garbage", nil), .stn)
        XCTAssertEqual(classify("  STN1170  ", "", nil), .stn)
    }

    /// ELM327 v1.5はクローンです。
    ///
    /// 責務: プローブ値に関わらずelm327Cloneになることを確認します。
    func testVersion15IsClone() {
        for probe in [true, false, nil] as [Bool?] {
            XCTAssertEqual(classify("?", "ELM327 v1.5", probe), .elm327Clone)
            XCTAssertEqual(classify("?\r\r>", "ATI\rELM327 v1.5\r\r>", probe), .elm327Clone)
            XCTAssertEqual(classify("?", "elm327 v1.5", probe), .elm327Clone)
        }
    }

    /// v1.5以外のバージョンはプローブで決まります。
    ///
    /// 責務: true→純正、false→クローン、nil→unknownを確認します。
    func testOtherVersionsDependOnProbe() {
        for version in ["v1.4b", "v2.1", "v1.5a"] {
            XCTAssertEqual(classify("?", "ELM327 \(version)", true), .elm327Genuine, version)
            XCTAssertEqual(classify("?", "ELM327 \(version)", false), .elm327Clone, version)
            XCTAssertEqual(classify("?", "ELM327 \(version)", nil), .unknown, version)
        }
        XCTAssertEqual(classify("STI\r?\r\r>", "ATI\rELM327 v2.1\r\r>", true), .elm327Genuine)
    }

    /// 判定できない入力はunknownです。
    ///
    /// 責務: STI/ATIが想定外の形式の場合にunknownになることを確認します。
    func testUnrecognizedInputIsUnknown() {
        XCTAssertEqual(classify("", "ELM327 v2.1", true), .unknown)
        XCTAssertEqual(classify("   ", "ELM327 v2.1", true), .unknown)
        XCTAssertEqual(classify("STI\r>", "ELM327 v2.1", true), .unknown)
        XCTAssertEqual(classify("OK", "ELM327 v2.1", true), .unknown)
        XCTAssertEqual(classify("?", "", true), .unknown)
        XCTAssertEqual(classify("?", "ATI\r>", true), .unknown)
        XCTAssertEqual(classify("?", "OBDLink SX", true), .unknown)
        XCTAssertEqual(classify("?", "ELM327 v", true), .unknown)
        XCTAssertEqual(classify("?", "ELM327 v ", false), .unknown)
        XCTAssertEqual(classify("", "", nil), .unknown)
    }

    /// 前後の空白・エコー・改行混在を正規化します。
    ///
    /// 責務: 行頭のエコー行や空行が無視されることを確認します。
    func testNormalization() {
        XCTAssertEqual(classify("  ?  ", "  ELM327 v1.5  ", nil), .elm327Clone)
        XCTAssertEqual(classify("\r\r?\r", "\r\rELM327 v2.1\r", true), .elm327Genuine)
        XCTAssertEqual(classify(">?", "> ELM327 v2.1", true), .elm327Genuine)
    }

    /// CRLF区切りの応答を行分割します。
    ///
    /// 責務: `\r\n`で区切られた応答でもエコー行を除いた最初の行が評価されることを確認します。
    func testCRLFLineSeparators() {
        XCTAssertEqual(classify("sti\r\n?\r\n>", "ati\r\nelm327 v1.5\r\n>", nil), .elm327Clone)
        XCTAssertEqual(classify("STI\r\nSTN2120 v5.6.5\r\n>", "", nil), .stn)
        XCTAssertTrue(policy.requiresExtendedProbe(stnIdentityResponse: "?\r\n>", identityResponse: "ATI\r\nELM327 v2.1\r\n>"))
    }

    /// 追加プローブが必要な入力を確認します。
    ///
    /// 責務: v1.5以外のELM327でSTIが`?`の時だけtrueになることを確認します。
    func testRequiresExtendedProbeTrueCases() {
        XCTAssertTrue(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "ELM327 v1.4b"))
        XCTAssertTrue(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "ELM327 v2.1"))
        XCTAssertTrue(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "ELM327 v1.5a"))
        XCTAssertTrue(
            policy.requiresExtendedProbe(stnIdentityResponse: "STI\r?\r\r>", identityResponse: "ATI\rELM327 v2.1\r\r>")
        )
    }

    /// 追加プローブが不要な入力を確認します。
    ///
    /// 責務: STN・v1.5・判定不能な入力でfalseになることを確認します。
    func testRequiresExtendedProbeFalseCases() {
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "STN2120 v5.6.5", identityResponse: "ELM327 v2.1"))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "ELM327 v1.5"))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "", identityResponse: "ELM327 v2.1"))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "OK", identityResponse: "ELM327 v2.1"))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: ""))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "ELM327 v"))
        XCTAssertFalse(policy.requiresExtendedProbe(stnIdentityResponse: "?", identityResponse: "OBDLink SX"))
    }
}
