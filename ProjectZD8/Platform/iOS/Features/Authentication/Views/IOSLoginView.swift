#if os(iOS)
import SwiftUI

/// iOS専用のAppleアカウントログイン画面を描画します。
struct IOSLoginView: View {
    /// Dynamic Typeの現在の文字サイズ分類です。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Applicationが提供する現在の認証状態です。
    let state: AuthenticationState

    /// ログイン画面の型付き操作をApplicationへ通知します。
    let send: (AuthenticationAction) -> Void

    /// iPhoneとiPadの利用可能領域へ追従するログイン画面を描画します。
    ///
    /// 責務: iOS認証状態を表示領域に応じた一列または二列のログイン画面へ表示します。
    var body: some View {
        GeometryReader { proxy in
            let metrics = IOSLoginMetrics.resolve(
                size: proxy.size,
                usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
            )

            ZStack {
                CockpitBackdrop()
                switch metrics.layout {
                case .singleColumn:
                    singleColumnLayout(metrics: metrics, height: proxy.size.height)
                case .split:
                    splitLayout(metrics: metrics, height: proxy.size.height)
                }
            }
            .environment(\.colorScheme, .dark)
            .animation(.snappy, value: state.phase)
            .animation(.snappy, value: state.failure)
        }
        .sheet(isPresented: disclaimerBinding) {
            IOSLoginDisclaimerView(
                dismiss: { send(.disclaimerDismissed) },
                accept: { send(.disclaimerAccepted) }
            )
        }
        .task {
            send(.appeared)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-login-screen")
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

    /// iPhone縦向きやiPad縦向きでブランド領域と認証操作を縦一列に並べます。iPhone幅では認証操作を下部へ固定します。
    ///
    /// 責務: 一列構成でスクロール量に関係なくログイン操作へ届く画面を配置します。
    /// - Parameters:
    ///   - metrics: 現在の表示領域から解決した寸法。
    ///   - height: 下部固定しない場合に内容を縦中央へ置くための表示領域の高さ。
    /// - Returns: iOS一列構成のログイン画面。
    private func singleColumnLayout(metrics: IOSLoginMetrics, height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: metrics.sectionSpacing) {
                brandHeader
                CockpitGaugeEmblem(diameter: metrics.heroDiameter)
                introduction(alignment: .center, metrics: metrics)
                capabilityTiles(columnCount: metrics.capabilityColumnCount)
                if metrics.docksAuthenticationPanel {
                    trustStrip
                } else {
                    authenticationCard
                }
            }
            .frame(maxWidth: metrics.contentMaxWidth)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.usesCompactHeight ? 16 : 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: metrics.docksAuthenticationPanel ? nil : height)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if metrics.docksAuthenticationPanel {
                dockedAuthenticationPanel(metrics: metrics)
            }
        }
    }

    /// iPad横向きやiPhone横向きでブランド領域と認証パネルを左右へ分けます。
    ///
    /// 責務: 二列構成で各列を独立スクロールさせ、低い画面でも見切れない配置にします。
    /// - Parameters:
    ///   - metrics: 現在の表示領域から解決した寸法。
    ///   - height: 列の最小高さとして使う表示領域の高さ。
    /// - Returns: iOS二列構成のログイン画面。
    private func splitLayout(metrics: IOSLoginMetrics, height: CGFloat) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    brandHeader
                    CockpitGaugeEmblem(diameter: metrics.heroDiameter)
                    introduction(alignment: .leading, metrics: metrics)
                    capabilityTiles(columnCount: metrics.capabilityColumnCount)
                }
                .frame(maxWidth: metrics.contentMaxWidth, alignment: .leading)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            ScrollView {
                authenticationCard
                    .padding(.vertical, 24)
                    .frame(minHeight: height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: metrics.panelWidth)
        }
        .frame(maxWidth: metrics.contentMaxWidth + metrics.columnSpacing + metrics.panelWidth)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Brand

    /// 製品名とコンセプトラベルを表示するブランドヘッダーです。
    private var brandHeader: some View {
        HStack(spacing: 12) {
            RevTorqueBrandMark(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("RevTorque Insight")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .tracking(0.2)
                Text("auth.eyebrow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// 製品の価値提案を指定配置で表示します。
    ///
    /// 責務: ログイン前の製品説明を見出しと本文へ配置します。
    /// - Parameters:
    ///   - alignment: 構成に応じたテキスト配置。
    ///   - metrics: 見出しの大きさを決める寸法。
    /// - Returns: 製品価値を説明するiOS表示。
    private func introduction(alignment: TextAlignment, metrics: IOSLoginMetrics) -> some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 10) {
            Text("auth.title")
                .font(
                    metrics.usesDisplayTitle
                        ? .system(size: 46, weight: .bold, design: .rounded)
                        : .system(.largeTitle, design: .rounded, weight: .bold)
                )
                .multilineTextAlignment(alignment)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("auth.subtitle")
                .font(metrics.usesDisplayTitle ? .title3 : .body)
                .multilineTextAlignment(alignment)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    /// ログイン後に使える主要機能を計器パネル風のタイルで並べます。
    ///
    /// 責務: 3件の静的な製品特性を指定列数のタイルへ配置します。
    /// - Parameter columnCount: 横に並べるタイル数。1の場合は縦に積みます。
    /// - Returns: 製品特性タイル群。
    @ViewBuilder
    private func capabilityTiles(columnCount: Int) -> some View {
        if columnCount > 1 {
            HStack(alignment: .top, spacing: 10) {
                capabilityTile(symbol: "waveform.path.ecg", key: "auth.capability.telemetry")
                capabilityTile(symbol: "doc.text.magnifyingglass", key: "auth.capability.logs")
                capabilityTile(symbol: "chart.xyaxis.line", key: "auth.capability.analysis")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                capabilityTile(symbol: "waveform.path.ecg", key: "auth.capability.telemetry")
                capabilityTile(symbol: "doc.text.magnifyingglass", key: "auth.capability.logs")
                capabilityTile(symbol: "chart.xyaxis.line", key: "auth.capability.analysis")
            }
        }
    }

    /// 製品特性を1件のタイルとして描画します。
    ///
    /// 責務: 1件の製品特性をアイコンとラベルを持つ計器風タイルへ変換します。
    /// - Parameters:
    ///   - symbol: 特性を補助するSF Symbol名。
    ///   - key: ローカライズ済み特性名のキー。
    /// - Returns: iOS向け製品特性タイル。
    private func capabilityTile(symbol: String, key: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// ログイン前に提示できる静的な信頼要素です。
    private var trustStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                trustItems
            }
            VStack(alignment: .leading, spacing: 8) {
                trustItems
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 3件の信頼要素ラベルです。
    @ViewBuilder
    private var trustItems: some View {
        trustItem(symbol: "lock.shield", key: "auth.trust.private")
        trustItem(symbol: "apple.logo", key: "auth.trust.apple_only")
        trustItem(symbol: "externaldrive", key: "auth.trust.local")
    }

    /// 静的な信頼要素を1件描画します。
    ///
    /// 責務: 1件のログイン前説明をアイコン付きの小型ラベルへ変換します。
    /// - Parameters:
    ///   - symbol: 説明を補助するSF Symbol名。
    ///   - key: ローカライズ済み説明文のキー。
    /// - Returns: iOS向け信頼要素ラベル。
    private func trustItem(symbol: String, key: LocalizedStringKey) -> some View {
        Label {
            Text(key)
                .lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor.opacity(0.9))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.66))
    }

    // MARK: - Authentication

    /// 一列構成の画面下部へ固定する認証パネルです。
    ///
    /// 責務: 認証操作と同意案内をSafe Area下端に沿うパネルへ配置します。
    /// - Parameter metrics: パネル幅と余白を決める寸法。
    /// - Returns: 画面下部固定の認証パネル。
    private func dockedAuthenticationPanel(metrics: IOSLoginMetrics) -> some View {
        VStack(spacing: 12) {
            authenticationControls
            consentHint
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: metrics.contentMaxWidth)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 24, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 二列構成や拡大文字で使う、見出し付きの認証カードです。
    private var authenticationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
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
            VStack(alignment: .leading, spacing: 8) {
                trustItems
            }
            consentHint
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
    }

    /// 現在の認証段階に対応する失敗表示、進捗、ログイン操作です。
    private var authenticationControls: some View {
        VStack(spacing: 10) {
            if state.phase == .signedOut, let failure = state.failure {
                failureBanner(for: failure)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .frame(minHeight: 54)
        }
    }

    /// Appleアカウントでのログインまたは再試行を通知するボタンです。
    private var signInButton: some View {
        Button {
            send(state.failure == nil ? .loginTapped : .retryTapped)
        } label: {
            Label("auth.continue_with_apple", systemImage: "apple.logo")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.25), radius: 18, y: 6)
        .accessibilityIdentifier("ios-auth-login")
    }

    /// ボタンと同じ高さを保つ進捗表示です。
    ///
    /// 責務: 1件の進行中段階をレイアウトを揺らさない進捗表示へ変換します。
    /// - Parameter key: 進行中段階を説明するローカライズ文字列キー。
    /// - Returns: ログインボタンと同寸の進捗表示。
    private func progressIndicator(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text(key)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 認証失敗と再試行可能であることを伝える警告表示です。
    ///
    /// 責務: 1件の認証失敗をオレンジの小さな警告バナーへ変換します。
    /// - Parameter failure: Applicationが保持する区別可能な認証失敗。
    /// - Returns: iOS向け認証失敗バナー。
    private func failureBanner(for failure: AuthenticationFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WarningTriangleIcon(size: 14)
            Text(failureMessage(for: failure))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// ログイン前に免責事項への同意が必要であることを伝える案内です。
    private var consentHint: some View {
        Text("auth.consent_hint")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Applicationの認証失敗をローカライズ表示キーへ変換します。
    ///
    /// 責務: 1件の認証失敗をiOSログイン画面の再試行メッセージへ写像します。
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
