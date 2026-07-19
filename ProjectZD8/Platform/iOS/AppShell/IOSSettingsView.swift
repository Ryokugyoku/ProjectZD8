#if os(iOS)
import SwiftUI

/// iOS専用の設定画面レイアウトを描画します。
struct IOSSettingsView: View {
    /// アクセシビリティ設定で動きを抑える必要があるかどうかです。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// アダプター設定カードの振動アニメーション進行値です。
    @State private var adapterAttentionProgress: CGFloat = 0

    /// このViewが最後に処理した注目要求番号です。
    @State private var handledAdapterAttentionSequence: UInt = 0

    /// スクロール対象として使うアダプター設定カードの識別子です。
    private static let adapterCardID = "ios-settings-adapter-card"

    /// 設定画面に表示する現在の選択状態です。
    let state: IOSSettingsState

    /// 設定画面の選択操作をAppShellへ通知するクロージャです。
    let send: (IOSSettingsAction) -> Void

    /// iPhoneの縦方向操作に合わせた設定スクロール領域を提供します。
    ///
    /// 責務: 表示設定と2種類のBluetoothアダプター選択導線をiOS設定レイアウトとして描画します。
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    languageCard
                    appearanceCard
                    adapterCard
                    storageCard
                    additionNotice
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                presentAdapterAttentionIfNeeded(
                    sequence: state.adapterAttentionSequence,
                    isPending: state.hasPendingAdapterAttention,
                    scrollProxy: scrollProxy
                )
            }
            .onChange(of: state.adapterAttentionSequence) { _, sequence in
                presentAdapterAttentionIfNeeded(
                    sequence: sequence,
                    isPending: state.hasPendingAdapterAttention,
                    scrollProxy: scrollProxy
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { state.presentedAdapterSlot != nil },
                set: { isPresented in
                    if !isPresented { send(.adapterSelectionCancelled) }
                }
            )
        ) {
            if let slot = state.presentedAdapterSlot {
                IOSAdapterSelectionView(slot: slot, state: state, send: send)
                    .environment(\.locale, Locale(identifier: state.language.localeIdentifier))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-screen")
    }

    /// 設定画面の目的を示すモバイル向け見出しです。
    private var header: some View {
        HStack(alignment: .center, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 58, height: 58)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("settings.title")
                    .font(.system(.title, design: .rounded, weight: .bold))

                Text("settings.subtitle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 8)
    }

    /// 表示言語を切り替える設定カードです。
    private var languageCard: some View {
        settingsCard(
            eyebrow: "settings.language.eyebrow",
            title: "settings.language.title",
            description: "settings.language.description",
            systemImage: "character.bubble.fill"
        ) {
            Picker(
                "settings.language.title",
                selection: Binding(
                    get: { state.language },
                    set: { send(.languageSelected($0)) }
                )
            ) {
                ForEach(IOSSettingsLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ios-settings-language")
        }
    }

    /// 外観モードを切り替える設定カードです。
    private var appearanceCard: some View {
        settingsCard(
            eyebrow: "settings.appearance.eyebrow",
            title: "settings.appearance.title",
            description: "settings.appearance.description",
            systemImage: "circle.lefthalf.filled"
        ) {
            HStack(spacing: 8) {
                ForEach(IOSSettingsAppearance.allCases) { appearance in
                    appearanceButton(for: appearance)
                }
            }
        }
    }

    /// プライマリーと受信専用セカンダリーを示すアダプター設定カードです。
    private var adapterCard: some View {
        settingsCard(
            eyebrow: "settings.adapter.eyebrow",
            title: "settings.adapter.title",
            description: "settings.adapter.description",
            systemImage: "cable.connector.horizontal"
        ) {
            VStack(spacing: 10) {
                adapterRow(for: .primary)
                adapterRow(for: .secondary)
            }
        }
        .id(Self.adapterCardID)
        .accessibilityIdentifier(Self.adapterCardID)
        .modifier(
            AttentionShakeEffect(
                progress: accessibilityReduceMotion ? 0 : adapterAttentionProgress,
                amplitude: 8
            )
        )
    }

    /// HOMEの「アダプターを設定」ボタン由来で未消費の注目要求がある場合だけ設定カードへスクロールして振動させます。
    ///
    /// 責務: 「アダプターを設定」ボタンを押すたびに遷移直後の1回だけを強調し、通常の手動遷移では再表示されない消費済み状態へ変換します。
    /// - Parameters:
    ///   - sequence: 処理対象の注目要求番号。
    ///   - isPending: 直前の「アダプターを設定」ボタン押下による未消費要求が残っているかどうか。
    ///   - scrollProxy: アダプター設定カードを表示領域へ移動するスクロール操作境界。
    private func presentAdapterAttentionIfNeeded(
        sequence: UInt,
        isPending: Bool,
        scrollProxy: ScrollViewProxy
    ) {
        guard isPending,
              sequence != handledAdapterAttentionSequence else { return }
        handledAdapterAttentionSequence = sequence
        send(.adapterAttentionConsumed(sequence))
        withAnimation(.snappy(duration: 0.26)) {
            scrollProxy.scrollTo(Self.adapterCardID, anchor: .center)
        }
        adapterAttentionProgress = 0
        guard !accessibilityReduceMotion else { return }
        withAnimation(.linear(duration: 0.56)) {
            adapterAttentionProgress = 1
        }
    }

    /// 将来提供予定であることを示すストレージ設定カードです。
    private var storageCard: some View {
        settingsCard(
            eyebrow: "settings.storage.eyebrow",
            title: "settings.storage.title",
            description: "settings.storage.description",
            systemImage: "internaldrive.fill"
        ) {
            Label("settings.storage.coming_soon", systemImage: "clock.badge.checkmark")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 14)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier("ios-settings-storage-coming-soon")
    }

    /// 今後の設定項目追加を予告する補足表示です。
    private var additionNotice: some View {
        Label("settings.more.caption", systemImage: "plus.circle.dashed")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    /// 共通階層を持つ設定カードを生成します。
    ///
    /// 責務: 1件の設定カテゴリを統一された見出しと操作領域を持つカードとして描画します。
    /// - Parameters:
    ///   - eyebrow: カテゴリを短く識別するローカライズキー。
    ///   - title: 設定カードのローカライズ済みタイトル。
    ///   - description: 設定内容を補足するローカライズキー。
    ///   - systemImage: カテゴリを表すSF Symbol名。
    ///   - content: カード下部へ配置する操作または状態表示。
    /// - Returns: iOS設定画面の視覚階層へ揃えたカード。
    private func settingsCard<Content: View>(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(.tint)

                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .bold))

                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    /// 1件の外観モードを選択するボタンを生成します。
    ///
    /// 責務: 1件の外観モードを選択状態が分かる操作として描画します。
    /// - Parameter appearance: ボタンが表す外観モード。
    /// - Returns: 選択状態を複数の視覚手掛かりで示すボタン。
    private func appearanceButton(for appearance: IOSSettingsAppearance) -> some View {
        let isSelected = state.appearance == appearance

        return Button {
            send(.appearanceSelected(appearance))
        } label: {
            VStack(spacing: 7) {
                Image(systemName: appearance.systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(appearance.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ios-settings-appearance-\(appearance.rawValue)")
    }

    /// 1件のアダプタースロットの要件と未選択状態を描画します。
    ///
    /// 責務: 1件のアダプタースロットを役割と選択導線を持つ行として描画します。
    /// - Parameter slot: 行が表すアダプタースロット。
    /// - Returns: 実接続を装わず選択導線を提供するアダプター行。
    private func adapterRow(for slot: AdapterConnectionRole) -> some View {
        Button {
            send(.adapterSelectionRequested(slot))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(slot == .primary ? Color.accentColor : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        slot == .primary ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(slot.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))

                        Text(slot.badge)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(slot == .primary ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }

                    Text(adapterDescription(for: slot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("settings.adapter.select"))
        .accessibilityIdentifier("ios-settings-adapter-\(slot.rawValue)")
    }

    /// アダプタースロットに対応する現在の設定内容を返します。
    ///
    /// 責務: 1件のiOSアダプタースロットを一覧表示用の設定説明へ変換します。
    /// - Parameter slot: 表示対象のアダプタースロット。
    /// - Returns: 選択済み名称または未選択を示すローカライズ値。
    private func adapterDescription(for slot: AdapterConnectionRole) -> LocalizedStringKey {
        if let adapter = state.selectedAdapters[slot] {
            LocalizedStringKey(adapter.displayName)
        } else {
            "settings.adapter.not_selected"
        }
    }
}
#endif
