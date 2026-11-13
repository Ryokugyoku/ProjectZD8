#if os(macOS)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 写真ライブラリまたはファイルから画像のバイト列を取得するメニューボタン。
///
/// 取得した `Data` はそのままモデルへ渡す。読み込みに失敗した場合は自身の直下に理由を表示する。
struct MacOSPhotoSourceMenu: View {
    let title: LocalizedStringKey
    let onPicked: (Data) -> Void

    @State private var isLibraryPresented = false
    @State private var isFileImporterPresented = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xs) {
            Menu {
                Button {
                    isLibraryPresented = true
                } label: {
                    Label("photo.source.library", systemImage: "photo.on.rectangle")
                }
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("photo.source.file", systemImage: "folder")
                }
            } label: {
                Label(title, systemImage: "photo.badge.plus")
            }
            .fixedSize()
            .photosPicker(isPresented: $isLibraryPresented, selection: $libraryItem, matching: .images)
            .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image]) { result in
                loadFile(result)
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task { await loadLibraryItem(item) }
            }
            if loadFailed {
                Text("photo.source.loadFailed")
                    .font(InsightTypography.footnote)
                    .foregroundStyle(InsightPalette.critical)
            }
        }
    }

    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
                loadFailed = false
                onPicked(data)
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }

    private func loadFile(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else {
            if case .failure = result { loadFailed = true }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            loadFailed = data.isEmpty
            if !data.isEmpty { onPicked(data) }
        } catch {
            loadFailed = true
        }
    }
}
#endif
