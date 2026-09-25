import SwiftUI

/// 歌单内排序方式
enum PlaylistSortMode: String, CaseIterable, Identifiable {
    case original = "默认"
    case name = "歌名"
    case duration = "时长"
    var id: String { rawValue }
}

struct PlaylistView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var playlistFavorites = PlaylistFavoritesStore.shared

    let playlist: Playlist
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortMode: PlaylistSortMode = .original
    @AppStorage("beans.homeHeaderHideSort") private var hideSortButton = false
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var cacheAccountID: String {
        switch playlist.source {
        case .netease:
            return "\(auth.user?.uid ?? 0)"
        case .qq:
            return ""
        case .kugou:
            return KugouMusicAuth.shared.userId
        case .kuwo, .migu:
            return ""
        }
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if loading {
                    BeansDetailSongsLoadingState(coverSize: 96, rowCount: 10)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load(force: true) }
                    }
                } else {
                    List {
                        header
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        Section {
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true, playbackContext: displayedTracks, playbackIndex: index) {
                                    player.play(songs: displayedTracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            }
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: isNativeClean ? 18 : 14) {
                CoverImage(url: playlist.coverURL, size: 96, cornerRadius: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name)
                        .font(BeansFont.appFont(18, .bold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(2)
                    if !playlist.creatorName.isEmpty {
                        HStack(spacing: 6) {
                            CoverImage(url: playlist.creatorAvatarURL, size: 22, cornerRadius: 11)
                            Text(playlist.creatorName)
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    Text(beansSongCountText(tracks.count))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                    if playlist.playCount > 0 {
                        Text("播放 \(formatPlaylistPlayCount(playlist.playCount))")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                }
                Spacer(minLength: 0)
            }
            if !playlist.playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(playlist.playlistDescription)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                    player.play(songs: displayedTracks, startAt: 0)
                }
                GlassButton(title: "随机播放", systemName: "shuffle", forceLiquid: true) {
                    if !displayedTracks.isEmpty {
                        player.play(songs: displayedTracks, startAt: Int.random(in: 0..<displayedTracks.count))
                    }
                }
                // 收藏按钮紧随随机播放之后（紧凑圆形，避免三个宽按钮挤出屏幕）
                let isFavorited = playlistFavorites.contains(playlist)
                Button {
                    BeansHaptics.tap()
                    var target = playlist
                    if tracks.count > target.trackCount {
                        target.trackCount = tracks.count
                    }
                    playlistFavorites.toggle(target)
                } label: {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isFavorited ? Color(red: 0.95, green: 0.30, blue: 0.32) : Color.beansLabel)
                        .frame(width: 44, height: 44)
                        .background { BeansGlass(shape: Circle(), forceLiquid: true) }
                }
                .buttonStyle(GlassPressButtonStyle())
                .accessibilityLabel(isFavorited ? "取消收藏" : "收藏歌单")
            }
            if tracks.count > 1 {
                HStack {
                    Text(beansSongCountText(displayedTracks.count))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                if #available(iOS 26, *) {
                    NativeSearchBar(
                        text: $searchText,
                        placeholder: beansLocalized("搜索歌单内歌曲", "Search songs in playlist"),
                        onSubmit: { _ in }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.beansComment)
                        TextField(beansLocalized("搜索歌单内歌曲", "Search songs in playlist"), text: $searchText)
                            .font(BeansFont.appFont(14))
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.beansComment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                }

                if !hideSortButton {
                    Menu {
                        Picker("排序", selection: $sortMode) {
                            ForEach(PlaylistSortMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 38, height: 38)
                            .background { BeansSurface(shape: Circle()) }
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
        }
        .padding(14)
        .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
    }

    private func formatPlaylistPlayCount(_ count: Int) -> String {
        if count >= 100_000_000 { return String(format: "%.1f亿", Double(count) / 100_000_000) }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return "\(count)"
    }

    /// 歌单内搜索 + 排序后的列表
    private var displayedTracks: [Song] {
        var list = tracks
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !kw.isEmpty {
            list = list.filter { song in
                song.name.lowercased().contains(kw)
                    || song.artists.lowercased().contains(kw)
                    || song.album.lowercased().contains(kw)
            }
        }
        switch sortMode {
        case .original: break
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .duration:
            list.sort { $0.duration < $1.duration }
        }
        return list
    }

    private func load(force: Bool = false) async {
        let cache = SyncedPlaylistCache.shared
        if let cached = cache.cachedSongs(playlist: playlist, accountID: cacheAccountID) {
            tracks = cached.songs
            loading = false
            if !force, cache.isFresh(cached), !BeansNetworkStatus.shared.isReachable {
                return
            }
        } else {
            loading = true
        }
        errorMessage = nil
        BeansLogger.shared.log("歌单页面打开 source=\(playlist.source.rawValue) id=\(playlist.id) name=\(playlist.name) advertisedCount=\(playlist.trackCount)", level: .info)
        do {
            if playlist.source == .kugou {
                tracks = try await KugouMusicAPI.shared.playlistSongs(playlist: playlist)
            } else if playlist.source == .qq || playlist.source == .netease {
                // QQ / 网易云音乐已移除：仅展示已同步缓存，不再请求云端。
            } else if playlist.source == .kuwo || playlist.source == .migu {
                tracks = try await AdditionalCatalogSearchAPI.playlistSongs(source: playlist.source, id: playlist.id)
            } else {
                tracks = []
            }
            if !tracks.isEmpty {
                cache.saveSongs(tracks, playlist: playlist, accountID: cacheAccountID)
            }
            // 收藏的歌单：用真实曲目数回写，修复收藏列表歌曲数显示 0。
            playlistFavorites.updateTrackCount(id: playlist.id, source: playlist.source, count: tracks.count)
            BeansLogger.shared.log("歌单页面加载完成 source=\(playlist.source.rawValue) id=\(playlist.id) name=\(playlist.name) count=\(tracks.count) error=无", level: tracks.isEmpty ? .warn : .info)
            loading = false
        } catch {
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                BeansLogger.shared.log("歌单页面刷新失败，继续使用缓存 source=\(playlist.source.rawValue) id=\(playlist.id) error=\(error.localizedDescription)", level: .warn)
            }
            BeansLogger.shared.log("歌单页面加载失败 source=\(playlist.source.rawValue) id=\(playlist.id) name=\(playlist.name) error=\(error.localizedDescription)", level: .error)
            loading = false
        }
    }
}
