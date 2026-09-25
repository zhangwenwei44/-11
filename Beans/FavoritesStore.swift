import Foundation

/// 收藏管理（红心）：网易云登录后同步到网易云云端；QQ 本地持久化，
/// 登录 QQ 时尽力同步到 QQ 云端（music.srfDissong），失败不影响本地收藏。
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    /// QQ 红心收藏（本地持久化，供音乐库展示）
    @Published private(set) var qqFavoriteSongs: [Song] = []
    /// 网易云红心收藏（本地缓存 + 云端同步）
    @Published private(set) var neteaseFavoriteSongs: [Song] = []
    /// 酷狗红心收藏（本地持久化，酷狗暂无稳定云端红心写入接口）
    @Published private(set) var kugouFavoriteSongs: [Song] = []
    /// 酷狗官方歌单收藏的本地镜像，用于显示收藏状态，不替代设备本地歌单。
    @Published private(set) var kugouOfficialFavoriteSongs: [Song] = []

    private let defaults = UserDefaults.standard
    private let neteaseKey = "beans.fav.netease.v1"
    private let qqKey = "beans.fav.qq.v1"
    private let kugouKey = "beans.fav.kugou.v1"
    private let kugouOfficialKey = "beans.fav.kugou.official.v1"

    private init() {
        qqFavoriteSongs = Self.loadSongs(qqKey)
        neteaseFavoriteSongs = Self.loadSongs(neteaseKey)
        kugouFavoriteSongs = Self.loadSongs(kugouKey)
        kugouOfficialFavoriteSongs = Self.loadSongs(kugouOfficialKey)
    }

    /// 该歌曲是否已收藏
    func isLiked(_ song: Song?) -> Bool {
        guard let song else { return false }
        switch song.source {
        case .netease:
            return neteaseFavoriteSongs.contains { $0.id == song.id }
        case .qq:
            if let mid = song.qqMid, !mid.isEmpty {
                return qqFavoriteSongs.contains { $0.qqMid == mid || $0.identityKey == song.identityKey }
            }
            return qqFavoriteSongs.contains { $0.identityKey == song.identityKey }
        case .kugou:
            return kugouFavoriteSongs.contains { $0.identityKey == song.identityKey }
                || kugouOfficialFavoriteSongs.contains { $0.identityKey == song.identityKey }
        case .kuwo, .migu:
            return kugouFavoriteSongs.contains { $0.identityKey == song.identityKey }
        }
    }

    func isOfficiallyLiked(_ song: Song?) -> Bool {
        guard let song else { return false }
        switch song.source {
        case .netease:
            return neteaseFavoriteSongs.contains { $0.id == song.id }
        case .kugou:
            return kugouOfficialFavoriteSongs.contains { $0.identityKey == song.identityKey }
        case .qq:
            return false
        case .kuwo, .migu:
            return false
        }
    }

    /// 切换收藏状态；网易云 / QQ 音乐已移除，仅本地维护。
    @discardableResult
    func toggle(_ song: Song) async -> Bool {
        switch song.source {
        case .netease:
            let liked = !isLiked(song)
            updateNetease(song, liked: liked)
            return true
        case .qq:
            let liked = !isLiked(song)
            updateQQ(song, liked: liked)
            return true
        case .kugou:
            let liked = !isLiked(song)
            updateKugou(song, liked: liked)
            return true
        case .kuwo, .migu:
            let liked = !isLiked(song)
            updateKugou(song, liked: liked)
            return true
        }
    }

    /// 移除 QQ 收藏（音乐库侧滑删除）
    func removeQQFavorite(_ song: Song) {
        updateQQ(song, liked: false)
    }

    /// QQ 音乐已移除：云端同步无操作。
    @MainActor
    func syncQQFromCloud() async {
        // QQ 音乐已移除
    }

    /// 网易云音乐已移除：仅维护本地收藏状态。
    @discardableResult
    func setNeteaseOfficial(_ song: Song, liked: Bool) async -> Bool {
        updateNetease(song, liked: liked)
        return true
    }

    private func updateNetease(_ song: Song, liked: Bool) {
        if liked {
            neteaseFavoriteSongs.removeAll { $0.id == song.id }
            neteaseFavoriteSongs.insert(song, at: 0)
        } else {
            neteaseFavoriteSongs.removeAll { $0.id == song.id }
        }
        saveSongs(neteaseFavoriteSongs, key: neteaseKey)
    }

    private func updateQQ(_ song: Song, liked: Bool) {
        if liked {
            qqFavoriteSongs.removeAll { existing in
                existing.identityKey == song.identityKey
                    || (existing.qqMid != nil && song.qqMid != nil && existing.qqMid == song.qqMid)
            }
            qqFavoriteSongs.insert(song, at: 0)
        } else {
            qqFavoriteSongs.removeAll { existing in
                existing.identityKey == song.identityKey
                    || (existing.qqMid != nil && song.qqMid != nil && existing.qqMid == song.qqMid)
            }
        }
        saveSongs(qqFavoriteSongs, key: qqKey)
    }

    private func updateKugou(_ song: Song, liked: Bool) {
        if liked {
            kugouFavoriteSongs.removeAll { $0.identityKey == song.identityKey }
            kugouFavoriteSongs.insert(song, at: 0)
        } else {
            kugouFavoriteSongs.removeAll { $0.identityKey == song.identityKey }
        }
        saveSongs(kugouFavoriteSongs, key: kugouKey)
    }

    private static func loadSongs(_ key: String) -> [Song] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return saved
    }

    private func saveSongs(_ songs: [Song], key: String) {
        if let data = try? JSONEncoder().encode(songs) {
            defaults.set(data, forKey: key)
        }
    }

    /// 退出网易云登录时清空本地网易云收藏缓存（保留 QQ 收藏）
    func resetNetease() {
        neteaseFavoriteSongs = []
        defaults.removeObject(forKey: neteaseKey)
    }

    func markKugouOfficial(_ song: Song, liked: Bool) {
        if liked {
            kugouOfficialFavoriteSongs.removeAll { $0.identityKey == song.identityKey }
            kugouOfficialFavoriteSongs.insert(song, at: 0)
        } else {
            kugouOfficialFavoriteSongs.removeAll { $0.identityKey == song.identityKey }
        }
        saveSongs(kugouOfficialFavoriteSongs, key: kugouOfficialKey)
    }

    func markNeteaseOfficial(_ song: Song, liked: Bool) {
        updateNetease(song, liked: liked)
    }
}
