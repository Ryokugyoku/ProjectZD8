import SwiftUI

/// 車両写真の枠です。共有コンテナの写真が読めればそれを、読めなければ車のアイコンのプレースホルダーを描きます。
struct RecordingSessionLiveActivityVehiclePhotoView: View {
    /// 共有コンテナ内の車両写真のファイル名です。無ければ `nil` です。
    let fileName: String?
    /// 正方形の枠の一辺です。
    let size: CGFloat

    /// 写真またはプレースホルダーを角丸の正方形に収めて描きます。
    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: RecordingSessionLiveActivityMetrics.photoCornerRadius))
    }

    /// 写真が読めれば写真、読めなければプレースホルダーです。
    @ViewBuilder
    private var content: some View {
        if let image = RecordingSessionLiveActivityPhotoLoader.image(fileName: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(RecordingSessionLiveActivityMetrics.placeholderBackgroundOpacity)
                Image(systemName: RecordingSessionLiveActivityStatusSymbol.photoPlaceholderName)
                    .font(.title3)
                    .foregroundStyle(RecordingSessionLiveActivityPalette.accent)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("live_activity.photo.placeholder"))
        }
    }
}
