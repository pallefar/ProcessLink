import Foundation

/// The reverse PDF Studio -> ProcessLink page-note contract.
public struct PageNote: Sendable, Equatable {
    public var document: String
    public var page: Int
    public var body: String
    public var author: String
}

public enum PageNoteParser {
    public static func parse(_ data: Data) -> PageNote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema"] as? String == "processlink-page-note/1",
              let body = root["body"] as? String, !body.isEmpty else { return nil }
        return PageNote(
            document: root["document"] as? String ?? "PDF",
            page: max(0, root["page"] as? Int ?? 0),
            body: body,
            author: root["author"] as? String ?? "PDF Studio")
    }
}
