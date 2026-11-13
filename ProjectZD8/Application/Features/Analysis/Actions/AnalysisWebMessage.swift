import Foundation

/// Webワークベンチからネイティブへ届くメッセージです。
nonisolated enum AnalysisWebMessage: Equatable, Sendable {
    /// ページの初期化が済み、ホストからの設定を受け取れる。
    case ready
    /// CSV・PNGの書き出し。
    case export(AnalysisExportRequest)
    /// 比較用に別セッションを追加したい。
    case requestSession
    /// セッション選択UIを開きたい。
    case openSessionPicker
    /// 長期傾向を要求する。
    case requestTrend(includeDemo: Bool)
    /// 比較セッションを外したい。
    case removeSession(SessionID)
    /// 失敗表示を閉じたい。
    case dismissFailure

    /// メッセージが不正だった理由です。
    enum DecodingFailure: Error, Equatable {
        case notADictionary
        case unknownType(String)
        case missingField(String)
        case invalidField(String)
    }

    /// `WKScriptMessage.body` に相当するJSON互換値から復元します。
    ///
    /// 責務: 信頼できないWeb入力を検証し、型付きメッセージへ変換します。
    /// - Throws: 形式不正は `DecodingFailure`。
    static func decode(_ body: Any) throws -> AnalysisWebMessage {
        guard let dictionary = body as? [String: Any] else { throw DecodingFailure.notADictionary }
        guard let type = dictionary["type"] as? String else { throw DecodingFailure.missingField("type") }
        switch type {
        case "ready":
            return .ready
        case "requestSession":
            return .requestSession
        case "openSessionPicker":
            return .openSessionPicker
        case "requestTrend":
            return .requestTrend(includeDemo: dictionary["includeDemo"] as? Bool ?? false)
        case "dismissFailure":
            return .dismissFailure
        case "removeSession":
            guard let raw = dictionary["id"] as? String else { throw DecodingFailure.missingField("id") }
            guard let uuid = UUID(uuidString: raw) else { throw DecodingFailure.invalidField("id") }
            return .removeSession(SessionID(rawValue: uuid))
        case "export":
            guard let filename = dictionary["filename"] as? String else { throw DecodingFailure.missingField("filename") }
            guard let mimeType = dictionary["mimeType"] as? String else { throw DecodingFailure.missingField("mimeType") }
            guard let base64 = dictionary["base64"] as? String else { throw DecodingFailure.missingField("base64") }
            guard let data = Data(base64Encoded: base64) else { throw DecodingFailure.invalidField("base64") }
            guard Self.allowedExportTypes.contains(mimeType) else { throw DecodingFailure.invalidField("mimeType") }
            return .export(AnalysisExportRequest(filename: Self.sanitizedFilename(filename), mimeType: mimeType, data: data))
        default:
            throw DecodingFailure.unknownType(type)
        }
    }

    /// 責務: メッセージに対応する画面操作を返します。`ready` のようにホストが直接処理するものは `nil` です。
    var action: AnalysisAction? {
        switch self {
        case .ready: nil
        case .export(let request): .receiveExport(request)
        case .requestSession: .requestSessionPicker(.addComparison)
        case .openSessionPicker: .requestSessionPicker(.replacePrimary)
        case .requestTrend(let includeDemo): .requestTrend(includeDemo: includeDemo)
        case .removeSession(let id): .removeSession(id)
        case .dismissFailure: .dismissFailure
        }
    }

    /// 書き出しを許可するMIMEタイプです。
    private static let allowedExportTypes: Set<String> = ["text/csv", "image/png"]

    /// 責務: パス区切りや制御文字を除いた安全なファイル名にします。
    static func sanitizedFilename(_ name: String) -> String {
        let cleaned = name.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.value < 0x20 { return "_" }
            return Character(scalar)
        }
        let result = String(cleaned).trimmingCharacters(in: .whitespaces)
        return result.isEmpty || result.hasPrefix(".") ? "export" + result : result
    }
}
