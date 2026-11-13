#if os(macOS)
import SwiftUI

/// 記録終了後に、最後の値が古いことと終了理由を知らせるバナー。
struct MacOSDriveStaleBanner: View {
    let reason: SessionEndReason
    let onClear: () -> Void

    var body: some View {
        InlineBanner(
            .info,
            title: Text("drive.stale.title"),
            message: Text(LocalizedStringKey(DriveSessionPresentation.endReasonKey(reason))),
            action: InsightAction(Text("drive.stale.clear"), handler: onClear)
        )
    }
}
#endif
