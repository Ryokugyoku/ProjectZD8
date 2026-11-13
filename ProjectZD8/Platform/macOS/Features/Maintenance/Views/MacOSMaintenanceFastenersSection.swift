#if os(macOS)
import SwiftUI

/// 重整備の締結部セクション(グループ・個々の締結証跡・写真の紐付け・確認)。
struct MacOSMaintenanceFastenersSection: View {
    let draft: MaintenanceDraft
    let photoData: [PhotoID: Data]
    let issues: [MaintenanceDraftIssue]
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Section {
            ForEach(draft.fastenerGroups) { group in
                groupView(group)
                Divider()
            }
            Button {
                send(.fastenerGroupAdded)
            } label: {
                Label("maintenance.fastener.addGroup", systemImage: "plus")
            }
        } header: {
            Text("maintenance.section.fasteners")
        }
    }

    private func groupView(_ group: MaintenanceFastenerGroup) -> some View {
        VStack(alignment: .leading, spacing: InsightSpacing.sm) {
            HStack {
                TextField(text: groupBinding(group, \.name)) { Text("maintenance.fastener.groupName") }
                Button(role: .destructive) {
                    send(.fastenerGroupRemoved(group.id))
                } label: {
                    Label("maintenance.fastener.removeGroup", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            TextField(text: groupBinding(group, \.location)) { Text("maintenance.fastener.location") }
            HStack {
                TextField(value: groupBinding(group, \.expectedCount), format: .number) { Text("maintenance.fastener.expected") }
                TextField(value: groupBinding(group, \.removedCount), format: .number) { Text("maintenance.fastener.removed") }
            }
            TextField(text: groupBinding(group, \.removalNotes), axis: .vertical) { Text("maintenance.fastener.removalNotes") }
                .lineLimit(1...4)
            photoLinks(
                titleKey: "maintenance.fastener.removalPhotos",
                linked: group.removalPhotoIDs,
                link: { send(.removalPhotoLinked(groupID: group.id, photoID: $0)) },
                unlink: { send(.removalPhotoUnlinked(groupID: group.id, photoID: $0)) }
            )

            ForEach(group.installations) { evidence in
                evidenceView(evidence, in: group)
            }
            Button {
                send(.fastenerAdded(groupID: group.id))
            } label: {
                Label("maintenance.fastener.add", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            if issues.contains(.fastenerGroupNameRequired(group.id)) || issues.contains(.fastenerValueInvalid(group.id)) {
                Text("maintenance.fastener.groupHasIssue")
                    .font(InsightTypography.footnote)
                    .foregroundStyle(InsightPalette.warning)
            }
        }
        .padding(.vertical, InsightSpacing.xs)
    }

    private func evidenceView(_ evidence: FastenerInstallationEvidence, in group: MaintenanceFastenerGroup) -> some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xs) {
            HStack {
                TextField(text: evidenceBinding(evidence, in: group, \.position)) { Text("maintenance.fastener.position") }
                TextField(value: evidenceBinding(evidence, in: group, \.torqueNewtonMeters), format: .number) {
                    Text("maintenance.fastener.torque")
                }
                Button(role: .destructive) {
                    send(.fastenerRemoved(groupID: group.id, evidenceID: evidence.id))
                } label: {
                    Label("maintenance.fastener.remove", systemImage: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            HStack {
                TextField(text: evidenceBinding(evidence, in: group, \.tool)) { Text("maintenance.fastener.tool") }
                TextField(text: evidenceBinding(evidence, in: group, \.tightenedBy)) { Text("maintenance.fastener.tightenedBy") }
            }
            TextField(text: evidenceBinding(evidence, in: group, \.notes), axis: .vertical) { Text("maintenance.fastener.notes") }
                .lineLimit(1...3)
            HStack {
                if let at = evidence.tightenedAt {
                    StatusBadge(Text("maintenance.fastener.confirmed"), tone: .positive, symbol: "checkmark.seal.fill")
                    Text(at, format: .dateTime.year().month().day().hour().minute())
                        .font(InsightTypography.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        send(.fastenerConfirmed(groupID: group.id, evidenceID: evidence.id))
                    } label: {
                        Label("maintenance.fastener.confirm", systemImage: "checkmark.seal")
                    }
                    StatusBadge(Text("maintenance.fastener.unconfirmed"), tone: .neutral)
                }
            }
            photoLinks(
                titleKey: "maintenance.fastener.photos",
                linked: evidence.photoIDs,
                link: { send(.fastenerPhotoLinked(groupID: group.id, evidenceID: evidence.id, photoID: $0)) },
                unlink: { send(.fastenerPhotoUnlinked(groupID: group.id, evidenceID: evidence.id, photoID: $0)) }
            )
        }
        .padding(InsightSpacing.sm)
        .background(RoundedRectangle(cornerRadius: InsightRadius.xs, style: .continuous).fill(InsightPalette.surface))
    }

    /// 責務: 下書きの写真を、紐付け済みサムネイルと「紐付け」メニューで表示する。
    private func photoLinks(
        titleKey: LocalizedStringKey,
        linked: [PhotoID],
        link: @escaping (PhotoID) -> Void,
        unlink: @escaping (PhotoID) -> Void
    ) -> some View {
        HStack(spacing: InsightSpacing.sm) {
            Text(titleKey).font(InsightTypography.footnote).foregroundStyle(.secondary)
            ForEach(linked, id: \.self) { id in
                Button {
                    unlink(id)
                } label: {
                    MacOSMaintenancePhotoThumbnail(data: photoData[id], size: 36)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "xmark.circle.fill").imageScale(.small).foregroundStyle(.white, .black.opacity(0.6))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("maintenance.photo.unlink"))
            }
            let unlinked = draft.photos.filter { !linked.contains($0.id) }
            if !unlinked.isEmpty {
                Menu {
                    ForEach(unlinked) { photo in
                        Button {
                            link(photo.id)
                        } label: {
                            if photo.caption.isEmpty {
                                Text(photo.capturedAt, format: .dateTime.month().day().hour().minute())
                            } else {
                                Text(verbatim: photo.caption)
                            }
                        }
                    }
                } label: {
                    Label("maintenance.photo.link", systemImage: "link")
                }
                .fixedSize()
            }
        }
    }

    private func groupBinding<Value>(_ group: MaintenanceFastenerGroup, _ keyPath: WritableKeyPath<MaintenanceFastenerGroup, Value>) -> Binding<Value> {
        Binding(
            get: { draft.fastenerGroups.first { $0.id == group.id }?[keyPath: keyPath] ?? group[keyPath: keyPath] },
            set: { value in
                var next = draft
                guard let index = next.fastenerGroups.firstIndex(where: { $0.id == group.id }) else { return }
                next.fastenerGroups[index][keyPath: keyPath] = value
                send(.draftChanged(next))
            }
        )
    }

    private func evidenceBinding<Value>(
        _ evidence: FastenerInstallationEvidence,
        in group: MaintenanceFastenerGroup,
        _ keyPath: WritableKeyPath<FastenerInstallationEvidence, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                draft.fastenerGroups.first { $0.id == group.id }?.installations.first { $0.id == evidence.id }?[keyPath: keyPath]
                    ?? evidence[keyPath: keyPath]
            },
            set: { value in
                var next = draft
                guard let groupIndex = next.fastenerGroups.firstIndex(where: { $0.id == group.id }),
                      let index = next.fastenerGroups[groupIndex].installations.firstIndex(where: { $0.id == evidence.id })
                else { return }
                next.fastenerGroups[groupIndex].installations[index][keyPath: keyPath] = value
                send(.draftChanged(next))
            }
        )
    }
}
#endif
