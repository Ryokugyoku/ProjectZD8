#if os(macOS)
import SwiftUI

/// macOS専用の設定画面レイアウトを描画します。
struct MacOSSettingsView: View {
    /// アクセシビリティ設定で動きを抑える必要があるかどうかです。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// アダプター設定カードの振動アニメーション進行値です。
    @State private var adapterAttentionProgress: CGFloat = 0

    /// このViewが最後に処理した注目要求番号です。
    @State private var handledAdapterAttentionSequence: UInt = 0

    /// スクロール対象として使うアダプター設定カードの識別子です。
    private static let adapterCardID = "macos-settings-adapter-card"

    /// 設定画面に表示する現在の選択状態です。
    let state: MacOSSettingsState

    /// 設定画面の選択操作をAppShellへ通知するクロージャです。
    let send: (MacOSSettingsAction) -> Void

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 設定画面のレスポンシブなスクロール領域を提供します。
    ///
    /// 責務: 表示設定と未接続機能の状態を操作可能なmacOS設定レイアウトとして描画します。
    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                        header
                        settingsLayout(isWide: proxy.size.width >= 760)
                        additionNotice
                    }
                    .padding(.horizontal, 32 * metrics.scale)
                    .padding(.vertical, 30 * metrics.scale)
                    .frame(maxWidth: 1_120, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .background(settingsBackground)
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
        }
        .sheet(
            item: Binding(
                get: { state.presentedAdapterSlot },
                set: { slot in
                    if slot == nil { send(.adapterSelectionCancelled) }
                }
            )
        ) { slot in
            MacOSAdapterSelectionView(
                slot: slot,
                state: state,
                send: send,
                metrics: metrics
            )
            .environment(\.locale, Locale(identifier: state.language.localeIdentifier))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-settings-screen")
    }

    /// 設定画面の目的を示す見出しです。
    private var header: some View {
        HStack(alignment: .center, spacing: 18 * metrics.scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 25 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 58 * metrics.scale, height: 58 * metrics.scale)
            .overlay {
                RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text("settings.title")
                    .font(.system(size: 28 * metrics.scale, weight: .bold, design: .rounded))

                Text("settings.subtitle")
                    .font(.system(size: 13 * metrics.scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 設定項目の背後に奥行きを与える背景です。
    private var settingsBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.08), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 560 * metrics.scale
            )
        }
        .ignoresSafeArea()
    }

    /// 設定項目をウインドウ幅に応じた列へ配置します。
    ///
    /// 責務: 設定カードを利用可能幅に応じて一列または二列へ並べ替えます。
    /// - Parameter isWide: 二列表示に十分な横幅があるかどうか。
    /// - Returns: 現在の横幅に適した設定カードの配置。
    @ViewBuilder
    private func settingsLayout(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 18 * metrics.scale) {
                VStack(spacing: 18 * metrics.scale) {
                    languageCard
                    appearanceCard
                }

                VStack(spacing: 18 * metrics.scale) {
                    adapterCard
                    storageCard
                }
            }
        } else {
            VStack(spacing: 16 * metrics.scale) {
                languageCard
                appearanceCard
                adapterCard
                storageCard
            }
        }
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
                ForEach(MacOSSettingsLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("macos-settings-language")
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
            HStack(spacing: 8 * metrics.scale) {
                ForEach(MacOSSettingsAppearance.allCases) { appearance in
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
            VStack(spacing: 10 * metrics.scale) {
                adapterRow(for: .primary)
                adapterRow(for: .secondary)
            }
        }
        .id(Self.adapterCardID)
        .accessibilityIdentifier(Self.adapterCardID)
        .modifier(
            AttentionShakeEffect(
                progress: accessibilityReduceMotion ? 0 : adapterAttentionProgress,
                amplitude: 9 * metrics.scale
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
        scrollProxy.scrollTo(Self.adapterCardID, anchor: .center)
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
            HStack(spacing: 10 * metrics.scale) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 15 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("settings.storage.coming_soon")
                    .font(.system(size: 12 * metrics.scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(12 * metrics.scale)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous))
        }
        .accessibilityIdentifier("macos-settings-storage-coming-soon")
    }

    /// 今後の設定項目追加を予告する補足表示です。
    private var additionNotice: some View {
        Label {
            Text("settings.more.caption")
                .font(.system(size: 11 * metrics.scale, weight: .medium))
        } icon: {
            Image(systemName: "plus.circle.dashed")
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4 * metrics.scale)
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
    /// - Returns: 設定画面の視覚階層へ揃えたカード。
    private func settingsCard<Content: View>(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            HStack(alignment: .top, spacing: 12 * metrics.scale) {
                Image(systemName: systemImage)
                    .font(.system(size: 16 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34 * metrics.scale, height: 34 * metrics.scale)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                    Text(eyebrow)
                        .font(.system(size: 9 * metrics.scale, weight: .bold, design: .rounded))
                        .tracking(1.2 * metrics.scale)
                        .foregroundStyle(.tint)

                    Text(title)
                        .font(.system(size: 17 * metrics.scale, weight: .bold, design: .rounded))

                    Text(description)
                        .font(.system(size: 11.5 * metrics.scale, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(18 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    /// 1件の外観モードを選択するボタンを生成します。
    ///
    /// 責務: 1件の外観モードを選択状態が分かる操作として描画します。
    /// - Parameter appearance: ボタンが表す外観モード。
    /// - Returns: 選択状態を複数の視覚手掛かりで示すボタン。
    private func appearanceButton(for appearance: MacOSSettingsAppearance) -> some View {
        let isSelected = state.appearance == appearance

        return Button {
            send(.appearanceSelected(appearance))
        } label: {
            VStack(spacing: 7 * metrics.scale) {
                Image(systemName: appearance.systemImage)
                    .font(.system(size: 17 * metrics.scale, weight: .semibold))

                Text(appearance.title)
                    .font(.system(size: 10.5 * metrics.scale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 56 * metrics.scale)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.48) : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("macos-settings-appearance-\(appearance.rawValue)")
    }

    /// 1件のアダプタースロットの要件と現在の選択状態を描画します。
    ///
    /// 責務: 1件のアダプタースロットを役割と選択導線を持つ行として描画します。
    /// - Parameter slot: 行が表すアダプタースロット。
    /// - Returns: 現在の選択状態と選択導線を提供するアダプター行。
    private func adapterRow(for slot: AdapterConnectionRole) -> some View {
        HStack(spacing: 12 * metrics.scale) {
            ZStack {
                Circle()
                    .fill(slot == .primary ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.055))

                Image(systemName: slot.systemImage)
                    .font(.system(size: 14 * metrics.scale, weight: .semibold))
                    .foregroundStyle(slot == .primary ? Color.accentColor : Color.secondary)
            }
            .frame(width: 34 * metrics.scale, height: 34 * metrics.scale)

            VStack(alignment: .leading, spacing: 2 * metrics.scale) {
                HStack(spacing: 6 * metrics.scale) {
                    Text(slot.title)
                        .font(.system(size: 12 * metrics.scale, weight: .semibold, design: .rounded))

                    Text(slot.badge)
                        .font(.system(size: 8 * metrics.scale, weight: .bold, design: .rounded))
                        .foregroundStyle(slot == .primary ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6 * metrics.scale)
                        .padding(.vertical, 2 * metrics.scale)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                }

                Text(adapterDescription(for: slot))
                    .font(.system(size: 10.5 * metrics.scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4 * metrics.scale)

            Button("settings.adapter.select") {
                send(.adapterSelectionRequested(slot))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(slot.title)
            .accessibilityHint(Text("settings.adapter.select"))
            .accessibilityIdentifier("macos-settings-adapter-\(slot.rawValue)-select")
        }
        .padding(11 * metrics.scale)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13 * metrics.scale, style: .continuous))
        .accessibilityIdentifier("macos-settings-adapter-\(slot.rawValue)")
    }

    /// アダプタースロットに対応する現在の設定内容を返します。
    ///
    /// 責務: 1件のアダプタースロットを一覧表示用の設定説明へ変換します。
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
