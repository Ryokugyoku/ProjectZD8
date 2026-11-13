#if os(macOS)
import SwiftUI

/// 発見したアダプターを一覧し、接続または既定への設定を行うシート。
struct MacOSAdapterPickerSheet: View {
    let state: DeviceConnectionState
    let isConnectEnabled: Bool
    let send: (DeviceConnectionAction) -> Void
    let onConnect: (AdapterDescriptor) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.lg) {
            HStack {
                Text("device.picker.title").font(InsightTypography.screenTitle)
                Spacer()
                if state.discovery == .discovering {
                    ProgressView().controlSize(.small)
                }
                Button {
                    send(.discoverRequested)
                } label: {
                    Label("device.picker.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.discovery == .discovering)
            }

            if case .failed(let error) = state.discovery {
                InlineBanner(.error, message: Text(LocalizedStringKey(error.localizationKey)))
            }

            content

            HStack {
                if state.defaultAdapter != nil {
                    Button(role: .destructive) {
                        send(.defaultAdapterCleared)
                    } label: {
                        Text("device.picker.clearDefault")
                    }
                }
                Spacer()
                Button(action: onClose) { Text("common.close") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(InsightSpacing.xl)
        .frame(width: MacOSAppShellMetrics.sheetWidth * 1.2)
        .frame(minHeight: 360)
        .task { send(.discoverRequested) }
        .onDisappear { send(.discoveryCancelled) }
    }

    @ViewBuilder
    private var content: some View {
        if state.adapters.isEmpty {
            if state.discovery == .discovering {
                EmptyStateView(symbol: "magnifyingglass", title: Text("device.picker.searching"))
            } else {
                EmptyStateView(
                    symbol: "cable.connector.slash",
                    title: Text("device.picker.empty.title"),
                    message: Text("device.picker.empty.message")
                )
            }
        } else {
            List(state.adapters) { adapter in
                row(adapter)
            }
            .listStyle(.inset)
            .frame(minHeight: 200)
        }
    }

    private func row(_ adapter: AdapterDescriptor) -> some View {
        let isDefault = state.defaultAdapter?.id == adapter.id
        return HStack(spacing: InsightSpacing.md) {
            Image(systemName: adapter.transport.macOSSymbol)
                .foregroundStyle(InsightPalette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                HStack(spacing: InsightSpacing.sm) {
                    Text(verbatim: adapter.displayName).font(InsightTypography.sectionTitle)
                    if isDefault { StatusBadge(Text("device.picker.default"), tone: .active) }
                }
                Text(adapter.transport.macOSNameKey).font(InsightTypography.caption).foregroundStyle(.secondary)
                if let detail = adapter.detail {
                    Text(verbatim: detail).font(InsightTypography.footnote).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !isDefault {
                Button {
                    send(.defaultAdapterSelected(adapter))
                } label: {
                    Text("device.picker.setDefault")
                }
            }
            Button {
                onConnect(adapter)
            } label: {
                Text("device.picker.connect")
            }
            .buttonStyle(.insightPrimary)
            .disabled(!isConnectEnabled)
        }
        .padding(.vertical, InsightSpacing.xs)
        .accessibilityElement(children: .contain)
    }
}
#endif
