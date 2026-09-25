import Foundation
import Combine

/// 精选页歌单收藏：整份歌单存本地，歌单页可查看、点开和取消收藏。
final class PlaylistFavoritesStore: ObservableObject {
    static let shared = PlaylistFavoritesStore()

    private static let storageKey = "beans.playlistFavorites.v1"

    @Published private(set) var playlists: [Playlist] = []

    private init() {
        load()
    }

    func contains(_ playlist: Playlist) -> Bool {
        playlists.contains { $0.id == playlist.id && $0.source == playlist.source }
    }

    @discardableResult
    func toggle(_ playlist: Playlist) -> Bool {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id && $0.source == playlist.source }) {
            playlists.remove(at: index)
            save()
            return false
        }
        playlists.insert(playlist, at: 0)
        save()
        return true
    }

    func remove(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id && $0.source == playlist.source }
        save()
    }

    /// 歌单详情加载后回写真实歌曲数，修复收藏列表一直显示 0 首的问题。
    func updateTrackCount(id: Int, source: SongSource, count: Int) {
        guard count > 0,
              let index = playlists.firstIndex(where: { $0.id == id && $0.source == source }),
              playlists[index].trackCount != count else { return }
        playlists[index].trackCount = count
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
