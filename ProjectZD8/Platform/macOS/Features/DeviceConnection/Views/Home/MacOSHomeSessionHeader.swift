#if os(macOS)
import SwiftUI

/// 接続中のmacOSホーム上端で、車両名、記録状態と経過時間、切断操作をまとめた見出しです。
struct MacOSHomeSessionHeader: View {
    /// 表示するセッション見出しの内容です。
    let content: HomeSessionHeaderContent
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 切断要求を通知するクロージャです。
    let onDisconnect: () -> Void

    /// 車両名と記録状態を左に、切断ボタンを右に並べます。狭い時は縦に並べます。
    ///
    /// 責務: 1件のセッション見出し内容を枠付きの見出しへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20 * scale) {
                identity
                Spacer(minLength: 12 * scale)
                disconnectButton
            }
            VStack(alignment: .leading, spacing: 16 * scale) {
                identity
                disconnectButton
            }
        }
        .padding(22 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.accentColor.opacity(0.18), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-home-session-header")
    }

    /// 車の記号、車両名、記録状態です。
    private var identity: some View {
        HStack(alignment: .center, spacing: 18 * scale) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 26 * scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 58 * scale, height: 58 * scale)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6 * scale) {
                vehicleName
                    .font(.system(size: 24 * scale, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("macos-home-vehicle-name")
                recordingStatus
            }
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
            MacOSHomeSessionHeaderRecordingLabel(startedAt: startedAt, scale: scale)
        case .notRecording:
            Label {
                Text(LocalizedStringKey(HomeRecordingStatus.notRecordingKey))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.system(size: 12 * scale, weight: .semibold))
            .accessibilityIdentifier("macos-home-recording-status")
        }
    }

    /// 通信を安全に終える切断ボタンです。終了処理中は押せません。
    private var disconnectButton: some View {
        Button(role: .destructive, action: onDisconnect) {
            Label("home.action.disconnect", systemImage: "stop.circle")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!content.isDisconnectEnabled)
        .accessibilityIdentifier("macos-home-disconnect")
    }
}
#endif
