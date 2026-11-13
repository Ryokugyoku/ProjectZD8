import Foundation

/// PID定義の名称キーを現在の言語の表示名へ解決する契約です。
nonisolated protocol AnalysisPIDNamePort: Sendable {
    /// 責務: 名称のローカライズキーを現在の言語の表示名へ解決します。
    func displayName(forKey key: String) -> String
}

/// アプリのString Catalogから表示名を解決します。
nonisolated struct BundleAnalysisPIDNameResolver: AnalysisPIDNamePort {
    private let bundle: Bundle

    /// 解決元のバンドルを指定して生成します。
    ///
    /// 責務: 名称解決に使うString Catalogの所在を固定します。
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// 責務: キーをString Catalogで解決します。未登録なら、キーそのものを返します。
    func displayName(forKey key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }
}
