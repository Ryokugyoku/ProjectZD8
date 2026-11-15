import Foundation
import XCTest
@testable import ProjectZD8

/// `AcquisitionManifestContinuationPolicy.canContinue` が、アダプター判定結果だけを比較から除き、
/// それ以外の8項目(各契約version・アプリversion・要求順・PID定義・取得platform)の違いで続行を拒むことを検証します。
final class AcquisitionManifestContinuationPolicyTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias F = AcquisitionManifestContinuationFixture
    /// 検証対象です。
    private let policy = AcquisitionManifestContinuationPolicy()

    /// 全項目が同じなら、判定結果が両方 `nil` でも両方同じ値でも続行できます。
    ///
    /// 責務: 完全一致の基準ケースが `true` になることを確認します。
    func testIdenticalManifestsCanContinue() {
        XCTAssertTrue(policy.canContinue(stored: F.manifest(), requested: F.manifest()))
        XCTAssertTrue(policy.canContinue(stored: F.manifest(probe: F.stnFrames), requested: F.manifest(probe: F.stnFrames)))
    }

    /// 保存済みだけが判定結果を持つ場合(常駐リンクで始め、手動接続で続ける)は続行できます。
    ///
    /// 責務: 判定結果のあり→なしを比較から除くことを確認します。
    func testStoredProbeOnlyCanContinue() {
        XCTAssertTrue(policy.canContinue(stored: F.manifest(probe: F.stnFrames), requested: F.manifest(probe: nil)))
    }

    /// 要求側だけが判定結果を持つ場合(手動接続で始め、常駐リンクで続ける)は続行できます。
    ///
    /// 責務: 判定結果のなし→ありを比較から除くことを確認します。
    func testRequestedProbeOnlyCanContinue() {
        XCTAssertTrue(policy.canContinue(stored: F.manifest(probe: nil), requested: F.manifest(probe: F.stnFrames)))
    }

    /// 判定結果のチップ種別だけ、またはATMA結果だけが違っても続行できます。
    ///
    /// 責務: 判定結果の各項目(チップ種別、ATMA結果の値違い、ATMA結果のあり/なし)を比較から除くことを確認します。
    func testProbeFieldDifferencesCanContinue() {
        let variants = [
            AcquisitionAdapterProbeEvidence(chipFamily: .elm327Clone, monitorProbeOutcome: .framesReceived),
            AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .silent),
            AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: nil)
        ]
        for variant in variants {
            XCTAssertTrue(
                policy.canContinue(stored: F.manifest(probe: F.stnFrames), requested: F.manifest(probe: variant)),
                "\(variant)"
            )
        }
    }

    /// 契約versionのどれか1つでも違えば続行できません。
    ///
    /// 責務: manifest・schema・polling policy・model入力の各versionを1つずつ変えて `false` になることを確認します。
    func testContractVersionDifferenceCannotContinue() {
        let base = F.manifest()
        XCTAssertFalse(policy.canContinue(stored: base, requested: F.manifest(manifestVersion: 2)), "manifest")
        XCTAssertFalse(policy.canContinue(stored: base, requested: F.manifest(schemaVersion: 2)), "schema")
        XCTAssertFalse(policy.canContinue(stored: base, requested: F.manifest(pollingVersion: 3)), "polling")
        XCTAssertFalse(policy.canContinue(stored: base, requested: F.manifest(modelVersion: 2)), "model")
    }

    /// アプリのmarketing versionまたはbuild versionが違えば続行できません。
    ///
    /// 責務: アプリversionの2項目をそれぞれ変えて `false` になることを確認します。
    func testApplicationVersionDifferenceCannotContinue() throws {
        let marketing = try AcquisitionApplicationVersion(marketingVersion: "fixture-1.1", buildVersion: "fixture-100")
        let build = try AcquisitionApplicationVersion(marketingVersion: "fixture-1.0", buildVersion: "fixture-101")

        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: F.manifest(applicationVersion: marketing)))
        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: F.manifest(applicationVersion: build)))
    }

    /// 要求順が入れ替わる、または件数が違えば続行できません。
    ///
    /// 責務: 同じPID集合でも順序違い、および部分集合への変化で `false` になることを確認します。
    func testRequestOrderDifferenceCannotContinue() {
        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: F.manifest(requests: [F.secondRequest, F.firstRequest])))
        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: F.manifest(requests: [F.firstRequest])))
    }

    /// PID定義の件数・中身・並びのどれかが違えば続行できません。
    ///
    /// 責務: 定義1件の削除、revision違い、並びの入れ替えで `false` になることを確認します。
    func testPIDDefinitionDifferenceCannotContinue() {
        let first = F.definition(F.firstRequest)
        let second = F.definition(F.secondRequest)
        let fewer = F.manifest(requests: [F.firstRequest], definitions: [first])
        let revised = F.manifest(definitions: [first, F.definition(F.secondRequest, revision: 2)])
        let reordered = F.manifest(definitions: [second, first])

        XCTAssertFalse(policy.canContinue(stored: F.manifest(requests: [F.firstRequest]), requested: fewer), "件数")
        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: revised), "中身")
        XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: reordered), "並び")
    }

    /// 取得platformが違えば続行できません。
    ///
    /// 責務: macOSで保存したmanifestをiPhoneの取得で続けない(およびその逆)ことを確認します。
    func testPlatformDifferenceCannotContinue() {
        XCTAssertFalse(policy.canContinue(stored: F.manifest(platform: .macOS), requested: F.manifest(platform: .iPhone)))
        XCTAssertFalse(policy.canContinue(stored: F.manifest(platform: .iPhone), requested: F.manifest(platform: .macOS)))
    }

    /// 判定結果が違っていても、ほかの項目が1つでも違えば続行できません。
    ///
    /// 責務: 判定結果の除外が他項目の不一致を隠さないことを確認します。
    func testProbeDifferenceDoesNotMaskOtherDifference() {
        XCTAssertFalse(policy.canContinue(stored: F.manifest(probe: F.stnFrames), requested: F.manifest(manifestVersion: 2, probe: nil)))
        XCTAssertFalse(policy.canContinue(stored: F.manifest(probe: nil), requested: F.manifest(platform: .iPhone, probe: F.stnFrames)))
    }

    /// legacy欠落(`nil`)どうしは一致として続行できます。
    ///
    /// 責務: 欠落可能な全項目が両方 `nil` のmanifestで `true` になることを確認します。
    func testBothLegacyMissingValuesCanContinue() {
        let legacy = F.manifest(
            manifestVersion: nil, applicationVersion: nil, schemaVersion: nil, pollingVersion: nil,
            requests: nil, platform: nil, modelVersion: nil
        )

        XCTAssertTrue(policy.canContinue(stored: legacy, requested: legacy))
    }

    /// 欠落可能な項目の片方だけが `nil` なら続行できません。
    ///
    /// 責務: 欠落可能な7項目それぞれで、保存済みだけ `nil` の場合に `false` になることを確認します。
    func testOneSidedLegacyMissingValueCannotContinue() {
        let oneSided: [(String, ConnectionSessionAcquisitionManifest)] = [
            ("manifest", F.manifest(manifestVersion: nil)),
            ("application", F.manifest(applicationVersion: nil)),
            ("schema", F.manifest(schemaVersion: nil)),
            ("polling", F.manifest(pollingVersion: nil)),
            ("requests", F.manifest(requests: nil)),
            ("platform", F.manifest(platform: nil)),
            ("model", F.manifest(modelVersion: nil))
        ]
        for (label, stored) in oneSided {
            XCTAssertFalse(policy.canContinue(stored: stored, requested: F.manifest()), label)
            XCTAssertFalse(policy.canContinue(stored: F.manifest(), requested: stored), label)
        }
    }
}
