import Foundation

/// セッション解析画面で切り替える表示単位です。iOS と macOS の解析画面で共有します。
nonisolated enum SessionLogAnalysisMode: String, CaseIterable, Identifiable, Sendable {
    /// 走行時間、距離、速度帯、回転域、部品・系統を確認します。
    case overview
    /// 1件のPIDを時間軸で確認します。
    case trends
    /// 2件のPIDの関係を散布図で確認します。
    case relationships

    /// Pickerで使用する安定識別子です。
    var id: String { rawValue }

    /// 表示モード名のローカライズキーです。View で `LocalizedStringKey` に変換します。
    var titleKey: String {
        switch self {
        case .overview: "analysis.mode.overview"
        case .trends: "analysis.mode.trends"
        case .relationships: "analysis.mode.relationships"
        }
    }
}
