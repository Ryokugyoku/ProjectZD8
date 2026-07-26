#if os(iOS)
import SwiftUI

/// iPhoneで検出したBluetooth候補の接続情報を表示します。
struct IOSAdapterConnectionDetailView: View {
    /// 詳細を表示するBluetooth候補です。
    let adapter: DiscoveredAdapter

    /// 候補を設定する対象のアダプタースロットです。
    let slot: AdapterConnectionRole

    /// 候補が別の接続役割へ割り当て済みかどうかです。
    let hasAssignmentConflict: Bool

    /// 設定確定または設定中止をプレゼンテーションモデルへ通知します。
    let send: (IOSSettingsAction) -> Void

    /// 取得済みの完全な識別情報と設定判断操作を提供します。
    ///
    /// 責務: 1件のBLE候補について捏造のない接続情報と設定判断をiPhone向けに描画します。
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 0) {
                        detailRow("settings.adapter.details.transport", value: String(localized: "settings.adapter.transport.bluetooth"))
                        detailRow("ios.settings.adapter.details.display_name", value: adapter.displayName)
                        detailRow("ios.settings.adapter.details.peripheral_uuid", value: adapter.systemIdentifier, monospaced: true)
                        detailRow("ios.settings.adapter.details.connection_state", value: adapter.connectionState.localizedTitle)
                        detailRow(
                            "ios.settings.adapter.details.advertisement_local_name",
                            value: adapter.advertisementLocalName ?? unavailableValue
                        )
                        detailRow(
                            "ios.settings.adapter.details.manufacturer_data",
                            value: manufacturerDataValue
                        )
                        detailRow(
                            "ios.settings.adapter.details.service_uuids",
                            value: serviceIdentifiersValue,
                            monospaced: true
                        )
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    Text(slot.detailNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasAssignmentConflict {
                        Label("settings.adapter.details.assignment_conflict", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ios-adapter-assignment-conflict")
                    }

                    VStack(spacing: 10) {
                        Button("settings.adapter.details.confirm") {
                            send(.inspectedAdapterConfirmed)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint(Text(slot.confirmHint))
                        .accessibilityIdentifier("ios-adapter-confirm")

                        Button("settings.adapter.details.decline") {
                            send(.inspectedAdapterDeclined)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("ios-adapter-decline")
                    }
                }
                .padding(18)
            }
            .navigationTitle("settings.adapter.details.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("ios-adapter-connection-details")
    }

    /// システムから値を取得できない場合のローカライズ済み表示です。
    private var unavailableValue: String {
        String(localized: "settings.adapter.details.unknown")
    }

    /// Manufacturer Dataの有無を捏造せず表示する値です。
    private var manufacturerDataValue: String {
        guard let hasManufacturerData = adapter.hasManufacturerData else { return unavailableValue }
        return String(localized: hasManufacturerData
            ? "ios.settings.adapter.details.available"
            : "ios.settings.adapter.details.not_available")
    }

    /// BLE広告から取得したService UUIDを省略せず表示する値です。
    private var serviceIdentifiersValue: String {
        guard !adapter.bluetoothServiceIdentifiers.isEmpty else { return unavailableValue }
        return adapter.bluetoothServiceIdentifiers.joined(separator: "\n")
    }

    /// 1件の接続情報を省略しない値の行として生成します。
    ///
    /// 責務: 1項目のBluetooth接続情報を選択可能な完全値とラベルを持つ詳細行として描画します。
    /// - Parameters:
    ///   - title: 項目名を表すローカライズキー。
    ///   - value: システムから取得した値または明確な取得不能表示。
    ///   - monospaced: 値を等幅フォントで表示するかどうか。
    /// - Returns: 長いUUIDを折り返して選択できる詳細行。
    private func detailRow(
        _ title: LocalizedStringKey,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(monospaced ? .footnote.monospaced() : .body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.55)
        }
    }
}

/// iOSアダプタースロットに対応する詳細確認文言を提供します。
private extension AdapterConnectionRole {
    /// 候補設定の効果と非接続境界を示すローカライズキーです。
    var detailNotice: LocalizedStringKey {
        switch self {
        case .primary:
            "settings.adapter.details.notice"
        case .secondary:
            "ios.settings.adapter.details.secondary_notice"
        }
    }

    /// 確定操作の対象スロットと非接続境界を示すアクセシビリティヒントです。
    var confirmHint: LocalizedStringKey {
        switch self {
        case .primary:
            "ios.settings.adapter.details.confirm_hint"
        case .secondary:
            "ios.settings.adapter.details.secondary_confirm_hint"
        }
    }
}

/// Bluetooth候補の検出時接続状態に対応する表示名を提供します。
private extension DiscoveredAdapterConnectionState {
    /// 検出時接続状態を示すローカライズ済み名称です。
    var localizedTitle: String {
        switch self {
        case .disconnected:
            String(localized: "ios.settings.adapter.connection_state.disconnected")
        case .connecting:
            String(localized: "ios.settings.adapter.connection_state.connecting")
        case .connected:
            String(localized: "ios.settings.adapter.connection_state.connected")
        case .disconnecting:
            String(localized: "ios.settings.adapter.connection_state.disconnecting")
        case .unknown:
            String(localized: "settings.adapter.details.unknown")
        }
    }
}
#endif
