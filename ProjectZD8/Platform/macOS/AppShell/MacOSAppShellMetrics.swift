#if os(macOS)
import SwiftUI

/// macOS シェルと各画面で共有する寸法。
enum MacOSAppShellMetrics {
    /// サイドバーの最小・理想・最大幅。
    static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (190, 220, 280)
    /// ウインドウの最小サイズ。
    static let windowMinimumSize = CGSize(width: 980, height: 640)
    /// 画面本文の最大幅(読みやすさのため)。
    static let contentMaxWidth: CGFloat = 1_200
    /// 画面本文の周囲余白。
    static let contentPadding: CGFloat = 24
    /// 設定ウインドウの幅。
    static let settingsWidth: CGFloat = 560
    /// シート(登録・アダプター選択)の幅。
    static let sheetWidth: CGFloat = 460
    /// 大型エディタシートの幅と最小高さ。
    static let editorSheetWidth: CGFloat = 640
    static let editorSheetMinHeight: CGFloat = 560
    /// 録画インジケーターの直径。
    static let recordingDotSize: CGFloat = 8
}
#endif
