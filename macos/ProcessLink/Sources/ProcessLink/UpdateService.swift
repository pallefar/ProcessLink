import CryptoKit
import Foundation

struct UpdateInfo: Sendable, Identifiable {
    var id: String { version }
    var version: String
    var pageURL: URL
    var downloadURL: URL?
    var notes: String
    var publishedAt: Date?
    var checksumsURL: URL?
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
        let checksums = assets.first { ($0["name"] as? String) == "SHA256SUMS.txt" }
        let checksumsURL = (checksums?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let notes = root["body"] as? String ?? ""
        let published = (root["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return UpdateInfo(version: version, pageURL: pageURL, downloadURL: download,
                          notes: notes, publishedAt: published, checksumsURL: checksumsURL)
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

    static func downloadAndVerify(_ info: UpdateInfo) async throws -> URL {
        guard let dmg = info.downloadURL, let sums = info.checksumsURL else {
            throw UpdateError.noChecksums
        }
        let (sumData, sumResponse) = try await URLSession.shared.data(from: sums)
        guard (sumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http((sumResponse as? HTTPURLResponse)?.statusCode ?? 0) }
        let text = String(decoding: sumData, as: UTF8.self)
        let expected = text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            return (String(parts[0]), parts.dropFirst().joined(separator: " "))
        }.first { $0.1.trimmingCharacters(in: CharacterSet(charactersIn: "*")) == dmg.lastPathComponent }?.0.lowercased()
        guard let expected else { throw UpdateError.noChecksums }
        let (temp, response) = try await URLSession.shared.download(from: dmg)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(dmg.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            try? FileManager.default.removeItem(at: destination)
            throw UpdateError.checksumMismatch
        }
        try verifySignature(dmg: destination)
        return destination
    }

    private static func verifySignature(dmg: URL) throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("processlink-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path]
        attach.standardOutput = Pipe()
        attach.standardError = Pipe()
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { throw UpdateError.signatureInvalid }

        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-quiet"]
            try? detach.run()
            detach.waitUntilExit()
        }

        guard let app = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.signatureInvalid }

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", app.path]
        verify.standardError = Pipe()
        verify.standardOutput = Pipe()
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else { throw UpdateError.signatureInvalid }

        let details = Process()
        details.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        details.arguments = ["-dv", "--verbose=2", app.path]
        let pipe = Pipe()
        details.standardError = pipe
        details.standardOutput = pipe
        try details.run()
        details.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard !text.contains("Signature=adhoc") else { throw UpdateError.signatureInvalid }
    }

    enum UpdateError: LocalizedError {
        case noChecksums
        case signatureInvalid
        case checksumMismatch
        case badURL
        case http(Int)
        case malformed
        var errorDescription: String? {
            switch self {
            case .badURL: "The update feed URL is invalid."
            case .http(let code): "The update feed answered HTTP \(code)."
            case .malformed: "The update feed did not contain a release."
            case .noChecksums: "The release has no SHA256SUMS.txt asset."
            case .checksumMismatch: "The downloaded DMG failed its SHA-256 check."
            case .signatureInvalid: "The downloaded app is not validly signed."
            }
        }
    }
}
