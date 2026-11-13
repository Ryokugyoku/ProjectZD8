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
    /// 責務: iOS認証状態をコックピットコンセプトのログイン画面へ表示します。
    var body: some View {
        GeometryReader { proxy in
            let metrics = IOSLoginMetrics.resolve(
                size: proxy.size,
                usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
            )

            ZStack {
                loginBackground
                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        brandHeader
                        cockpitHero(diameter: metrics.heroDiameter)
                        introduction
                        trustStrip
                        authenticationPanel
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.usesCompactHeight ? 20 : 34)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
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

    /// 深い車載コックピットを想起させる背景です。
    private var loginBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.055, blue: 0.065),
                    Color(red: 0.025, green: 0.035, blue: 0.055),
                    Color(red: 0.018, green: 0.02, blue: 0.028)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 150, y: -240)
            Circle()
                .fill(Color.orange.opacity(0.055))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -170, y: 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// 製品名とコンセプトラベルを表示するブランドヘッダーです。
    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
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
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
                    .offset(x: 12, y: -11)
            }
            .frame(width: 48, height: 48)
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(0.3), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("RevTorque Insight")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .tracking(0.2)
                Text("auth.eyebrow")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1.1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    /// 車両データとの接続を抽象化したコックピット意匠です。
    ///
    /// 責務: 指定直径でログイン画面の中心となる静的な計器意匠を描画します。
    /// - Parameter diameter: 利用可能領域から解決した意匠の直径。
    /// - Returns: 運用状態を示さない装飾的な計器表示。
    private func cockpitHero(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 18)
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor, .cyan, Color.accentColor.opacity(0.25)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
            Circle()
                .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                .padding(22)
            HStack(spacing: -diameter * 0.03) {
                Text("R")
                    .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: diameter * 0.25, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            Circle()
                .fill(.orange)
                .frame(width: diameter * 0.035, height: diameter * 0.035)
                .offset(x: diameter * 0.20, y: -diameter * 0.035)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.accentColor.opacity(0.2), radius: 24)
        .accessibilityHidden(true)
    }

    /// ログイン画面の価値提案を表示する説明領域です。
    private var introduction: some View {
        VStack(spacing: 10) {
            Text("auth.title")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("auth.subtitle")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ログイン前に提示できる静的な信頼要素です。
    private var trustStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                trustItem(symbol: "lock.shield", key: "auth.trust.private")
                trustItem(symbol: "apple.logo", key: "auth.trust.apple_only")
                trustItem(symbol: "externaldrive", key: "auth.trust.local")
            }
            VStack(spacing: 9) {
                trustItem(symbol: "lock.shield", key: "auth.trust.private")
                trustItem(symbol: "apple.logo", key: "auth.trust.apple_only")
                trustItem(symbol: "externaldrive", key: "auth.trust.local")
            }
        }
    }

    /// 現在の認証段階に対応する進捗、失敗、ログイン操作を表示します。
    private var authenticationPanel: some View {
        VStack(spacing: 14) {
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
                        .multilineTextAlignment(.center)
                }
                Button {
                    send(state.failure == nil ? .loginTapped : .retryTapped)
                } label: {
                    Label("auth.continue_with_apple", systemImage: "apple.logo")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityIdentifier("ios-auth-login")
            case .signedIn:
                EmptyView()
            }
            Text("auth.consent_hint")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(.ultraThinMaterial.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    /// 静的な信頼要素を1件描画します。
    ///
    /// 責務: 1件のログイン前説明をアイコン付きの小型ラベルへ変換します。
    /// - Parameters:
    ///   - symbol: 説明を補助するSF Symbol名。
    ///   - key: ローカライズ済み説明文のキー。
    /// - Returns: iOS向け信頼要素ラベル。
    private func trustItem(symbol: String, key: LocalizedStringKey) -> some View {
        Label(key, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: Capsule())
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
