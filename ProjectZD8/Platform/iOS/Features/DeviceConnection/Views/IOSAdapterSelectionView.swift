#if os(iOS)
import SwiftUI

/// iPhoneで指定スロットへ割り当てるBluetooth Low Energy候補を表示します。
struct IOSAdapterSelectionView: View {
    /// Bluetooth候補を割り当てるアダプタースロットです。
    let slot: AdapterConnectionRole

    /// 候補一覧とBluetooth探索状態を含む現在の設定表示状態です。
    let state: IOSSettingsState

    /// 候補探索と選択操作をプレゼンテーションモデルへ通知します。
    let send: (IOSSettingsAction) -> Void

    /// Bluetooth専用の候補一覧と再探索およびキャンセル操作を提供します。
    ///
    /// 責務: iPhoneで指定スロット向けBLE候補を状態別に確認できる選択画面として描画します。
    var body: some View {
        NavigationStack {
            discoveryContent
                .navigationTitle(slot.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("settings.adapter.selector.cancel") {
                            send(.adapterSelectionCancelled)
                        }
                        .accessibilityIdentifier("ios-adapter-selection-cancel")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            send(.bluetoothRefreshRequested)
                        } label: {
                            Label("settings.adapter.selector.refresh", systemImage: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("ios-adapter-refresh")
                    }
                }
        }
        .sheet(
            isPresented: Binding(
                get: { state.inspectedAdapter != nil },
                set: { isPresented in
                    if !isPresented { send(.adapterDetailsDismissed) }
                }
            )
        ) {
            if let adapter = state.inspectedAdapter {
                IOSAdapterConnectionDetailView(
                    adapter: adapter,
                    slot: slot,
                    hasAssignmentConflict: state.hasAdapterAssignmentConflict,
                    send: send
                )
            }
        }
        .accessibilityIdentifier("ios-adapter-selection-\(slot.rawValue)")
    }

    /// 現在のBluetooth探索状態に対応する候補領域です。
    @ViewBuilder
    private var discoveryContent: some View {
        switch state.bluetoothDiscoveryStatus {
        case .idle, .searching:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("ios.settings.adapter.selector.searching")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("ios-adapter-searching")
        case .loaded where state.discoveredAdapters.isEmpty:
            ContentUnavailableView(
                "settings.adapter.selector.empty.title",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: Text("ios.settings.adapter.selector.empty.description")
            )
            .accessibilityIdentifier("ios-adapter-empty")
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(state.discoveredAdapters) { adapter in
                        candidateButton(for: adapter)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.automatic)
        case let .unavailable(reason):
            unavailableView(for: reason)
        case .failed:
            ContentUnavailableView(
                "settings.adapter.selector.failed.title",
                systemImage: "exclamationmark.triangle.fill",
                description: Text("ios.settings.adapter.selector.failed.description")
            )
            .accessibilityIdentifier("ios-adapter-discovery-failed")
        }
    }

    /// 1件のBLE候補を詳細確認へ進める行として生成します。
    ///
    /// 責務: 1件のBluetooth候補を名称と省略したUUIDを持つ44pt以上の選択操作として描画します。
    /// - Parameter adapter: 表示対象のBluetooth候補。
    /// - Returns: VoiceOverで名称、方式、選択操作を判別できる候補ボタン。
    private func candidateButton(for adapter: DiscoveredAdapter) -> some View {
        Button {
            send(.adapterCandidateSelected(adapter))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(adapter.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(adapter.systemIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(adapter.displayName))
        .accessibilityValue(Text("settings.adapter.transport.bluetooth"))
        .accessibilityHint(Text("ios.settings.adapter.selector.inspect_hint"))
        .accessibilityIdentifier("ios-adapter-candidate-\(adapter.id)")
    }

    /// Bluetooth利用不可理由に対応する説明表示を生成します。
    ///
    /// 責務: 1件のBluetooth利用不可理由を空一覧と区別できる説明として描画します。
    /// - Parameter reason: CoreBluetooth状態から変換された利用不可理由。
    /// - Returns: OFF、未許可、非対応を個別に案内する利用不可表示。
    private func unavailableView(for reason: IOSBluetoothUnavailableReason) -> some View {
        ContentUnavailableView(
            reason.title,
            systemImage: reason.systemImage,
            description: Text(reason.description)
        )
        .accessibilityIdentifier("ios-adapter-unavailable-\(reason.identifier)")
    }
}

/// iOSのBluetooth利用不可理由に対応する表示情報を提供します。
private extension IOSBluetoothUnavailableReason {
    /// 利用不可理由を識別するアクセシビリティ向け文字列です。
    var identifier: String {
        switch self {
        case .poweredOff:
            "powered-off"
        case .unauthorized:
            "unauthorized"
        case .unsupported:
            "unsupported"
        }
    }

    /// 利用不可理由を示すローカライズ済み見出しです。
    var title: LocalizedStringKey {
        switch self {
        case .poweredOff:
            "ios.settings.adapter.unavailable.powered_off.title"
        case .unauthorized:
            "ios.settings.adapter.unavailable.unauthorized.title"
        case .unsupported:
            "ios.settings.adapter.unavailable.unsupported.title"
        }
    }

    /// 利用不可理由への対応を示すローカライズ済み説明です。
    var description: LocalizedStringKey {
        switch self {
        case .poweredOff:
            "ios.settings.adapter.unavailable.powered_off.description"
        case .unauthorized:
            "ios.settings.adapter.unavailable.unauthorized.description"
        case .unsupported:
            "ios.settings.adapter.unavailable.unsupported.description"
        }
    }

    /// 利用不可理由を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .poweredOff:
            "antenna.radiowaves.left.and.right.slash"
        case .unauthorized:
            "hand.raised.fill"
        case .unsupported:
            "iphone.slash"
        }
    }
}
#endif
