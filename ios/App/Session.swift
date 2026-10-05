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
        guard let value else { SecItemDelete(query(key) as CFDictionary); return }
        let data = [kSecValueData as String: Data(value.utf8)]
        // update in place when the item exists: a delete that fails quietly would leave the old value behind an add that then fails too
        if SecItemUpdate(query(key) as CFDictionary, data as CFDictionary) == errSecSuccess { return }
        SecItemDelete(query(key) as CFDictionary)
        SecItemAdd(query(key).merging(data) { $1 } as CFDictionary, nil)
    }
}

@MainActor
final class Session: ObservableObject {
    /// One session for the whole app: the Mac window and the Settings window both read it.
    static let shared = Session()

    /// The demo, the scripted launches used for tests and screenshots (`-demo YES`, `-signedOut YES`) and the unit
    /// test host never read or write the saved sign-in. Without this one test run leaves the real app sitting in
    /// the demo inbox, which is exactly what happened on 2026-10-04.
    let scripted = launchFlag("demo") || launchFlag("signedOut") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @Published private(set) var token: String?
    @Published private(set) var label = "Inbox"
    /// True after Sign out is pressed, until the next sign-in. Keeps the personal build from walking straight back into Mail.app mode.
    private(set) var choseToSignOut = false
    @Published var busy = false
    @Published var error: String?

    /// Gmail sign-ins that live next to Mail.app mode, keyed by lowercased address. Mail.app cannot move Gmail,
    /// so each Gmail account on the Mac gets its own session and is cleared through Gmail itself.
    @Published private(set) var gmailTokens: [String: String] = [:]

    init() {
        guard !scripted else { return }
        token = Keychain.get("session")
        label = UserDefaults.standard.string(forKey: "label") ?? "Inbox"
        gmailTokens = Session.savedGmail()
        // the demo is never kept; one saved by an older build is dropped here
        if label == "Demo inbox" { store(nil) }
        Task { await dropSavedDemo() }
    }

    /// Older builds saved the demo session like a real sign-in, sometimes under another label. Ask the server what
    /// the saved session is, and if it is the demo, forget it, so the app never opens on sample mail by itself.
    private func dropSavedDemo() async {
        guard let saved = token, !saved.hasPrefix("mac:"), let api else { return }
        if let who = try? await api.whoami(), who.provider == "demo", token == saved { store(nil) }
    }

    private static func savedGmail() -> [String: String] {
        guard let data = Keychain.get("gmail")?.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private func saveGmail() {
        guard !scripted else { return }
        let json = (try? JSONEncoder().encode(gmailTokens)).flatMap { String(data: $0, encoding: .utf8) }
        Keychain.set("gmail", gmailTokens.isEmpty ? nil : json)
    }

    func gmailAPI(for email: String) -> API? { gmailTokens[email.lowercased()].map { API(token: $0) } }

    func forgetGmail(_ email: String) {
        guard let t = gmailTokens.removeValue(forKey: email.lowercased()) else { return }
        saveGmail()
        Task { await API(token: t).logout() }
    }

    /// Adds a Gmail account without leaving Mail.app mode. `hint` preselects the address in Google's chooser.
    func addGmail(hint: String? = nil) {
        busy = true; error = nil
        GoogleAuth.shared.connect(loginHint: hint) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                defer { self.busy = false }
                guard let t else { self.error = "Gmail sign-in was cancelled."; return }
                guard let email = try? await API(token: t).whoami().email, !email.isEmpty else {
                    self.error = "Signed in, but Gmail did not say which account."
                    await API(token: t).logout()
                    return
                }
                if let old = self.gmailTokens[email.lowercased()], old != t { await API(token: old).logout() }
                self.gmailTokens[email.lowercased()] = t
                self.saveGmail()
            }
        }
    }

    var api: API? { token.map { API(token: $0.hasPrefix("mac:") ? String($0.dropFirst(4)) : $0) } }

    /// `save: false` keeps the session in memory only. The demo uses it, so a relaunch never lands back in sample mail.
    func store(_ t: String?, label newLabel: String = "Inbox", save: Bool = true) {
        token = t; label = newLabel
        if t != nil { choseToSignOut = false }
        guard save, !scripted else { return }
        Keychain.set("session", t)
        UserDefaults.standard.set(newLabel, forKey: "label")
    }

    /// Signs out of everything: the main session and every added Gmail account, here and on the server.
    func signOut() {
        choseToSignOut = true
        let tokens = [api?.token].compactMap { $0 } + Array(gmailTokens.values)
        store(nil)
        gmailTokens = [:]; saveGmail()
        Task { for t in tokens { await API(token: t).logout() } }
    }

    func demo() async { await run(label: "Demo inbox", save: false) { try await Auth.demo() } }
    /// Mail.app mode keeps a server token for /api/sort, prefixed so the inbox knows to read Mail.app.
    func macMail() async { await run(label: "Mail on this Mac") { "mac:" + (try await Auth.mac()) } }
    var isMacMail: Bool { token?.hasPrefix("mac:") ?? false }
    var isDemo: Bool { token != nil && label == "Demo inbox" }
    func icloud(email: String, appPassword: String) async { await run(label: email) { try await Auth.icloud(email: email, appPassword: appPassword) } }
    func gmail() {
        busy = true; error = nil
        GoogleAuth.shared.connect { [weak self] t in
            Task { @MainActor in
                self?.busy = false
                if let t { self?.store(t, label: "Gmail") } else { self?.error = "Gmail sign-in was cancelled." }
            }
        }
    }

    private func run(label: String, save: Bool = true, _ work: () async throws -> String) async {
        busy = true; error = nil
        defer { busy = false }
        do { store(try await work(), label: label, save: save) } catch { self.error = error.localizedDescription }
    }
}
