import SwiftUI

struct AddToPlaylistSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    private let favorites = FavoritesStore.shared
    @Environment(\.dismiss) private var dismiss

    let song: Song
    @State private var newName = ""
    @State private var showCreateField = false
    @State private var message: String?

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            List {
                if auth.playlists.isEmpty {
                    Text("暂无歌单，请先创建一个")
                        .foregroundStyle(Color.beansComment)
                } else {
                    Section("选择歌单") {
                        ForEach(auth.playlists) { playlist in
                            Button {
                                Task { await add(to: playlist) }
                            } label: {
                                HStack(spacing: 12) {
                                    CoverImage(url: playlist.coverURL, size: 38, cornerRadius: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(BeansFont.appFont(15))
                                            .foregroundStyle(Color.beansLabel)
                                            .lineLimit(1)
                                        Text(beansSongCountText(playlist.trackCount))
                                            .font(BeansFont.appFont(11))
                                            .foregroundStyle(Color.beansComment)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                if showCreateField {
                    Section("新建歌单") {
                        TextField("歌单名称", text: $newName)
                            .submitLabel(.done)
                        Button {
                            Task { await createAndAdd() }
                        } label: {
                            Text("创建并添加")
                                .font(BeansFont.appFont(15, .semibold))
                                .foregroundStyle(Color.beansAmber)
                        }
                    }
                } else {
                    Button {
                        showCreateField = true
                    } label: {
                        Label("新建歌单", systemImage: "plus.circle")
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansSage)
                    }
                }
            }
            .navigationTitle("添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func add(to playlist: Playlist) async {
        message = "网易云音乐已移除，无法添加到云端歌单"
    }

    private func createAndAdd() async {
        message = "网易云音乐已移除，无法创建云端歌单"
    }
}
