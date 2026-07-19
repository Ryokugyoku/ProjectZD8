#if os(macOS)
import SwiftUI

/// 検出したアダプター候補のシステム接続情報を表示します。
struct MacOSAdapterConnectionDetailView: View {
    /// 詳細を表示するアダプター候補です。
    let adapter: DiscoveredAdapter

    /// 同一候補が別の接続役割へ割り当て済みかどうかです。
    let hasAssignmentConflict: Bool

    /// 設定確定または設定中止をプレゼンテーションモデルへ通知します。
    let send: (MacOSSettingsAction) -> Void

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 候補の完全な識別情報と設定判断操作を提供します。
    ///
    /// 責務: 1件のアダプター候補について省略されていない接続情報と設定判断を描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 20 * metrics.scale) {
            HStack(spacing: 14 * metrics.scale) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 25 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                    Text("settings.adapter.details.title")
                        .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
                    Text(adapter.displayName)
                        .font(.system(size: 12 * metrics.scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            VStack(spacing: 0) {
                detailRow("settings.adapter.details.transport", value: adapter.transportMode.detailTitle)
                detailRow("settings.adapter.details.manufacturer", value: adapter.manufacturerName ?? String(localized: "settings.adapter.details.unknown"))
                detailRow("settings.adapter.details.product", value: adapter.productName ?? String(localized: "settings.adapter.details.unknown"))
                detailRow("settings.adapter.details.identifier", value: adapter.systemIdentifier, monospaced: true)

                if let serialNumber = adapter.serialNumber {
                    detailRow("settings.adapter.details.serial", value: serialNumber, monospaced: true)
                }
                if let vendorIdentifier = adapter.vendorIdentifier {
                    detailRow("settings.adapter.details.vendor_id", value: vendorIdentifier, monospaced: true)
                }
                if let productIdentifier = adapter.productIdentifier {
                    detailRow("settings.adapter.details.product_id", value: productIdentifier, monospaced: true)
                }
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }

            Text("settings.adapter.details.notice")
                .font(.system(size: 10.5 * metrics.scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasAssignmentConflict {
                Label("settings.adapter.details.assignment_conflict", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("macos-adapter-assignment-conflict")
            }

            HStack(spacing: 12 * metrics.scale) {
                Button("settings.adapter.details.decline") {
                    send(.inspectedAdapterDeclined)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("macos-adapter-details-decline")

                Spacer(minLength: 0)

                Button("settings.adapter.details.confirm") {
                    send(.inspectedAdapterConfirmed)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("macos-adapter-details-confirm")
            }
        }
        .padding(26 * metrics.scale)
        .frame(width: 520 * metrics.scale)
        .accessibilityIdentifier("macos-adapter-connection-details")
    }

    /// 1件の接続情報をラベルと省略しない値の行として生成します。
    ///
    /// 責務: 1項目の接続情報を判別可能なラベル付き詳細行として描画します。
    /// - Parameters:
    ///   - title: 項目名を表すローカライズキー。
    ///   - value: システムから取得した完全な値。
    ///   - monospaced: 値を等幅フォントで表示するかどうか。
    /// - Returns: 長い識別子を選択して確認できる詳細行。
    private func detailRow(
        _ title: LocalizedStringKey,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 16 * metrics.scale) {
            Text(title)
                .font(.system(size: 10.5 * metrics.scale, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104 * metrics.scale, alignment: .leading)

            Text(value)
                .font(.system(size: 11 * metrics.scale, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14 * metrics.scale)
        .padding(.vertical, 11 * metrics.scale)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }
}

/// 接続情報モーダルで使う接続方式名称を提供します。
private extension AdapterTransportMode {
    /// 接続方式の詳細表示用名称です。
    var detailTitle: String {
        switch self {
        case .usb:
            String(localized: "settings.adapter.transport.usb")
        case .bluetooth:
            String(localized: "settings.adapter.transport.bluetooth")
        }
    }
}
#endif
