import XCTest
@testable import ProjectZD8

/// 車両エネルギー源の動力区分別整合規則を検証します。
final class VehicleEnergySourcePolicyTests: XCTestCase {
    /// ハイブリッドが保持する燃料と電力を正規化で失わないことを検証します。
    ///
    /// 責務: 複数の利用可能な既存エネルギー源が元の順序で保持されることを確認します。
    func testNormalizationPreservesMultipleValidHybridSources() {
        let sources = VehicleEnergySourcePolicy.normalizedSources(
            [.gasolineRegular, .electricity],
            for: .hybrid
        )

        XCTAssertEqual(sources, [.gasolineRegular, .electricity])
    }

    /// 動力区分に適合しない既存値だけを除外することを検証します。
    ///
    /// 責務: 利用可能値と不適合値が混在する入力から利用可能値だけを保持することを確認します。
    func testNormalizationRemovesOnlyUnavailableSources() {
        let sources = VehicleEnergySourcePolicy.normalizedSources(
            [.hydrogen, .gasolinePremium, .electricity],
            for: .plugInHybrid
        )

        XCTAssertEqual(sources, [.gasolinePremium, .electricity])
    }

    /// ハイブリッドに利用可能な既存値がない場合の既定値を検証します。
    ///
    /// 責務: 空になったハイブリッドのエネルギー源が電力1件で補完されることを確認します。
    func testNormalizationDefaultsHybridToElectricity() {
        let sources = VehicleEnergySourcePolicy.normalizedSources([.hydrogen], for: .hybrid)

        XCTAssertEqual(sources, [.electricity])
    }

    /// 編集開始時にPicker候補外の保存済み値も失わないことを検証します。
    ///
    /// 責務: 編集準備が既存のLPGとCNGを変更せず保持することを確認します。
    func testEditingPreparationPreservesExistingSourcesOutsidePickerCandidates() {
        let sources = VehicleEnergySourcePolicy.sourcesForEditing(
            [.lpg, .cng],
            powertrain: .combustion
        )

        XCTAssertEqual(sources, [.lpg, .cng])
    }
}
