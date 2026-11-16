import Foundation
import XCTest
@testable import ProjectZD8

/// 保存済みプライマリー設定がある時の設定画面アダプター行の説明を検証します。
@MainActor
final class AdapterSlotSettingsDescriptionSavedPreferenceTests: XCTestCase {
    /// 保存済み設定があれば、探索で未検出でもプライマリーは保存名で選択済みとして説明します。
    ///
    /// 責務: 再起動後に探索結果が空でも「未選択」にならないことを確認します。
    func testSavedPrimaryWithoutDetectionReturnsSavedName() {
        let description = AdapterSlotSettingsDescription(
            slot: .primary,
            selectedAdapters: [:],
            defaultAdapterPreference: preference(named: "OBDLink CX")
        )

        XCTAssertEqual(description, .adapterName("OBDLink CX"))
    }

    /// 保存済み設定の名前は文言キーや書式文字列に見える名前でもそのまま返します。
    ///
    /// 責務: 保存名をローカライズキーとして扱わないことを確認します。
    func testSavedPrimaryNameIsVerbatim() {
        for name in [AdapterSlotSettingsDescription.notSelectedKey, "ELM327 %@ 100%"] {
            let description = AdapterSlotSettingsDescription(
                slot: .primary,
                selectedAdapters: [:],
                defaultAdapterPreference: preference(named: name)
            )

            XCTAssertEqual(description, .adapterName(name), "名前: \(name)")
        }
    }

    /// 保存済み設定が無ければ、プライマリーは未選択として説明します。
    ///
    /// 責務: 設定が無い時だけ未選択の文言キーになることを確認します。
    func testNoSavedPreferenceReturnsNotSelectedKey() {
        let description = AdapterSlotSettingsDescription(
            slot: .primary,
            selectedAdapters: [:],
            defaultAdapterPreference: nil
        )

        XCTAssertEqual(description, .localizationKey(AdapterSlotSettingsDescription.notSelectedKey))
    }

    /// 保存済みのプライマリー設定はセカンダリー行の説明へ影響しません。
    ///
    /// 責務: プライマリー設定がセカンダリーを選択済みに見せないことを確認します。
    func testSavedPrimaryDoesNotAffectSecondary() {
        let description = AdapterSlotSettingsDescription(
            slot: .secondary,
            selectedAdapters: [:],
            defaultAdapterPreference: preference(named: "OBDLink CX")
        )

        XCTAssertEqual(description, .localizationKey(AdapterSlotSettingsDescription.notSelectedKey))
    }

    /// 指定した表示名の保存済み設定を作ります。
    ///
    /// 責務: 表示名だけを変えたテスト用の保存済み設定を返します。
    /// - Parameter name: 保存済み設定の表示名。
    /// - Returns: 保存済みデフォルトアダプター設定。
    private func preference(named name: String) -> DefaultAdapterPreference {
        DefaultAdapterPreference(
            adapterID: "saved",
            transportMode: .bluetooth,
            displayName: name,
            systemIdentifier: "saved"
        )
    }
}
