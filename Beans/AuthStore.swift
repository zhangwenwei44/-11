import Foundation

/// 账号存储。网易云 / QQ 音乐已移除，此类型仅保留以兼容既有 @EnvironmentObject 注入。
/// 当前始终为未登录状态，歌单列表为空。
final class AuthStore: ObservableObject {
    @Published var user: NetEaseUser?
    @Published var isLoggedIn = false
    @Published var playlists: [Playlist] = []

    init() {
        // 网易云音乐登录已移除：忽略历史登录态，始终按访客处理。
        user = nil
        isLoggedIn = false
        playlists = []
    }

    @MainActor
    func finishLogin() async throws {
        throw NetEaseError.unknown("网易云音乐已移除")
    }

    /// 刷新账号资料（网易云已移除，无操作）。
    @MainActor
    func refreshAccount(force: Bool = false) async {
        user = nil
        isLoggedIn = false
        playlists = []
    }

    @MainActor
    func loadLibrary(force: Bool = false) async {
        playlists = []
    }

    func logout() {
        user = nil
        playlists = []
        isLoggedIn = false
    }
}
