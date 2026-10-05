#if os(macOS)
import SwiftUI

/// The whole Mac app: how much mail there is, one button, inbox zero. Nothing is deleted.
struct SimpleInboxView: View {
    @EnvironmentObject var session: Session
    @State private var count: Int?
    @State private var busy = false
    @State private var line = ""
    @State private var gmailLeft = 0
    @State private var accounts: [(name: String, count: Int, note: String?)] = []

    private let ink = Color(red: 0.71, green: 0.31, blue: 0.17)

    /// White in light mode, the system dark in dark mode.
    private let paper = Color(nsColor: .textBackgroundColor)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            paper.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text(count.map { $0 + gmailLeft == 0 ? "Inbox zero" : "\($0 + gmailLeft)" } ?? " ")
                    .font(.system(size: shownZero ? 64 : 120, weight: .semibold))
                    .accessibilityIdentifier("count")
                    .foregroundStyle(shownZero ? ink : .primary)
                    .contentTransition(.numericText())
                Text(shownZero ? "Nothing left to do." : (count == 0 ? "Gmail can't be cleared from Mail. Sign in to Gmail." : "in your inbox"))
                    .font(.title2).foregroundStyle(.secondary)
                Button { Task { await clear() } } label: {
                    Text(busy ? "Clearing..." : "Clear inbox").font(.title3.weight(.semibold)).frame(width: 260, height: 32)
                }
                .controlSize(.extraLarge).buttonStyle(.borderedProminent)
                .disabled(busy || (count ?? 0) == 0)
                .padding(.top, 8)
                .accessibilityIdentifier("clear")
                if !accounts.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(accounts, id: \.name) { a in
                            HStack {
                                Text(a.name)
                                if let note = a.note { Text(note).foregroundStyle(.tertiary) }
                                Spacer()
                                Text("\(a.count)").monospacedDigit()
                            }
                            .foregroundStyle(a.note == nil ? .primary : .secondary)
                        }
                    }
                    .font(.callout).frame(width: 260).padding(.top, 6)
                }
                Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 44)
                    .accessibilityIdentifier("result")
                Spacer()
            }
            .padding(40)
            .frame(maxWidth: .infinity)
            Button("Sign out") { session.signOut() }
                .buttonStyle(.plain).accessibilityIdentifier("signout").font(.callout).foregroundStyle(.secondary)
                .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
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

    private var shownZero: Bool { count != nil && (count ?? 0) + gmailLeft == 0 }

    private func load() async {
        do { count = try await inbox().count; line = ""; try refreshAccounts() } catch { line = error.localizedDescription }
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
            try refreshAccounts()
            line = "Filed \(moved). Machine mail is in its Hagaki box, people are in Archive. Nothing was deleted."
        } catch { line = error.localizedDescription }
    }

    /// Mail.app mode lists every account on the Mac; otherwise the one account you signed in with.
    private func refreshAccounts() throws {
        #if DEBUG
        if session.isMacMail {
            let all = try MacMail.accounts()
            gmailLeft = all.filter(\.isGmail).map(\.count).reduce(0, +)
            accounts = all.map { ($0.name, $0.count, $0.isGmail ? "Gmail" : nil) }
            return
        }
        #endif
        gmailLeft = 0
        accounts = [(session.label, count ?? 0, nil)]
    }

    private func clearAccount(_ messages: [Message]) async throws -> Int {
        guard let api = session.api else { return 0 }
        let filed = try await api.organize(messages.filter { $0.folder != nil }).total
        for m in messages where m.folder == nil { try await api.perform(.archive, on: m) }
        return filed + messages.filter { $0.folder == nil }.count
    }
}
#endif
