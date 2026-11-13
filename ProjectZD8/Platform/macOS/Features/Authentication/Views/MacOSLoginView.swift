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
    /// 責務: macOS認証状態を落ち着いた自動車コックピットのログイン画面へ表示します。
    var body: some View {
        GeometryReader { proxy in
            let metrics = MacOSLoginMetrics.resolve(
                size: proxy.size,
                usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
            )

            ZStack {
                loginBackground
                if metrics.usesStackedLayout {
                    stackedLayout(metrics: metrics)
                } else {
                    desktopLayout(metrics: metrics)
                }
            }
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

    /// 標準以上のウインドウでブランドと認証操作を左右に分けて描画します。
    ///
    /// 責務: macOSログイン内容を横長ウインドウ向けの二列構成へ配置します。
    /// - Parameter metrics: 現在のウインドウ寸法から解決した表示規則。
    /// - Returns: ブランド領域と認証パネルを持つmacOS標準構成。
    private func desktopLayout(metrics: MacOSLoginMetrics) -> some View {
        HStack(spacing: metrics.outerPadding) {
            VStack(alignment: .leading, spacing: 22 * metrics.scale) {
                brandHeader(scale: metrics.scale)
                Spacer(minLength: 10)
                HStack(spacing: 34 * metrics.scale) {
                    cockpitHero(diameter: metrics.heroDiameter)
                    introduction(alignment: .leading, scale: metrics.scale)
                }
                Spacer(minLength: 10)
                capabilityStrip(scale: metrics.scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            authenticationPanel
                .frame(maxWidth: metrics.panelMaxWidth)
        }
        .padding(metrics.outerPadding)
    }

    /// 小さいウインドウまたは拡大文字で全内容を縦積みにして描画します。
    ///
    /// 責務: macOSログイン内容を見切れないスクロール可能な一列構成へ配置します。
    /// - Parameter metrics: 現在のウインドウ寸法から解決した表示規則。
    /// - Returns: 最小ウインドウでも操作可能なmacOSコンパクト構成。
    private func stackedLayout(metrics: MacOSLoginMetrics) -> some View {
        ScrollView {
            VStack(spacing: 18 * metrics.scale) {
                brandHeader(scale: metrics.scale)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 28) {
                        cockpitHero(diameter: metrics.heroDiameter)
                        introduction(alignment: .leading, scale: metrics.scale)
                    }
                    VStack(spacing: 16) {
                        cockpitHero(diameter: metrics.heroDiameter)
                        introduction(alignment: .center, scale: metrics.scale)
                    }
                }
                authenticationPanel
                    .frame(maxWidth: metrics.panelMaxWidth)
                capabilityStrip(scale: metrics.scale)
            }
            .padding(metrics.outerPadding)
            .frame(maxWidth: .infinity)
        }
    }

    /// 深い車載コックピットを想起させるmacOS背景です。
    private var loginBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.06),
                    Color(red: 0.025, green: 0.035, blue: 0.055),
                    Color(red: 0.016, green: 0.018, blue: 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.accentColor.opacity(0.17))
                .frame(width: 560, height: 560)
                .blur(radius: 130)
                .offset(x: 280, y: -280)
            Circle()
                .fill(Color.orange.opacity(0.05))
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .offset(x: -380, y: 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// 製品名とコンセプトラベルを指定倍率で表示します。
    ///
    /// 責務: macOSログイン画面のブランド識別情報を1件のヘッダーへ配置します。
    /// - Parameter scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: RevTorque InsightのmacOSブランドヘッダー。
    private func brandHeader(scale: CGFloat) -> some View {
        HStack(spacing: 13 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.015, green: 0.075, blue: 0.14),
                                Color(red: 0.025, green: 0.15, blue: 0.23)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 24 * scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Circle()
                    .fill(.orange)
                    .frame(width: 5 * scale, height: 5 * scale)
                    .offset(x: 13 * scale, y: -12 * scale)
            }
            .frame(width: 50 * scale, height: 50 * scale)
            .overlay {
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(0.3), radius: 14 * scale, y: 6 * scale)
            VStack(alignment: .leading, spacing: 2) {
                Text("RevTorque Insight")
                    .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                    .tracking(0.25)
                Text("auth.eyebrow")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.4)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 車両データとの接続を抽象化したコックピット意匠です。
    ///
    /// 責務: 指定直径でmacOSログイン画面の中心となる静的な計器意匠を描画します。
    /// - Parameter diameter: ウインドウ寸法から解決した意匠の直径。
    /// - Returns: 運用状態を示さない装飾的な計器表示。
    private func cockpitHero(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.07), lineWidth: max(12, diameter * 0.07))
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentColor.opacity(0.2), Color.accentColor, .cyan, Color.accentColor.opacity(0.2)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: max(4, diameter * 0.018), lineCap: .round)
                )
                .rotationEffect(.degrees(135))
            Circle()
                .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 9]))
                .padding(diameter * 0.12)
            HStack(spacing: -diameter * 0.03) {
                Text("R")
                    .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: diameter * 0.23, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            Circle()
                .fill(.orange)
                .frame(width: diameter * 0.035, height: diameter * 0.035)
                .offset(x: diameter * 0.19, y: -diameter * 0.03)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.accentColor.opacity(0.2), radius: 30)
        .accessibilityHidden(true)
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
            Text("auth.subtitle")
                .font(.system(size: 15 * scale, weight: .regular))
                .multilineTextAlignment(alignment)
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 静的な製品特性をウインドウ幅に応じて並べます。
    ///
    /// 責務: ログイン前に説明できる3件の製品特性をレスポンシブに表示します。
    /// - Parameter scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: 3件の静的な製品特性表示。
    private func capabilityStrip(scale: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10 * scale) {
                capabilityItem(symbol: "waveform.path.ecg", key: "auth.capability.telemetry", scale: scale)
                capabilityItem(symbol: "doc.text.magnifyingglass", key: "auth.capability.logs", scale: scale)
                capabilityItem(symbol: "chart.xyaxis.line", key: "auth.capability.analysis", scale: scale)
            }
            VStack(alignment: .leading, spacing: 8 * scale) {
                capabilityItem(symbol: "waveform.path.ecg", key: "auth.capability.telemetry", scale: scale)
                capabilityItem(symbol: "doc.text.magnifyingglass", key: "auth.capability.logs", scale: scale)
                capabilityItem(symbol: "chart.xyaxis.line", key: "auth.capability.analysis", scale: scale)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 現在の認証段階に対応する進捗、失敗、ログイン操作を表示します。
    private var authenticationPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("auth.panel.eyebrow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.2)
                Text("auth.panel.title")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("auth.panel.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(.white.opacity(0.1))

            switch state.phase {
            case .checkingSession:
                ProgressView("auth.checking")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
            case .signingIn:
                ProgressView("auth.signing_in")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
            case .signedOut:
                if let failure = state.failure {
                    Label(failureMessage(for: failure), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    send(state.failure == nil ? .loginTapped : .retryTapped)
                } label: {
                    Label("auth.continue_with_apple", systemImage: "apple.logo")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("macos-auth-login")
            case .signedIn:
                EmptyView()
            }

            Label("auth.trust.apple_only", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text("auth.consent_hint")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 32, y: 14)
    }

    /// 静的な製品特性を1件のmacOSラベルとして描画します。
    ///
    /// 責務: 1件の製品特性をアイコン付きの小型カードへ変換します。
    /// - Parameters:
    ///   - symbol: 特性を補助するSF Symbol名。
    ///   - key: ローカライズ済み特性名のキー。
    ///   - scale: ウインドウ寸法から解決した内部コンテンツ倍率。
    /// - Returns: macOS向け製品特性ラベル。
    private func capabilityItem(
        symbol: String,
        key: LocalizedStringKey,
        scale: CGFloat
    ) -> some View {
        Label(key, systemImage: symbol)
            .font(.system(size: 11 * scale, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 13 * scale)
            .padding(.vertical, 10 * scale)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
