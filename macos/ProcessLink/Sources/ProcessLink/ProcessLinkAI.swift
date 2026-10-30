import Foundation

/// Optional local transformers.js sidecar. It runs on this Mac, receives only
/// activity/map labels, and never sees case ids or person data.
enum ProcessLinkAI {
    static let defaultsKey = "ai.transformersURL"
    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "http://127.0.0.1:4183" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    struct MapResult: Decodable {
        var mapping: [String: String]
        var confidence: [String: Double]?
    }

    static func health() async -> Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root["ok"] as? Bool == true
    }

    struct TaskName: Decodable { var app: String; var title: String; var suggestedName: String; var confidence: Double }
    struct NameResult: Decodable { var tasks: [TaskName] }

    static func suggestTaskNames(samples: [(app: String, title: String)], candidates: [String]) async throws -> [TaskName] {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/api/name") else {
            throw AIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "samples": samples.map { ["app": $0.app, "title": $0.title] },
            "candidates": candidates,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(NameResult.self, from: data).tasks
    }

    static func suggestMapping(activities: [String], steps: [(id: String, label: String)]) async throws -> MapResult {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/api/map") else {
            throw AIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "activities": activities,
            "steps": steps.map { ["id": $0.id, "label": $0.label] },
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(MapResult.self, from: data)
    }

    enum AIError: LocalizedError {
        case badURL
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .badURL: "Set a valid transformers.js sidecar URL."
            case .http(let code): "The local AI sidecar answered HTTP \(code)."
            }
        }
    }
}
