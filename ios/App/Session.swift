import SwiftUI
import Security

/// The sign-in session token lives in the Keychain, never in UserDefaults.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.nulljosh.sieve", kSecAttrAccount as String: key]
    }
    static func get(_ key: String) -> String? {
        var q = query(key); q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key); q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

@MainActor
final class Session: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var label = UserDefaults.standard.string(forKey: "label") ?? "Inbox" {
        didSet { UserDefaults.standard.set(label, forKey: "label") }
    }
    @Published var busy = false
    @Published var error: String?

    init(token: String? = Keychain.get("session")) { self.token = token }

    var api: API? { token.map { API(token: $0.hasPrefix("mac:") ? String($0.dropFirst(4)) : $0) } }

    func store(_ t: String?) { token = t; Keychain.set("session", t) }

    func signOut() { store(nil) }

    func demo() async { label = "Demo inbox"; await run { try await Auth.demo() } }
    /// Mail.app mode keeps a server token for /api/sort, prefixed so the inbox knows to read Mail.app.
    func macMail() async { label = "Mail on this Mac"; await run { "mac:" + (try await Auth.mac()) } }
    var isMacMail: Bool { token?.hasPrefix("mac:") ?? false }
    var isDemo: Bool { token != nil && label == "Demo inbox" }
    func icloud(email: String, appPassword: String) async { label = email; await run { try await Auth.icloud(email: email, appPassword: appPassword) } }
    func gmail() {
        busy = true; error = nil
        GoogleAuth.shared.connect { [weak self] t in
            Task { @MainActor in
                self?.busy = false
                if let t { self?.label = "Gmail"; self?.store(t) } else { self?.error = "Gmail sign-in was cancelled." }
            }
        }
    }

    private func run(_ work: () async throws -> String) async {
        busy = true; error = nil
        defer { busy = false }
        do { store(try await work()) } catch { self.error = error.localizedDescription }
    }
}
