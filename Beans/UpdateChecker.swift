import Foundation
import UIKit

struct UpdateChecker {
    static let repoPath = "zhangwenwei44/-11"
    static let releasePageURL = URL(string: "https://github.com/\(repoPath)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases/latest")!
    private static let releasesAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases?per_page=100")!
    private static let minimumHistoryVersion = "1.6.5"
    private static let suppressedVersionKey = "beans.updateCheck.suppressedVersion"

    struct ReleaseInfo {
        let version: String
        let name: String
        let body: String
        let htmlURL: URL
        let notesImageURL: URL?
        let notesTextColorHex: String?
        /// Release 中 manifest.plist 的地址；用于应用内直接推送安装包。
        let manifestURL: URL?

        /// itms-services 安装链接：点击后系统直接下载并安装 ipa（越狱设备需 AppSync）。
        var installURL: URL? {
            guard let manifestURL,
                  let encoded = manifestURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")
        }
    }

    enum CheckResult {
        case update(ReleaseInfo)
        case upToDate
        case failed
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func checkIfNeeded() async -> ReleaseInfo? {
        guard let info = try? await fetchLatest(), isNewer(info.version, than: currentVersion) else { return nil }
        if UserDefaults.standard.string(forKey: suppressedVersionKey) == info.version { return nil }
        return info
    }

    static func checkNow() async -> CheckResult {
        do {
            let info = try await fetchLatest()
            return isNewer(info.version, than: currentVersion) ? .update(info) : .upToDate
        } catch {
            return .failed
        }
    }

    static func suppress(version: String) {
        UserDefaults.standard.set(version, forKey: suppressedVersionKey)
        UserDefaults.standard.synchronize()
    }

    /// 应用内直接推送安装包：优先走 itms-services 系统安装，失败时退回 Release 页面。
    static func openInstall(_ info: ReleaseInfo) {
        guard let url = info.installURL else {
            UIApplication.shared.open(info.htmlURL)
            return
        }
        UIApplication.shared.open(url)
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestAPI)
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              let url = URL(string: html) else {
            throw URLError(.cannotParseResponse)
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]]
        let manifestAsset = assets?.first { ($0["name"] as? String) == "manifest.plist" }
        let manifestURL = (manifestAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repoPath)/releases/download/\(tag)/manifest.plist")
        return ReleaseInfo(
            version: version,
            name: json["name"] as? String ?? tag,
            body: json["body"] as? String ?? "",
            htmlURL: url,
            notesImageURL: nil,
            notesTextColorHex: nil,
            manifestURL: manifestURL
        )
    }

    static func fetchHistory() async throws -> [ReleaseInfo] {
        let githubHistory = try await fetchGitHubHistory()
        return githubHistory.filter { !isNewer(minimumHistoryVersion, than: $0.version) }
    }

    private static func fetchGitHubHistory() async throws -> [ReleaseInfo] {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let releases = try JSONDecoder().decode([GitHubReleasePayload].self, from: data)
        return releases.compactMap { release in
            guard !release.draft, !release.prerelease,
                  let tag = release.tagName,
                  let htmlURL = URL(string: release.htmlURL) else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return ReleaseInfo(
                version: version,
                name: release.name ?? tag,
                body: release.body ?? "",
                htmlURL: htmlURL,
                notesImageURL: nil,
                notesTextColorHex: nil,
                manifestURL: URL(string: "https://github.com/\(repoPath)/releases/download/\(tag)/manifest.plist")
            )
        }
    }

    static func isNewer(_ remote: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").compactMap { Int($0) }
        }
        let r = parts(remote)
        let c = parts(current)
        let count = max(r.count, c.count)
        for i in 0..<count {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

}

private struct GitHubReleasePayload: Decodable {
    let tagName: String?
    let name: String?
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(String.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }
}
