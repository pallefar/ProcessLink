import Foundation

struct UpdateInfo: Sendable, Identifiable {
    var id: String { version }
    var version: String
    var pageURL: URL
    var downloadURL: URL?
    var notes: String
    var publishedAt: Date?
}

/// Checks the public GitHub release feed. It never installs anything: the
/// signed DMG is downloaded/opened by the person, matching the manual release
/// process this app already uses.
enum UpdateService {
    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.20"
    }

    static var releasesPage: URL {
        URL(string: "https://github.com/pallefar/ProcessLink/releases")!
    }

    static func latest(channel: String = "stable") async throws -> UpdateInfo {
        let endpoint = channel == "beta"
            ? "https://api.github.com/repos/pallefar/ProcessLink/releases?per_page=10"
            : "https://api.github.com/repos/pallefar/ProcessLink/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw UpdateError.badURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ProcessLink/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let payload = try JSONSerialization.jsonObject(with: data)
        let root: [String: Any]
        if channel == "beta", let list = payload as? [[String: Any]], let first = list.first {
            root = first
        } else if let object = payload as? [String: Any] {
            root = object
        } else {
            throw UpdateError.malformed
        }
        guard let tag = root["tag_name"] as? String,
              let page = root["html_url"] as? String, let pageURL = URL(string: page) else {
            throw UpdateError.malformed
        }
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let assets = root["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let download = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let notes = root["body"] as? String ?? ""
        let published = (root["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return UpdateInfo(version: version, pageURL: pageURL, downloadURL: download,
                          notes: notes, publishedAt: published)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    enum UpdateError: LocalizedError {
        case badURL
        case http(Int)
        case malformed
        var errorDescription: String? {
            switch self {
            case .badURL: "The update feed URL is invalid."
            case .http(let code): "The update feed answered HTTP \(code)."
            case .malformed: "The update feed did not contain a release."
            }
        }
    }
}
