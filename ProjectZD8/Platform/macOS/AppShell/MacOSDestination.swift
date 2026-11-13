#if os(macOS)
import SwiftUI

/// サイドバーの遷移先。
enum MacOSDestination: String, CaseIterable, Identifiable, Hashable {
    case drive
    case logs
    case analysis
    case garage
    case maintenance

    var id: String { rawValue }

    /// サイドバー・メニューに出す文言のキー。
    var titleKey: LocalizedStringKey {
        switch self {
        case .drive: "shell.destination.drive"
        case .logs: "shell.destination.logs"
        case .analysis: "shell.destination.analysis"
        case .garage: "shell.destination.garage"
        case .maintenance: "shell.destination.maintenance"
        }
    }

    /// SF Symbols 名。
    var symbol: String {
        switch self {
        case .drive: "gauge.with.dots.needle.67percent"
        case .logs: "list.bullet.rectangle"
        case .analysis: "chart.xyaxis.line"
        case .garage: "car.2"
        case .maintenance: "wrench.and.screwdriver"
        }
    }

    /// ⌘ と組み合わせる数字キー。
    var shortcutKey: KeyEquivalent {
        switch self {
        case .drive: "1"
        case .logs: "2"
        case .analysis: "3"
        case .garage: "4"
        case .maintenance: "5"
        }
    }
}
#endif
