#if os(iOS)
import ActivityKit

/// `RecordingSessionActivityAttributes` を ActivityKit の Live Activity の属性として使えるようにする iOS 専用の準拠です。
///
/// 準拠以外の定義(値型・定数・写真の場所)は Foundation だけのファイルに置き、macOS の単体テストからも検証できるようにします。
/// `ContentState` は入れ子の `RecordingSessionActivityAttributes.ContentState` がそのまま関連型になります。
extension RecordingSessionActivityAttributes: ActivityAttributes {}
#endif
