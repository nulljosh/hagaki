#if os(macOS)
import SwiftUI

/// The whole Mac app: how much mail there is, one button, inbox zero. Nothing is deleted.
struct SimpleInboxView: View {
    @EnvironmentObject var session: Session
    @State private var count: Int?
    @State private var busy = false
    @State private var line = ""

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(count.map { $0 == 0 ? "Inbox zero" : "\($0)" } ?? " ")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .foregroundStyle(count == 0 ? Color.accentColor : .primary)
            Text(count == 0 ? "Nothing left to do." : "in your inbox")
                .font(.title3).foregroundStyle(.secondary)
            Button { Task { await clear() } } label: {
                Text(busy ? "Clearing..." : "Clear inbox").frame(width: 180)
            }
            .controlSize(.large).buttonStyle(.borderedProminent)
            .disabled(busy || (count ?? 0) == 0)
            Text(line).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 36)
            Spacer()
            Button("Sign out") { session.signOut() }.buttonStyle(.link).font(.footnote)
        }
        .padding(32)
        .frame(minWidth: 380, minHeight: 420)
        .task(id: session.token) { await load() }
    }

    /// Mail.app mode reads the Mac's own inbox; otherwise the signed-in Gmail/iCloud account.
    private func inbox() async throws -> [Message] {
        guard let api = session.api else { return [] }
        #if DEBUG
        if session.isMacMail {
            let items = try MacMail.inbox()
            return items.isEmpty ? [] : try await api.sort(items)
        }
        #endif
        return try await api.messages()
    }

    private func load() async {
        do { count = try await inbox().count; line = "" } catch { line = error.localizedDescription }
        if CommandLine.arguments.contains("-hagakiClear"), (count ?? 0) > 0 { await clear() }
    }

    private func clear() async {
        busy = true; defer { busy = false }
        do {
            let messages = try await inbox()
            var moved = 0
            #if DEBUG
            if session.isMacMail { moved = try MacMail.clear(messages) } else { moved = try await clearAccount(messages) }
            #else
            moved = try await clearAccount(messages)
            #endif
            count = try await inbox().count
            line = "Filed \(moved). Machine mail is in its Hagaki box, people are in Archive. Nothing was deleted."
        } catch { line = error.localizedDescription }
    }

    private func clearAccount(_ messages: [Message]) async throws -> Int {
        guard let api = session.api else { return 0 }
        let filed = try await api.organize(messages.filter { $0.folder != nil }).total
        for m in messages where m.folder == nil { try await api.perform(.archive, on: m) }
        return filed + messages.filter { $0.folder == nil }.count
    }
}
#endif
