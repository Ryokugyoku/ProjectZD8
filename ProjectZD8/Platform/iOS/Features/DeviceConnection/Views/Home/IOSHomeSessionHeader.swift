#if os(iOS)
import SwiftUI

/// 接続中のホーム上端で、車両名、記録状態と経過時間、切断操作をまとめた見出しです。
struct IOSHomeSessionHeader: View {
    /// 表示するセッション見出しの内容です。
    let content: HomeSessionHeaderContent
    /// 切断要求を通知するクロージャです。
    let onDisconnect: () -> Void

    /// 車両名の行と、記録状態・切断ボタンの行を縦に並べます。
    ///
    /// 責務: 1件のセッション見出し内容を枠付きの見出しへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IOSHomeMetrics.sessionHeaderCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            vehicleRow
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    recordingStatus
                    Spacer(minLength: 0)
                    disconnectButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    recordingStatus
                    disconnectButton
                }
            }
        }
        .padding(IOSHomeMetrics.sessionHeaderPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.accentColor.opacity(IOSHomeMetrics.cardStrokeOpacity), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-home-session-header")
    }

    /// 車の記号と車両名の行です。
    private var vehicleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            vehicleName
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("ios-home-vehicle-name")
        }
    }

    /// 登録名はそのまま、未登録・名称未設定は文言で出す車両名です。
    private var vehicleName: Text {
        switch content.vehicle {
        case let .named(name):
            Text(verbatim: name)
        case .unregistered, .unnamed:
            Text(LocalizedStringKey(content.vehicle.localizationKey ?? ""))
        }
    }

    /// 記録中なら印と経過時間、記録していなければその旨を出します。
    @ViewBuilder
    private var recordingStatus: some View {
        switch content.recording {
        case let .recording(startedAt):
            IOSHomeSessionHeaderRecordingLabel(startedAt: startedAt)
        case .notRecording:
            Label {
                Text(LocalizedStringKey(HomeRecordingStatus.notRecordingKey))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("ios-home-recording-status")
        }
    }

    /// 通信を安全に終える切断ボタンです。終了処理中は押せません。
    private var disconnectButton: some View {
        Button(role: .destructive, action: onDisconnect) {
            Label("home.action.disconnect", systemImage: "stop.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .disabled(!content.isDisconnectEnabled)
        .accessibilityIdentifier("ios-home-disconnect")
    }
}
#endif
