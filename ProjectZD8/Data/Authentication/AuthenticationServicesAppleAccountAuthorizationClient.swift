import AuthenticationServices
import Foundation

/// `AuthenticationServices`を使ってAppleアカウント認証を実行します。
@MainActor
final class AuthenticationServicesAppleAccountAuthorizationClient: NSObject,
    AppleAccountAuthorizationPort,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    /// システム認証UIを関連付ける現在の表示ウインドウを解決します。
    private let presentationAnchorProvider: () -> ASPresentationAnchor?

    /// 実行中の認証UIへ固定した表示ウインドウです。
    private var activePresentationAnchor: ASPresentationAnchor?

    /// 実行中のApple認証要求を待機する継続です。
    private var authorizationContinuation: CheckedContinuation<AppleAccountSession, Error>?

    /// 認証UIを表示するウインドウ解決処理を注入します。
    ///
    /// 責務: Apple認証UIを1件のプラットフォーム表示ウインドウへ結び付けます。
    /// - Parameter presentationAnchorProvider: 現在表示中の認証UI用ウインドウを返す処理。
    init(presentationAnchorProvider: @escaping () -> ASPresentationAnchor?) {
        self.presentationAnchorProvider = presentationAnchorProvider
    }

    /// Appleのシステム認証UIを提示してアプリ固有セッションを返します。
    ///
    /// 責務: 1回のApple ID認証要求を`ASAuthorizationController`で実行します。
    /// - Returns: Appleがこのアプリへ割り当てたユーザー識別子を持つセッション。
    /// - Throws: 表示ウインドウがない場合、キャンセルされた場合、または認証に失敗した場合は `AppleAccountAuthorizationError`。
    func authorize() async throws -> AppleAccountSession {
        guard authorizationContinuation == nil else {
            throw AppleAccountAuthorizationError.unavailable
        }
        guard let presentationAnchor = presentationAnchorProvider() else {
            throw AppleAccountAuthorizationError.unavailable
        }

        activePresentationAnchor = presentationAnchor
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            controller.performRequests()
        }
    }

    /// 保存済みユーザー識別子の現在のApple資格状態を返します。
    ///
    /// 責務: 1件のAppleユーザー識別子を`ASAuthorizationAppleIDProvider`の資格状態へ照合します。
    /// - Parameter userIdentifier: 以前の認証で保存したアプリ固有ユーザー識別子。
    /// - Returns: Appleが返した現在の資格状態。
    /// - Throws: Apple資格状態を取得できない場合は `AppleAccountAuthorizationError`。
    func credentialState(for userIdentifier: String) async throws -> AppleAccountCredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, error in
                if error != nil {
                    continuation.resume(throwing: AppleAccountAuthorizationError.unavailable)
                    return
                }

                switch state {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked:
                    continuation.resume(returning: .revoked)
                case .notFound:
                    continuation.resume(returning: .notFound)
                case .transferred:
                    continuation.resume(returning: .transferred)
                @unknown default:
                    continuation.resume(throwing: AppleAccountAuthorizationError.failed)
                }
            }
        }
    }

    /// Apple認証成功をアプリ固有セッションへ変換します。
    ///
    /// 責務: `ASAuthorizationAppleIDCredential`のユーザー識別子で実行中要求を完了します。
    /// - Parameters:
    ///   - controller: 認証結果を生成したシステムコントローラー。
    ///   - authorization: Appleが返した認証結果。
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            !credential.user.isEmpty
        else {
            finishAuthorization(with: .failure(AppleAccountAuthorizationError.failed))
            return
        }
        finishAuthorization(
            with: .success(AppleAccountSession(userIdentifier: credential.user))
        )
    }

    /// Apple認証失敗をApplicationの区別可能なエラーへ変換します。
    ///
    /// 責務: システム認証エラーで実行中のApple認証要求を1件終了します。
    /// - Parameters:
    ///   - controller: 認証失敗を生成したシステムコントローラー。
    ///   - error: Apple認証UIが返したシステムエラー。
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finishAuthorization(with: .failure(AppleAccountAuthorizationError.cancelled))
        } else {
            finishAuthorization(with: .failure(AppleAccountAuthorizationError.failed))
        }
    }

    /// 実行中のApple認証UIを関連付ける表示ウインドウを返します。
    ///
    /// 責務: `ASAuthorizationController`へ認証開始時に固定した表示ウインドウを提供します。
    /// - Parameter controller: 表示ウインドウを要求する認証コントローラー。
    /// - Returns: 認証開始時に解決したプラットフォーム表示ウインドウ。
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let activePresentationAnchor else {
            preconditionFailure("Apple認証の表示ウインドウが失われました。")
        }
        return activePresentationAnchor
    }

    /// 実行中の継続を指定結果で一度だけ完了します。
    ///
    /// 責務: 1件のApple認証結果を待機中のApplication要求へ返します。
    /// - Parameter result: Applicationへ返す認証セッションまたは失敗。
    private func finishAuthorization(with result: Result<AppleAccountSession, Error>) {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        activePresentationAnchor = nil
        continuation?.resume(with: result)
    }
}
