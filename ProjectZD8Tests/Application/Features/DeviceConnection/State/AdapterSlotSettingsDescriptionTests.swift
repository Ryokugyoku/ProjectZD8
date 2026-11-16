import Foundation
import XCTest
@testable import ProjectZD8

/// 設定画面のアダプター行の説明が、選択済みなら名前をそのまま、未選択なら文言キーを返すことを検証します。
@MainActor
final class AdapterSlotSettingsDescriptionTests: XCTestCase {
    /// 選択済みのスロットはアダプターの表示名を「そのまま表示する名前」として返します。
    ///
    /// 責務: 通常の名前が文言キーではなく名前として返ることを確認します。
    func testSelectedSlotReturnsAdapterNameVerbatim() {
        let description = AdapterSlotSettingsDescription(slot: .primary, selectedAdapters: [.primary: adapter(named: "OBDLink CX")])

        XCTAssertEqual(description, .adapterName("OBDLink CX"))
    }

    /// 翻訳キーと同じ文字列・`%` を含む文字列・空文字の名前も、文言キーではなく名前として返します。
    ///
    /// 責務: アダプター名をローカライズキーとして扱わない境界を確認します。
    func testSelectedSlotTreatsKeyLikeOrFormatOrEmptyNamesAsNames() {
        let names = [AdapterSlotSettingsDescription.notSelectedKey, "ELM327 %@ 100%", "%d", ""]

        for name in names {
            let description = AdapterSlotSettingsDescription(slot: .secondary, selectedAdapters: [.secondary: adapter(named: name)])

            XCTAssertEqual(description, .adapterName(name), "名前: \(name)")
        }
    }

    /// 何も選ばれていなければ、未選択の文言キーを返します。
    ///
    /// 責務: 未選択の時だけ文言キー `settings.adapter.not_selected` を返すことを確認します。
    func testUnselectedSlotReturnsNotSelectedKey() {
        for slot in AdapterConnectionRole.allCases {
            let description = AdapterSlotSettingsDescription(slot: slot, selectedAdapters: [:])

            XCTAssertEqual(description, .localizationKey("settings.adapter.not_selected"), "スロット: \(slot)")
        }
        XCTAssertEqual(AdapterSlotSettingsDescription.notSelectedKey, "settings.adapter.not_selected")
    }

    /// スロットごとに分岐し、別のスロットだけが選ばれていても未選択として扱います。
    ///
    /// 責務: 他スロットの選択を流用しないことを確認します。
    func testDescriptionDependsOnlyOnRequestedSlot() {
        let onlyPrimary: [AdapterConnectionRole: DiscoveredAdapter] = [.primary: adapter(named: "Primary")]
        let onlySecondary: [AdapterConnectionRole: DiscoveredAdapter] = [.secondary: adapter(named: "Secondary")]
        let both: [AdapterConnectionRole: DiscoveredAdapter] = [.primary: adapter(named: "Primary"), .secondary: adapter(named: "Secondary")]

        XCTAssertEqual(AdapterSlotSettingsDescription(slot: .secondary, selectedAdapters: onlyPrimary), .localizationKey("settings.adapter.not_selected"))
        XCTAssertEqual(AdapterSlotSettingsDescription(slot: .primary, selectedAdapters: onlySecondary), .localizationKey("settings.adapter.not_selected"))
        XCTAssertEqual(AdapterSlotSettingsDescription(slot: .primary, selectedAdapters: both), .adapterName("Primary"))
        XCTAssertEqual(AdapterSlotSettingsDescription(slot: .secondary, selectedAdapters: both), .adapterName("Secondary"))
    }

    /// 指定した表示名のアダプター候補を作ります。
    ///
    /// 責務: 表示名だけを変えたテスト用の検出結果を返します。
    /// - Parameter name: アダプターの表示名。
    /// - Returns: 検出したアダプター候補。
    private func adapter(named name: String) -> DiscoveredAdapter {
        DiscoveredAdapter(id: "adapter-\(name)", transportMode: .usb, displayName: name, systemIdentifier: "/dev/cu.test", isConnected: false)
    }
}
