import Foundation

/// Client for the local agent control plane. It sends policy and consent
/// references only; capture data never leaves the Mac.
enum AgentServiceClient {
    static func enroll(endpoint: String, token: String, deviceID: String,
                       workspaceID: String, projectID: String,
                       policy: [String: Any], consents: [[String: Any]]) async throws -> String {
        let data = try await post(endpoint: endpoint, path: "/v1/enroll", token: token, body: [
            "deviceID": deviceID, "workspaceID": workspaceID, "projectID": projectID,
            "policy": policy, "consents": consents,
        ])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceToken = root["deviceToken"] as? String else {
            throw AgentError.http(0, "enrollment returned no device token")
        }
        return deviceToken
    }

    static func heartbeat(endpoint: String, deviceToken: String, deviceID: String) async throws {
        _ = try await post(endpoint: endpoint, path: "/v1/heartbeat", token: deviceToken, body: ["deviceID": deviceID])
    }

    static func listAgents(endpoint: String, enrollmentToken: String, workspaceID: String = "") async throws -> [[String: Any]] {
        var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespaces) + "/v1/agents")
        if !workspaceID.isEmpty { components?.queryItems = [URLQueryItem(name: "workspace", value: workspaceID)] }
        guard let url = components?.url else { throw AgentError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(enrollmentToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AgentError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return root["agents"] as? [[String: Any]] ?? []
    }

    static func revoke(endpoint: String, enrollmentToken: String, deviceID: String) async throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/v1/agents/" + deviceID) else { throw AgentError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        request.setValue("Bearer \(enrollmentToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AgentError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
    }

    static func policy(endpoint: String, deviceToken: String, deviceID: String) async throws -> [String: Any] {
        guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespaces) + "/v1/policy") else {
            throw AgentError.badURL
        }
        components.queryItems = [URLQueryItem(name: "deviceID", value: deviceID)]
        guard let url = components.url else { throw AgentError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AgentError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func post(endpoint: String, path: String, token: String, body: [String: Any]) async throws -> Data {
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
        return data
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
