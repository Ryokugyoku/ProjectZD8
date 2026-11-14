/// セッション行に表示するRawログ保管状態バッジの内容です。
struct ConnectionHistoryRawStatusBadge: Equatable, Sendable {
    /// バッジ文言のローカライズキーです。View 側で `LocalizedStringKey` に包みます。
    let titleKey: String
    /// バッジに添えるSF Symbol名です。
    let systemImage: String
    /// バッジの意味上の色調です。
    let tone: ConnectionHistoryStatusTone

    /// 文言キー、シンボル、色調を固定して生成します。
    ///
    /// 責務: 1件のバッジ表示値を不変の組へまとめます。
    /// - Parameters:
    ///   - titleKey: バッジ文言のローカライズキー。
    ///   - systemImage: バッジに添えるSF Symbol名。
    ///   - tone: バッジの意味上の色調。
    init(titleKey: String, systemImage: String, tone: ConnectionHistoryStatusTone) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tone = tone
    }

    /// CloudKit転送状態に対応するバッジを生成します。
    ///
    /// 責務: 1件のCloudKit転送状態を文言キー、シンボル、色調へ変換します。
    /// - Parameter cloudState: 表示するCloudKit転送状態。
    init(cloudState: ConnectionSessionCloudSyncState) {
        switch cloudState {
        case .notUploaded:
            self.init(titleKey: "history.raw.cloud.not_uploaded", systemImage: "icloud.slash", tone: .neutral)
        case .pending:
            self.init(titleKey: "history.raw.cloud.pending", systemImage: "icloud.and.arrow.up", tone: .caution)
        case .uploaded:
            self.init(titleKey: "history.raw.cloud.uploaded", systemImage: "checkmark.icloud.fill", tone: .positive)
        case .failed:
            self.init(titleKey: "history.raw.cloud.failed", systemImage: "exclamationmark.icloud.fill", tone: .critical)
        }
    }

    /// 現在端末のRaw保管状態に対応するバッジを生成します。
    ///
    /// 責務: 1件のローカルRaw状態を未記録、保存済み、除去済みの文言キー、シンボル、色調へ変換します。
    /// - Parameter localState: 表示する現在端末のRaw保管状態。
    init(localState: ConnectionSessionLocalRawState) {
        switch localState {
        case .empty:
            self.init(titleKey: "history.raw.local.empty", systemImage: "minus.circle", tone: .neutral)
        case .available:
            self.init(titleKey: "history.raw.local.available", systemImage: "checkmark.circle.fill", tone: .informative)
        case .removed:
            self.init(titleKey: "history.raw.local.removed", systemImage: "icloud.and.arrow.down", tone: .neutral)
        }
    }
}
