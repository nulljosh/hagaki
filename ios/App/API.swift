import Foundation

let apiBase = URL(string: "https://hagaki.heyitsmejosh.com")!

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let from: String
    let subject: String?
    let snippet: String?
    let score: Int
    let reasons: [String]
    let isJunk: Bool
    let category: String?
    let listUnsubscribe: String?
    let oneClick: Bool?

    var sender: String {
        let name = from.split(separator: "<").first.map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\""))) } ?? ""
        return name.isEmpty ? from : name
    }
    var domain: String { senderDomain(from) }
    /// One of the seven smart folders, or nil when the mail is from a person and stays in the inbox.
    var folder: String? { smartFolders.contains(category ?? "") ? category : nil }
}

/// Seven boxes, like the seven red boxes on a Japanese postcard.
let smartFolders = ["Receipts", "Travel", "Dev", "Newsletters", "Social", "Promotions", "Junk"]

/// Mail the app read itself, sent to /api/sort with no body text.
struct MailItem: Codable { let id: String; let from: String; let subject: String }

enum Action: String { case archive, delete, unsubscribe, organize }

func senderDomain(_ from: String) -> String {
    guard let at = from.lastIndex(of: "@") else { return from.lowercased() }
    return String(from[from.index(after: at)...]).trimmingCharacters(in: CharacterSet(charactersIn: "> ")).lowercased()
}

/// Junk senders who mailed more than once and offered an unsubscribe link, most frequent first.
func repeatSenders(_ messages: [Message]) -> [(domain: String, messages: [Message])] {
    let junk = messages.filter { ["Junk", "Promotions", "Newsletters"].contains($0.category ?? "") && ($0.listUnsubscribe ?? "").isEmpty == false }
    return Dictionary(grouping: junk, by: \.domain)
        .filter { $0.value.count > 1 }
        .map { (domain: $0.key, messages: $0.value) }
        .sorted { $0.messages.count > $1.messages.count }
}

struct OrganizeResult: Decodable, Equatable {
    let organized: [String: Int]
    let failed: Int
    var total: Int { organized.values.reduce(0, +) }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct API {
    var token: String
    var session: URLSession = .shared

    func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: apiBase.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    func messages() async throws -> [Message] {
        let (data, response) = try await session.data(for: request("api/messages"))
        try check(response, data)
        return try JSONDecoder().decode([Message].self, from: data)
    }

    func perform(_ action: Action, on m: Message) async throws {
        struct Body: Encodable { let messageId: String; let action: String; let category: String?; let listUnsubscribe: String?; let oneClick: Bool? }
        let body = try JSONEncoder().encode(Body(messageId: m.id, action: action.rawValue, category: m.folder, listUnsubscribe: m.listUnsubscribe, oneClick: m.oneClick))
        let (data, response) = try await session.data(for: request("api/action", method: "POST", body: body))
        try check(response, data)
    }

    /// Sorts mail the app read itself (Mail.app), same rules and AI pass as the server's own inboxes.
    func sort(_ items: [MailItem]) async throws -> [Message] {
        struct Body: Encodable { let items: [MailItem] }
        let (data, response) = try await session.data(for: request("api/sort", method: "POST", body: try JSONEncoder().encode(Body(items: items))))
        try check(response, data)
        return try JSONDecoder().decode([Message].self, from: data)
    }

    /// Files every message that has a smart folder, in one pass. Nothing is deleted.
    func organize(_ messages: [Message]) async throws -> OrganizeResult {
        struct Item: Encodable { let messageId: String; let category: String }
        struct Body: Encodable { let items: [Item] }
        let items = messages.compactMap { m in m.folder.map { Item(messageId: m.id, category: $0) } }
        let body = try JSONEncoder().encode(Body(items: items))
        let (data, response) = try await session.data(for: request("api/organize", method: "POST", body: body))
        try check(response, data)
        return try JSONDecoder().decode(OrganizeResult.self, from: data)
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "No response") }
        if http.statusCode == 401 { throw APIError(message: "Session expired. Sign in again.") }
        if http.statusCode >= 400 { throw APIError(message: String(data: data, encoding: .utf8) ?? "Request failed") }
    }
}

enum Auth {
    static func demo() async throws -> String { try await token("auth/demo", body: nil) }
    static func mac() async throws -> String { try await token("auth/mac", body: nil) }

    static func icloud(email: String, appPassword: String) async throws -> String {
        try await token("auth/icloud", body: ["email": email, "appPassword": appPassword])
    }

    private static func token(_ path: String, body: [String: String]?) async throws -> String {
        var r = URLRequest(url: apiBase.appendingPathComponent(path))
        r.httpMethod = "POST"
        if let body { r.httpBody = try JSONEncoder().encode(body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError(message: String(data: data, encoding: .utf8) ?? "Sign in failed")
        }
        struct T: Decodable { let token: String }
        return try JSONDecoder().decode(T.self, from: data).token
    }
}
