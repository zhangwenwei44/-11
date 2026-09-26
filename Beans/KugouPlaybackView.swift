import AVKit
import SwiftUI
import MediaPlayer
import UIKit

// MARK: - 酷狗风格播放页
//
// 布局贴近酷狗播放器：全屏封面背景（模糊封面 + 分段压暗渐变）、
// 中部三页横滑（封面 / 歌词 / 队列）配顶部圆点指示、
// 底部为歌名 + 歌手标签行、功能图标行、细进度条和五键控制区。

struct KugouPlaybackView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var localLibrary = LocalLibraryStore.shared
    @ObservedObject private var customCovers = CustomSongCoverStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true

    let song: Song?
    let lyrics: [LyricLine]
    let onClose: () -> Void
    let onFavorite: () -> Void
    let onComments: () -> Void
    let onSleepTimer: () -> Void
    let onAddToLocalPlaylist: () -> Void
    let onPlayerSettings: () -> Void
    let onArtist: () -> Void

    @StateObject private var backdropLoader = KugouBackdropLoader()
    @State private var pageIndex: Int = Page.lyrics.rawValue
    @State private var showShare = false

    private enum Page: Int, CaseIterable {
        case cover
        case lyrics
        case queue
    }

    private var coverURL: URL? {
        customCovers.url(for: song) ?? song?.coverURL
    }

    private var shareItems: [Any] {
        guard let song else { return [] }
        var items: [Any] = ["\(song.name) - \(song.artists)"]
        if let url = song.officialURL { items.append(url) }
        return items
    }

    private var favoriteMark: FavoriteMark {
        guard let song else { return .none }
        let local = localLibrary.containsSong(song)
        let official = favorites.isOfficiallyLiked(song)
        switch (local, official) {
        case (true, true): return .both
        case (true, false): return .local
        case (false, true): return .official
        case (false, false): return .none
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop

                VStack(spacing: 0) {
                    header

                    TabView(selection: $pageIndex) {
                        coverPage(size: geo.size)
                            .tag(Page.cover.rawValue)
                        lyricsPage
                            .tag(Page.lyrics.rawValue)
                        queuePage
                            .tag(Page.queue.rawValue)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomPanel
                }
                .foregroundStyle(.white)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            backdropLoader.load(url: coverURL)
            if lyrics.isEmpty {
                pageIndex = Page.cover.rawValue
            }
        }
        .onChange(of: coverURL) { nextURL in
            backdropLoader.load(url: nextURL)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: - 背景

    private var backdrop: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 毛玻璃封面垫底：封面未加载 / 视频封面时也有氛围背景
            CoverBlurBackground(url: coverURL, scheme: colorScheme)
                .ignoresSafeArea()

            if let image = backdropLoader.image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // 顶部状态栏可读 + 中部露出封面 + 底部信息区压暗
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.52), location: 0),
                    .init(color: .black.opacity(0.24), location: 0.16),
                    .init(color: .black.opacity(0.04), location: 0.36),
                    .init(color: .black.opacity(0.42), location: 0.58),
                    .init(color: .black.opacity(0.88), location: 0.74),
                    .init(color: .black.opacity(0.97), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 顶部栏

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                BeansHaptics.tap()
                onClose()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                ForEach(Page.allCases, id: \.rawValue) { page in
                    Button {
                        BeansHaptics.tap()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pageIndex = page.rawValue
                        }
                    } label: {
                        Capsule()
                            .fill(.white.opacity(pageIndex == page.rawValue ? 0.95 : 0.38))
                            .frame(width: pageIndex == page.rawValue ? 17 : 7, height: 7)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                AirPlayRoutePicker()
                    .frame(width: 26, height: 26)
                Button {
                    BeansHaptics.tap()
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    // MARK: - 中部页面

    private func coverPage(size: CGSize) -> some View {
        let artSize = min(size.width - 96, min(size.height * 0.42, 360))
        return VStack(spacing: 16) {
            Spacer(minLength: 10)

            CoverImage(
                url: coverURL,
                song: song,
                size: artSize,
                cornerRadius: 18,
                emptyHint: player.isBuffering ? "等待开始播放…" : nil,
                playsCoverVideoAudio: true
            )
            .shadow(color: .black.opacity(0.5), radius: 34, y: 16)
            .scaleEffect(player.isPlaying ? 1 : 0.965)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: player.isPlaying)

            if !lyrics.isEmpty {
                Button {
                    BeansHaptics.tap()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        pageIndex = Page.lyrics.rawValue
                    }
                } label: {
                    Text(currentLyricText)
                        .font(BeansFont.appFont(14, .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(GlassPressButtonStyle())
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsPage: some View {
        Group {
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("暂无歌词")
                        .font(BeansFont.appFont(15, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppleMusicLyricsSection(
                    lyrics: lyrics,
                    primary: .white,
                    secondary: .white.opacity(0.5),
                    lyricOffset: CGFloat(lyricOffset)
                ) { line in
                    BeansHaptics.tap()
                    player.seekPrecisely(to: LyricTiming.seekTime(for: line, userOffset: Double(lyricOffset)))
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private var queuePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("播放队列")
                    .font(BeansFont.appFont(18, .bold))
                Spacer()
                Menu {
                    Button("清空队列", role: .destructive) {
                        player.clearQueue()
                    }
                    Divider()
                    Button("定时关闭", action: onSleepTimer)
                    Button("添加到本地歌单", action: onAddToLocalPlaylist)
                    Button("播放器设置", action: onPlayerSettings)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 38, height: 30)
                }
            }

            AppleMusicCompactQueueContent()
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 底部信息与控制

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(song?.name ?? "未在播放")
                    .font(BeansFont.appFont(26, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showSongVIPBadge, song?.isVIP == true {
                    Text("VIP")
                        .font(BeansFont.appFont(9, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.93, green: 0.25, blue: 0.22), in: Capsule())
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(song?.artists ?? "")
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if song != nil { onArtist() }
                    }

                pillButton("音效") { onPlayerSettings() }

                if !lyrics.isEmpty {
                    pillButton("歌词") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pageIndex = pageIndex == Page.lyrics.rawValue
                                ? Page.cover.rawValue
                                : Page.lyrics.rawValue
                        }
                    }
                }

                if player.sleepTimerEndsAt != nil {
                    pillButton("定时 \(beansTimeString(Double(player.sleepTimerRemaining)))") {
                        onSleepTimer()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            HStack(spacing: 0) {
                favoriteIconButton
                actionIcon("bubble.right") { onComments() }
                actionIcon(
                    player.sleepTimerEndsAt != nil ? "moon.zzz.fill" : "moon.zzz",
                    active: player.sleepTimerEndsAt != nil
                ) { onSleepTimer() }
                actionIcon("plus.circle") { onAddToLocalPlaylist() }
                moreMenu
            }
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                Text(beansTimeString(clock.progress))
                    .frame(minWidth: 34, alignment: .leading)
                SeekBar(accent: .white, track: .white.opacity(0.32))
                    .frame(height: 22)
                Text(beansTimeString(clock.duration))
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(BeansFont.appFont(11, .regular, .monospaced))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.top, 8)

            HStack(spacing: 0) {
                modeButton
                Spacer(minLength: 0)
                transportButton(icon: "backward.fill", size: 28) { player.previous() }
                Spacer(minLength: 0)
                playButton
                Spacer(minLength: 0)
                transportButton(icon: "forward.fill", size: 28) { player.next() }
                Spacer(minLength: 0)
                queueButton
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - 底部组件

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(BeansFont.appFont(11, .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(.white.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private var favoriteIconButton: some View {
        Button {
            BeansHaptics.tap()
            onFavorite()
        } label: {
            FavoriteHeartView(mark: favoriteMark, size: 22, inactiveColor: .white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func actionIcon(_ name: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: name)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(active ? Color.beansAmber : .white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private var moreMenu: some View {
        Menu {
            Button("定时关闭", action: onSleepTimer)
            Button("添加到本地歌单", action: onAddToLocalPlaylist)
            Button("播放器设置", action: onPlayerSettings)
            Button("分享") { showShare = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
    }

    private var modeButton: some View {
        Button {
            BeansHaptics.tap()
            player.togglePlayMode()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: player.playMode.icon)
                    .font(.system(size: 19, weight: .medium))
                Text(player.playMode.title)
                    .font(BeansFont.appFont(9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 56, height: 44)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func transportButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(song == nil)
        .opacity(song == nil ? 0.4 : 1)
    }

    private var playButton: some View {
        Button {
            BeansHaptics.medium()
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(.white.opacity(0.12))
                Circle()
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: player.isPlaying ? 0 : 1.5)
            }
            .frame(width: 66, height: 66)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(song == nil)
        .opacity(song == nil ? 0.4 : 1)
    }

    private var queueButton: some View {
        Button {
            BeansHaptics.tap()
            withAnimation(.easeInOut(duration: 0.25)) {
                pageIndex = pageIndex == Page.queue.rawValue
                    ? Page.cover.rawValue
                    : Page.queue.rawValue
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(pageIndex == Page.queue.rawValue ? Color.beansAmber : .white.opacity(0.85))
                .frame(width: 56, height: 44)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 工具

    private var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let progress = LyricTiming.effectiveProgress(clock.progress, userOffset: Double(lyricOffset))
        var low = 0
        var high = lyrics.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= progress {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    private var currentLyricText: String {
        guard let index = currentLyricIndex, lyrics.indices.contains(index) else {
            return lyrics.first?.text ?? "暂无歌词"
        }
        return lyrics[index].text
    }
}

// MARK: - 封面直出背景图加载器（切歌重载，内存缓存）

private final class KugouBackdropLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private var task: Task<Void, Never>?
    private var currentURL: URL?
    private static let cache = NSCache<NSURL, UIImage>()

    func load(url: URL?) {
        let resolved = CustomSongCoverStore.shared.resolvedURL(for: url)
        guard let resolved else {
            task?.cancel()
            currentURL = nil
            if image != nil { image = nil }
            return
        }
        guard resolved != currentURL else { return }
        currentURL = resolved
        if let cached = Self.cache.object(forKey: resolved as NSURL) {
            image = cached
            return
        }
        task?.cancel()
        task = Task { @MainActor in
            guard let data = await Self.fetchData(resolved) else { return }
            guard !Task.isCancelled, let loaded = UIImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: resolved as NSURL)
            self.image = loaded
        }
    }

    private static func fetchData(_ url: URL) async -> Data? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
        }
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data
    }
}

// MARK: - 顶部投屏按钮（系统音频路由选择）

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
