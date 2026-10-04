import SwiftUI

struct InboxView: View {
    @EnvironmentObject var session: Session
    @State private var messages: [Message] = []
    @State private var loaded = false
    @State private var error: String?

    private var junk: [Message] { messages.filter(\.isJunk) }
    private var legit: [Message] { messages.filter { !$0.isJunk } }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if loaded && messages.isEmpty {
                    Text("Inbox is clean. Nothing to triage.").foregroundStyle(.secondary)
                }
                let repeats = repeatSenders(messages)
                if !repeats.isEmpty {
                    Section("Repeat senders") {
                        ForEach(repeats, id: \.domain) { sender in
                            HStack {
                                Text("\(sender.domain) (\(sender.messages.count))")
                                Spacer()
                                Button("Unsubscribe all") { Task { for m in sender.messages { await run(.unsubscribe, m) } } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                if !junk.isEmpty { Section("Junk (\(junk.count))") { ForEach(junk) { row($0) } } }
                if !legit.isEmpty { Section("Looks legit") { ForEach(legit) { row($0) } } }
            }
            .refreshable { await load() }
            .navigationTitle("Inbox")
            .toolbar {
                Menu {
                    Button("Refresh") { Task { await load() } }
                    Button("Sign out", role: .destructive) { session.signOut() }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
            .overlay { if !loaded && error == nil { ProgressView() } }
            .task { await load() }
        }
    }

    private func row(_ m: Message) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(m.sender).font(.subheadline.weight(.semibold)).foregroundStyle(m.isJunk ? Color.accentColor : .primary)
            Text(m.subject ?? "(no subject)").font(.subheadline)
            Text(m.isJunk ? "Junk, \(m.score) signals: \(m.reasons.joined(separator: ", "))" : "Looks legit")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await run(.delete, m) } }
            Button("Archive") { Task { await run(.archive, m) } }.tint(.gray)
        }
        .swipeActions(edge: .leading) {
            if m.isJunk && (m.listUnsubscribe ?? "").isEmpty == false {
                Button("Unsubscribe") { Task { await run(.unsubscribe, m) } }.tint(.accentColor)
            }
        }
        .contextMenu {
            if m.isJunk && (m.listUnsubscribe ?? "").isEmpty == false {
                Button("Unsubscribe") { Task { await run(.unsubscribe, m) } }
            }
            Button("Archive") { Task { await run(.archive, m) } }
            Button("Delete", role: .destructive) { Task { await run(.delete, m) } }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        do { messages = try await api.messages(); error = nil } catch {
            self.error = error.localizedDescription
            if error.localizedDescription.hasPrefix("Session expired") { session.signOut() }
        }
        loaded = true
    }

    private func run(_ action: Action, _ m: Message) async {
        guard let api = session.api else { return }
        do {
            try await api.perform(action, on: m)
            withAnimation { messages.removeAll { $0.id == m.id } }
        } catch { self.error = error.localizedDescription }
    }
}
