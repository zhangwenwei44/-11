import AVKit
import AVRouting
import SwiftUI
import MediaPlayer
import UIKit

// MARK: - 酷狗风格播放页（沉浸式）
//
// 沉浸式布局贴近酷狗新版播放器：封面全屏铺底，顶部轻压暗保证顶栏可读，
// 中下部由亮纱渐变（深色模式为暗纱）承载信息与控件，文字转为墨水色；
// 中部三页横滑（封面 / 歌词 / 队列）配顶部圆点指示，歌词与队列压在亮纱之上。

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

    // MARK: 沉浸式配色（跟随背景图主色）

    private var veilColor: Color { colorScheme == .dark ? .black : .white }

    private var tintColor: Color {
        guard let c = backdropLoader.dominantColor else { return .black }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var isTintLight: Bool {
        guard let c = backdropLoader.dominantColor else { return false }
        return (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) > 0.55
    }

    private var adaptiveInkPrimary: Color { isTintLight ? .black : .white }
    private var adaptiveInkSecondary: Color { isTintLight ? .black.opacity(0.56) : .white.opacity(0.62) }
    private var adaptiveInkFaint: Color { isTintLight ? .black.opacity(0.38) : .white.opacity(0.4) }

    private var queuePalette: CompactQueuePalette {
        isTintLight ? .onLightVeil : .onDarkArtwork
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

    // MARK: - 背景（沉浸式：顶部压暗 + 中下部亮纱，颜色跟随背景图）

    private var backdrop: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 毛玻璃封面垫底：封面未加载时也有氛围背景
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

            // 顶部轻压暗：状态栏与顶栏白色元素可读
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .black.opacity(0.30), location: 0.06),
                    .init(color: .black.opacity(0.10), location: 0.13),
                    .init(color: .clear, location: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 沉浸式亮纱：上半屏露出封面，中下部渐亮承载信息与控件；颜色跟随背景图主色
            let tint = backdropLoader.dominantColor ?? .black
            let tintR = CGFloat(tint.red); let tintG = CGFloat(tint.green); let tintB = CGFloat(tint.blue)
            let tintLight = Color(red: min(1, tintR + 0.15), green: min(1, tintG + 0.15), blue: min(1, tintB + 0.15))
            let tintDark = Color(red: max(0, tintR - 0.15), green: max(0, tintG - 0.15), blue: max(0, tintB - 0.15))
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.20),
                    .init(color: tintLight.opacity(0.30), location: 0.28),
                    .init(color: tintLight.opacity(0.55), location: 0.38),
                    .init(color: tint.opacity(0.80), location: 0.48),
                    .init(color: tintDark.opacity(0.85), location: 0.60),
                    .init(color: tintDark.opacity(0.92), location: 0.78),
                    .init(color: tintDark.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 顶部栏（保持白色元素，压暗在深色顶部）

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
        // 背景图缩小显示中间：去除 frosted 头像框，用直出背景图
        GeometryReader { geo in
            let imgSize = min(geo.width * 0.58, geo.height * 0.50)
            let imgX = (geo.width - imgSize) / 2
            let imgY = geo.size.height * 0.14

            if let image = backdropLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imgSize, height: imgSize)
                    .position(x: imgX + imgSize / 2, y: imgY + imgSize / 2)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            } else {
                CoverImage(
                    url: coverURL,
                    song: song,
                    size: imgSize * 0.6,
                    cornerRadius: 18,
                    emptyHint: player.isBuffering ? "等待开始播放…" : nil,
                    playsCoverVideoAudio: true
                )
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 歌词页：顶部占位把歌词压到中下部，当前行落在亮纱上
    private var lyricsPage: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear.frame(height: geo.size.height * 0.26)
                Group {
                    if lyrics.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(adaptiveInkFaint)
                            Text("暂无歌词")
                                .font(BeansFont.appFont(15, .medium))
                                .foregroundStyle(adaptiveInkSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        AppleMusicLyricsSection(
                            lyrics: lyrics,
                            primary: adaptiveInkPrimary,
                            secondary: adaptiveInkSecondary,
                            lyricOffset: CGFloat(lyricOffset)
                        ) { line in
                            BeansHaptics.tap()
                            player.seekPrecisely(to: LyricTiming.seekTime(for: line, userOffset: Double(lyricOffset)))
                        }
                        .padding(.horizontal, 22)
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // 队列页局部亮纱：从封面过渡到近实色的浅色列表背景，颜色跟随背景图
    private var queuePage: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: tintColor.opacity(0.40), location: 0.10),
                        .init(color: tintColor.opacity(0.86), location: 0.22),
                        .init(color: tintColor.opacity(0.94), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: geo.size.height * 0.18)

                    HStack {
                        Text("播放队列")
                            .font(BeansFont.appFont(18, .bold))
                            .foregroundStyle(adaptiveInkPrimary)
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
                                .foregroundStyle(adaptiveInkPrimary.opacity(0.85))
                                .frame(width: 38, height: 30)
                        }
                    }

                    AppleMusicCompactQueueContent(palette: queuePalette)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

        // MARK: - 底部信息与控制（全部墨水色）

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(song?.name ?? "未在播放")
                    .font(BeansFont.appFont(26, .bold))
                    .foregroundStyle(adaptiveInkPrimary)
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
                    .foregroundStyle(adaptiveInkSecondary)
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
            .padding(.top, 4)
            .padding(.bottom, 2)

            // 图3 式：进度条在顶，时间在下方
            HStack {
                Text(beansTimeString(clock.progress))
                    .font(BeansFont.appFont(10, .regular, .monospaced))
                    .frame(minWidth: 30, alignment: .leading)
                Spacer()
                Text(beansTimeString(clock.duration))
                    .font(BeansFont.appFont(10, .regular, .monospaced))
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .foregroundStyle(adaptiveInkSecondary)
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 底部组件

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(BeansFont.appFont(11, .medium))
                .foregroundStyle(adaptiveInkPrimary.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(adaptiveInkPrimary.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private var favoriteIconButton: some View {
        Button {
            BeansHaptics.tap()
            onFavorite()
        } label: {
            FavoriteHeartView(mark: favoriteMark, size: 22, inactiveColor: adaptiveInkPrimary.opacity(0.85))
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
                .foregroundStyle(active ? Color.beansAmber : adaptiveInkPrimary.opacity(0.86))
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
                .foregroundStyle(adaptiveInkPrimary.opacity(0.86))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
    }

    private var modeButton: some View {
        Button {
            BeansHaptics.tap()
            player.togglePlayMode()
        } label: {
            Image(systemName: player.playMode.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(adaptiveInkPrimary.opacity(0.9))
                .frame(width: 44, height: 44)
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
                .foregroundStyle(adaptiveInkPrimary)
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
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.5))
                Circle()
                    .strokeBorder(adaptiveInkPrimary.opacity(colorScheme == .dark ? 0.45 : 0.18), lineWidth: 1)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(adaptiveInkPrimary)
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
                .foregroundStyle(pageIndex == Page.queue.rawValue ? Color.beansAmber : adaptiveInkPrimary.opacity(0.85))
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
    @Published private(set) var dominantColor: UIColor?

    private var task: Task<Void, Never>?
    private var currentURL: URL?
    private static let cache = NSCache<NSURL, UIImage>()
    private static let colorCache = NSCache<NSURL, UIColor>()

    func load(url: URL?) {
        let resolved = CustomSongCoverStore.shared.resolvedURL(for: url)
        guard let resolved else {
            task?.cancel()
            currentURL = nil
            if image != nil { image = nil }
            if dominantColor != nil { dominantColor = nil }
            return
        }
        guard resolved != currentURL else { return }
        currentURL = resolved
        if let cached = Self.cache.object(forKey: resolved as NSURL) {
            image = cached
            dominantColor = Self.colorCache.object(forKey: resolved as NSURL)
                ?? Self.computeDominantColor(from: cached)
            return
        }
        task?.cancel()
        task = Task { @MainActor in
            guard let data = await Self.fetchData(resolved) else { return }
            guard !Task.isCancelled, let loaded = UIImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: resolved as NSURL)
            self.image = loaded
            let color = Self.computeDominantColor(from: loaded)
            Self.colorCache.setObject(color, forKey: resolved as NSURL)
            self.dominantColor = color
        }
    }

    private static func computeDominantColor(from image: UIImage) -> UIColor {
        guard let cg = image.cgImage else { return .black }
        let size = CGSize(width: 1, height: 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .black }
        ctx.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
        return UIColor(red: CGFloat(pixel[0]) / 255.0, green: CGFloat(pixel[1]) / 255.0, blue: CGFloat(pixel[2]) / 255.0, alpha: 1.0)
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
