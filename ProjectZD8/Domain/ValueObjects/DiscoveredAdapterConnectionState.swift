import Foundation

/// アダプター候補を検出した時点のシステム接続状態を表します。
enum DiscoveredAdapterConnectionState: String, Equatable, Sendable {
    /// 周辺機器が切断されています。
    case disconnected

    /// 周辺機器へ接続中です。
    case connecting

    /// 周辺機器へ接続済みです。
    case connected

    /// 周辺機器を切断中です。
    case disconnecting

    /// システムから接続状態を判定できません。
    case unknown
}
