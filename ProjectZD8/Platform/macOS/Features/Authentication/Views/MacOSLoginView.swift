#if os(macOS)
import SwiftUI

/// macOS専用のAppleアカウントログイン画面を描画します。
struct MacOSLoginView: View {
    /// Dynamic Typeの現在の文字サイズ分類です。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Applicationが提供する現在の認証状態です。
    let state: AuthenticationState

    /// ログイン画面の型付き操作をApplicationへ通知します。
    let send: (AuthenticationAction) -> Void

    /// Macウインドウの利用可能領域へ追従するログイン画面を描画します。
    ///
    /// 責務: macOS認証状態をウインドウ寸法に応じた一列または二列のログイン画面へ表示します。
    var body: some View {
        GeometryReader { proxy in
            let metrics = MacOSLoginMetrics.resolve(
                size: proxy.size,
                usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
            )

            ZStack {
                CockpitBackdrop()
                switch metrics.layout {
                case .split:
                    splitLayout(metrics: metrics, height: proxy.size.height)
                case .singleColumn:
                    singleColumnLayout(metrics: metrics, height: proxy.size.height)
                }
            }
            .environment(\.colorScheme, .dark)
            .animation(.snappy, value: state.phase)
            .animation(.snappy, value: state.failure)
        }
        .sheet(isPresented: disclaimerBinding) {
            MacOSLoginDisclaimerView(
                dismiss: { send(.disclaimerDismissed) },
                accept: { send(.disclaimerAccepted) }
            )
        }
        .task {
            send(.appeared)
        }
        .frame(minWidth: 640, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-login-screen")
    }

    /// Application状態と免責事項シートの表示を双方向に結び付けます。
    private var disclaimerBinding: Binding<Bool> {
        Binding(
            get: { state.isDisclaimerPresented },
            set: { isPresented in
                if !isPresented {
                    send(.disclaimerDismissed)
                }
            }
        )
    }

    // MARK: - Layouts

    /// 横長ウインドウでブランド領域と認証パネルを左右に分けます。
    ///
    /// 責務: 二列構成で各列を独立スクロールさせ、低いウインドウでも見切れない配置にします。
    /// - Parameters:
    ///   - metrics: 現在のウインドウ寸法から解決した表示規則。
    ///   - height: 列の最小高さとして使うウインドウ内の高さ。
    /// - Returns: ブランド領域と認証パネルを持つmacOS二列構成。
    private func splitLayout(metrics: MacOSLoginMetrics, height: CGFloat) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader(scale: metrics.scale)
                    Spacer(minLength: 28 * metrics.scale)
                    heroAndIntroduction(metrics: metrics, alignment: .leading)
                    Spacer(minLength: 28 * metrics.scale)
                    capabilityTiles(scale: metrics.scale)
                }
                .frame(maxWidth: metrics.contentMaxWidth, alignment: .leading)
                .padding(.vertical, metrics.outerPadding)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)

            ScrollView {
                authenticationPanel(scale: metrics.scale)
                    .padding(.vertical, metrics.outerPadding)
                    .frame(minHeight: height)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: metrics.panelWidth)
        }
        .frame(maxWidth: metrics.contentMaxWidth + metrics.columnSpacing + metrics.panelWidth)
        .padding(.horizontal, metrics.outerPadding)
        .frame(maxWidth: .infinity)
    }

    /// 小さいウインドウまたは拡大文字で全内容を中央一列に並べます。
    ///
    /// 責務: macOSログイン内容を見切れないスクロール可能な一列構成へ配置します。
    /// - Parameters:
    ///   - metrics: 現在のウインドウ寸法から解決した表示規則。
    ///   - height: 内容を縦中央へ置くためのウインドウ内の高さ。
    /// - Returns: 最小ウインドウでも操作可能なmacOS一列構成。
    private func singleColumnLayout(metrics: MacOSLoginMetrics, height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 22 * metrics.scale) {
                brandHeader(scale: metrics.scale)
                heroAndIntroduction(
                    metrics: metrics,
                    alignment: metrics.placesHeroBesideIntroduction ? .leading : .center
                )
                authenticationPanel(scale: metrics.scale)
                capabilityTiles(scale: metrics.scale)
            }
            .frame(maxWidth: metrics.contentMaxWidth)
            .padding(metrics.outerPadding)
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Brand

    /// 製品名とコンセプトラベルを指定倍率で表示します。
    ///
    /// 責務: macOSログイン画面のブランド識別情報を1件のヘッダーへ配置します。
    /// - Parameter scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: RevTorque InsightのmacOSブランドヘッダー。
    private func brandHeader(scale: CGFloat) -> some View {
        HStack(spacing: 13 * scale) {
            RevTorqueBrandMark(size: 48 * scale)
            VStack(alignment: .leading, spacing: 2) {
                Text("RevTorque Insight")
                    .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                    .tracking(0.25)
                Text("auth.eyebrow")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.4)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// コックピット意匠と価値提案を、幅に応じて横並びまたは縦積みで表示します。
    ///
    /// 責務: 表示規則に従って計器意匠と見出しの相対配置を決めます。
    /// - Parameters:
    ///   - metrics: 意匠直径と配置方向を決める表示規則。
    ///   - alignment: 縦積み時のテキスト配置。
    /// - Returns: 計器意匠と製品説明の組み合わせ。
    @ViewBuilder
    private func heroAndIntroduction(metrics: MacOSLoginMetrics, alignment: TextAlignment) -> some View {
        if metrics.placesHeroBesideIntroduction {
            HStack(spacing: 34 * metrics.scale) {
                CockpitGaugeEmblem(diameter: metrics.heroDiameter)
                introduction(alignment: .leading, scale: metrics.scale)
            }
        } else {
            VStack(alignment: alignment == .center ? .center : .leading, spacing: 20 * metrics.scale) {
                CockpitGaugeEmblem(diameter: metrics.heroDiameter)
                introduction(alignment: alignment, scale: metrics.scale)
            }
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        }
    }

    /// 製品の価値提案を指定配置と倍率で表示します。
    ///
    /// 責務: ログイン前の製品説明をmacOS用の見出しと本文へ配置します。
    /// - Parameters:
    ///   - alignment: ウインドウ構成に応じたテキスト配置。
    ///   - scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: 製品価値を説明するmacOS表示。
    private func introduction(alignment: TextAlignment, scale: CGFloat) -> some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 10 * scale) {
            Text("auth.title")
                .font(.system(size: 38 * scale, weight: .bold, design: .rounded))
                .multilineTextAlignment(alignment)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("auth.subtitle")
                .font(.system(size: 15 * scale, weight: .regular))
                .multilineTextAlignment(alignment)
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    /// 静的な製品特性を計器パネル風のタイルで並べます。
    ///
    /// 責務: ログイン前に説明できる3件の製品特性を等幅タイルで表示します。
    /// - Parameter scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: 3件の静的な製品特性表示。
    private func capabilityTiles(scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10 * scale) {
            capabilityTile(symbol: "waveform.path.ecg", key: "auth.capability.telemetry", scale: scale)
            capabilityTile(symbol: "doc.text.magnifyingglass", key: "auth.capability.logs", scale: scale)
            capabilityTile(symbol: "chart.xyaxis.line", key: "auth.capability.analysis", scale: scale)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 静的な製品特性を1件のmacOSタイルとして描画します。
    ///
    /// 責務: 1件の製品特性をアイコン付きの計器風タイルへ変換します。
    /// - Parameters:
    ///   - symbol: 特性を補助するSF Symbol名。
    ///   - key: ローカライズ済み特性名のキー。
    ///   - scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: macOS向け製品特性タイル。
    private func capabilityTile(
        symbol: String,
        key: LocalizedStringKey,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                .accessibilityHidden(true)
            Text(key)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Authentication

    /// 見出し、認証操作、信頼要素、同意案内を持つ認証パネルです。
    ///
    /// 責務: 現在の認証段階に対応する操作をmacOSのガラス調パネルへ配置します。
    /// - Parameter scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: macOS向け認証パネル。
    private func authenticationPanel(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("auth.panel.eyebrow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.2)
                Text("auth.panel.title")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("auth.panel.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(.white.opacity(0.1))

            authenticationControls

            VStack(alignment: .leading, spacing: 7) {
                trustItem(symbol: "lock.shield", key: "auth.trust.private")
                trustItem(symbol: "checkmark.shield", key: "auth.trust.apple_only")
                trustItem(symbol: "externaldrive", key: "auth.trust.local")
            }

            Text("auth.consent_hint")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 32, y: 14)
    }

    /// 現在の認証段階に対応する失敗表示、進捗、ログイン操作です。
    private var authenticationControls: some View {
        VStack(spacing: 10) {
            if state.phase == .signedOut, let failure = state.failure {
                failureBanner(for: failure)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Group {
                switch state.phase {
                case .checkingSession:
                    progressIndicator("auth.checking")
                case .signingIn:
                    progressIndicator("auth.signing_in")
                case .signedOut:
                    signInButton
                case .signedIn:
                    EmptyView()
                }
            }
            .frame(minHeight: 46)
        }
    }

    /// Appleアカウントでのログインまたは再試行を通知するボタンです。
    private var signInButton: some View {
        Button {
            send(state.failure == nil ? .loginTapped : .retryTapped)
        } label: {
            Label("auth.continue_with_apple", systemImage: "apple.logo")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.22), radius: 16, y: 5)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("macos-auth-login")
    }

    /// ボタンと同じ高さを保つ進捗表示です。
    ///
    /// 責務: 1件の進行中段階をレイアウトを揺らさない進捗表示へ変換します。
    /// - Parameter key: 進行中段階を説明するローカライズ文字列キー。
    /// - Returns: ログインボタンと同寸の進捗表示。
    private func progressIndicator(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(key)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 認証失敗と再試行可能であることを伝える警告表示です。
    ///
    /// 責務: 1件の認証失敗をオレンジの小さな警告バナーへ変換します。
    /// - Parameter failure: Applicationが保持する区別可能な認証失敗。
    /// - Returns: macOS向け認証失敗バナー。
    private func failureBanner(for failure: AuthenticationFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WarningTriangleIcon(size: 13)
            Text(failureMessage(for: failure))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// 静的な信頼要素を1件描画します。
    ///
    /// 責務: 1件のログイン前説明をアイコン付きの小型ラベルへ変換します。
    /// - Parameters:
    ///   - symbol: 説明を補助するSF Symbol名。
    ///   - key: ローカライズ済み説明文のキー。
    /// - Returns: macOS向け信頼要素ラベル。
    private func trustItem(symbol: String, key: LocalizedStringKey) -> some View {
        Label {
            Text(key)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor.opacity(0.9))
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.64))
    }

    /// Applicationの認証失敗をローカライズ表示キーへ変換します。
    ///
    /// 責務: 1件の認証失敗をmacOSログイン画面の再試行メッセージへ写像します。
    /// - Parameter failure: Applicationが保持する区別可能な認証失敗。
    /// - Returns: ユーザーへ表示するローカライズ文字列キー。
    private func failureMessage(for failure: AuthenticationFailure) -> LocalizedStringKey {
        switch failure {
        case .remoteLogoutPersistenceFailed:
            "auth.error.remote_logout_persistence"
        case .sessionCheckFailed:
            "auth.error.session_check"
        case .serviceUnavailable:
            "auth.error.unavailable"
        case .signInFailed:
            "auth.error.sign_in"
        }
    }
}
#endif
