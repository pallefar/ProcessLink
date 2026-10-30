import Foundation

/// Client for the local agent control plane. It sends policy and consent
/// references only; capture data never leaves the Mac.
enum AgentServiceClient {
    static func enroll(endpoint: String, token: String, deviceID: String,
                       workspaceID: String, projectID: String,
                       policy: [String: Any], consents: [[String: Any]]) async throws {
        try await post(endpoint: endpoint, path: "/v1/enroll", token: token, body: [
            "deviceID": deviceID, "workspaceID": workspaceID, "projectID": projectID,
            "policy": policy, "consents": consents,
        ])
    }

    static func heartbeat(endpoint: String, token: String, deviceID: String) async throws {
        try await post(endpoint: endpoint, path: "/v1/heartbeat", token: token, body: ["deviceID": deviceID])
    }

    static func policy(endpoint: String, token: String, deviceID: String) async throws -> [String: Any] {
        guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespaces) + "/v1/policy") else {
            throw AgentError.badURL
        }
        components.queryItems = [URLQueryItem(name: "deviceID", value: deviceID)]
        guard let url = components.url else { throw AgentError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AgentError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func post(endpoint: String, path: String, token: String, body: [String: Any]) async throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + path) else {
            throw AgentError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AgentError.http((response as? HTTPURLResponse)?.statusCode ?? 0, detail)
        }
    }

    enum AgentError: LocalizedError {
        case badURL
        case http(Int, String = "")
        var errorDescription: String? {
            switch self {
            case .badURL: "Set a valid agent control-plane endpoint."
            case .http(let code, let detail): "Agent service HTTP \(code). \(detail)"
            }
        }
    }
}
