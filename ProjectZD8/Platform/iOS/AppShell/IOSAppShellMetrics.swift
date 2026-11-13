#if os(iOS)
import SwiftUI

/// iOS 画面の寸法の基準値です。画面ごとの固有値はここへ集約します。
enum IOSAppShellMetrics {
    /// 回転数ゲージの目盛り範囲です。
    static let rpmRange: ClosedRange<Double> = 0...8000
    /// 回転数ゲージの警告帯(ピーク)です。
    static let rpmWarningZone: ClosedRange<Double> = 6500...8000
    /// 車速ゲージの目盛り範囲(km/h)です。
    static let speedRange: ClosedRange<Double> = 0...240
    /// 主要ゲージ1つの一辺です。
    static let gaugeSide: CGFloat = 148
    /// 主要ゲージの太さです。
    static let gaugeLineWidth: CGFloat = 12
    /// チャンネルタイルの最小幅です。iPhone は2列、iPad はそれ以上の列になります。
    static let channelTileMinimumWidth: CGFloat = 156
    /// チャンネルの履歴グラフの高さです。
    static let sparklineHeight: CGFloat = 36
    /// 一覧の車両アバターの大きさです。
    static let vehicleCardAvatarSize: CGFloat = 56
    /// 詳細ヘッダーの車両アバターの大きさです。
    static let vehicleDetailAvatarSize: CGFloat = 88
    /// 車両エディタの写真プレビューの大きさです。
    static let vehicleEditorPhotoSize: CGFloat = 96
    /// 整備写真サムネイルの一辺です。
    static let maintenancePhotoSide: CGFloat = 96
    /// 録画中インジケーターの点の大きさです。
    static let recordingDotSize: CGFloat = 10
    /// 分析画面を閉じるボタンの最小サイズです。
    static let closeButtonSide: CGFloat = 44
    /// 画面幅に対するコンテンツの最大幅(iPad で間延びさせない)です。
    static let contentMaxWidth: CGFloat = 820
    /// 登録・フィルタなどシートの最小高さです。
    static let sheetMinimumHeight: CGFloat = 420
}
#endif
