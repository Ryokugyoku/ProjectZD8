#if os(macOS)
import SwiftUI

/// 共通の状態バナーのトーンへmacOSの表示色を付加します。
extension LiveTelemetryStatusBannerTone {
    /// macOSのリアルタイム表示パネルの状態バナーに使う表示色です。
    var color: Color {
        switch self {
        case .active: .cyan
        case .healthy: .green
        case .warning: .orange
        }
    }
}
#endif
