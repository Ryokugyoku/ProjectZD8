#if os(macOS)
import SwiftUI

/// macOSで指定された接続役割の利用可能な接続済みアダプター候補を接続方式別に表示します。
struct MacOSAdapterSelectionView: View {
    /// この候補選択画面が設定するアダプターの接続役割です。
    let slot: AdapterConnectionRole

    /// 候補一覧と探索状態を含む現在の設定表示状態です。
    let state: MacOSSettingsState

    /// 候補探索と選択操作をプレゼンテーションモデルへ通知します。
    let send: (MacOSSettingsAction) -> Void

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 接続方式、候補一覧、再探索操作を持つ選択画面を提供します。
    ///
    /// 責務: 指定された接続役割のアダプター候補を接続方式別に比較できるモーダルとして描画します。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            discoveryContent
            Divider()
            footer
        }
        .frame(minWidth: 560 * metrics.scale, idealWidth: 640 * metrics.scale)
        .frame(minHeight: 500 * metrics.scale, idealHeight: 580 * metrics.scale)
        .background(selectionBackground)
        .sheet(
            isPresented: Binding(
                get: { state.inspectedAdapter != nil },
                set: { isPresented in
                    if !isPresented { send(.adapterDetailsDismissed) }
                }
            )
        ) {
            if let adapter = state.inspectedAdapter {
                MacOSAdapterConnectionDetailView(
                    adapter: adapter,
                    hasAssignmentConflict: state.hasAdapterAssignmentConflict,
                    send: send,
                    metrics: metrics
                )
            }
        }
        .accessibilityIdentifier("macos-\(slot.rawValue)-adapter-selection")
    }

    /// 選択画面の目的と接続方式切り替えを表示します。
    private var header: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            HStack(spacing: 14 * metrics.scale) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))

                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 21 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 46 * metrics.scale, height: 46 * metrics.scale)

                VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                    Text(slot.selectionTitle)
                        .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))

                    Text("settings.adapter.selector.description")
                        .font(.system(size: 11.5 * metrics.scale))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Picker(
                "settings.adapter.selector.mode",
                selection: Binding(
                    get: { state.adapterTransportMode },
                    set: { send(.adapterTransportModeSelected($0)) }
                )
            ) {
                ForEach(AdapterTransportMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("macos-adapter-transport-mode")
        }
        .padding(24 * metrics.scale)
    }

    /// 現在の探索状態に対応する候補領域です。
    @ViewBuilder
    private var discoveryContent: some View {
        switch state.adapterDiscoveryStatus {
        case .idle, .searching:
            VStack(spacing: 14 * metrics.scale) {
                ProgressView()
                    .controlSize(.large)
                Text("settings.adapter.selector.searching")
                    .font(.system(size: 12 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("macos-adapter-searching")
        case .loaded where state.discoveredAdapters.isEmpty:
            ContentUnavailableView(
                "settings.adapter.selector.empty.title",
                systemImage: state.adapterTransportMode.systemImage,
                description: Text("settings.adapter.selector.empty.description")
            )
            .accessibilityIdentifier("macos-adapter-empty")
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 10 * metrics.scale) {
                    ForEach(state.discoveredAdapters) { adapter in
                        candidateButton(for: adapter)
                    }
                }
                .padding(20 * metrics.scale)
            }
            .scrollIndicators(.automatic)
        case .failed:
            ContentUnavailableView(
                "settings.adapter.selector.failed.title",
                systemImage: "exclamationmark.triangle.fill",
                description: Text("settings.adapter.selector.failed.description")
            )
            .accessibilityIdentifier("macos-adapter-discovery-failed")
        }
    }

    /// 選択画面下部の再探索と終了操作です。
    private var footer: some View {
        HStack(spacing: 12 * metrics.scale) {
            Button {
                send(.adapterRefreshRequested)
            } label: {
                Label("settings.adapter.selector.refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.adapterDiscoveryStatus == .searching)
            .accessibilityIdentifier("macos-adapter-refresh")

            Spacer(minLength: 0)

            Button("settings.adapter.selector.cancel") {
                send(.adapterSelectionCancelled)
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24 * metrics.scale)
        .padding(.vertical, 16 * metrics.scale)
    }

    /// 選択モーダルへ抑制された奥行きを与える背景です。
    private var selectionBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.075), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 460 * metrics.scale
            )
        }
        .ignoresSafeArea()
    }

    /// 1件の候補を名称と短縮識別情報を持つ選択行として生成します。
    ///
    /// 責務: 1件のアダプター候補を詳細確認へ進める選択操作として描画します。
    /// - Parameter adapter: 表示対象のアダプター候補。
    /// - Returns: 名称が取得できない場合も識別可能な候補ボタン。
    private func candidateButton(for adapter: DiscoveredAdapter) -> some View {
        Button {
            send(.adapterCandidateSelected(adapter))
        } label: {
            HStack(spacing: 14 * metrics.scale) {
                Image(systemName: adapter.transportMode.systemImage)
                    .font(.system(size: 17 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38 * metrics.scale, height: 38 * metrics.scale)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11 * metrics.scale, style: .continuous))

                VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                    Text(adapter.displayName)
                        .font(.system(size: 13 * metrics.scale, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(adapter.systemIdentifier)
                        .font(.system(size: 10.5 * metrics.scale, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6 * metrics.scale)

                Image(systemName: "info.circle")
                    .font(.system(size: 15 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(13 * metrics.scale)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("macos-adapter-candidate-\(adapter.id)")
    }
}

/// macOSアダプター選択画面で使う接続方式表示を提供します。
private extension AdapterTransportMode {
    /// 接続方式のローカライズ済み名称です。
    var title: LocalizedStringKey {
        switch self {
        case .usb:
            "settings.adapter.transport.usb"
        case .bluetooth:
            "settings.adapter.transport.bluetooth"
        }
    }

    /// 接続方式を表すSF Symbol名です。
    var systemImage: String {
        switch self {
        case .usb:
            "cable.connector"
        case .bluetooth:
            "antenna.radiowaves.left.and.right"
        }
    }
}
#endif
