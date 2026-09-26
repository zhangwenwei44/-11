import Foundation
import Combine

/// 专辑收藏：专辑详情页点收藏，歌单（音乐库）页集中展示收藏的专辑。
final class AlbumFavoritesStore: ObservableObject {
    static let shared = AlbumFavoritesStore()

    private static let storageKey = "beans.albumFavorites.v1"

    @Published private(set) var albums: [Album] = []

    private init() {
        load()
    }

    func contains(_ album: Album) -> Bool {
        albums.contains { $0.id == album.id && $0.source == album.source }
    }

    @discardableResult
    func toggle(_ album: Album) -> Bool {
        if let index = albums.firstIndex(where: { $0.id == album.id && $0.source == album.source }) {
            albums.remove(at: index)
            save()
            return false
        }
        albums.insert(album, at: 0)
        save()
        return true
    }

    func remove(_ album: Album) {
        albums.removeAll { $0.id == album.id && $0.source == album.source }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Album].self, from: data) else { return }
        albums = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
