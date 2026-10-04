import SwiftUI

struct InboxView: View {
    @EnvironmentObject var session: Session
    @State private var messages: [Message] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var note: String?
    @State private var filing = false

    private var filable: [Message] { messages.filter { $0.folder != nil } }
    private var staying: [Message] { messages.filter { $0.folder == nil } }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
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
                ForEach(smartFolders, id: \.self) { folder in
                    let inBox = messages.filter { $0.folder == folder }
                    if !inBox.isEmpty { Section("\(folder) (\(inBox.count))") { ForEach(inBox) { row($0) } } }
                }
                if !staying.isEmpty { Section("Stays in your inbox (\(staying.count))") { ForEach(staying) { row($0) } } }
            }
            .refreshable { await load() }
            .navigationTitle("Inbox")
            .toolbar {
                Button(filing ? "Filing..." : "File everything") { Task { await fileAll() } }
                    .disabled(filable.isEmpty || filing)
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
            Text(m.isJunk ? "\(m.score) signals: \(m.reasons.joined(separator: ", "))" : (m.folder == nil ? "A person, stays put" : "Goes to \(m.folder!)"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await run(.delete, m) } }
            Button("Archive") { Task { await run(.archive, m) } }.tint(.gray)
            if let folder = m.folder { Button("File") { Task { await run(.organize, m) } }.tint(.accentColor).accessibilityLabel("File to \(folder)") }
        }
        .swipeActions(edge: .leading) {
            if ["Junk", "Promotions", "Newsletters"].contains(m.category ?? "") && (m.listUnsubscribe ?? "").isEmpty == false {
                Button("Unsubscribe") { Task { await run(.unsubscribe, m) } }.tint(.accentColor)
            }
        }
        .contextMenu {
            if ["Junk", "Promotions", "Newsletters"].contains(m.category ?? "") && (m.listUnsubscribe ?? "").isEmpty == false {
                Button("Unsubscribe") { Task { await run(.unsubscribe, m) } }
            }
            if let folder = m.folder { Button("File to \(folder)") { Task { await run(.organize, m) } } }
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

    private func fileAll() async {
        guard let api = session.api else { return }
        filing = true; defer { filing = false }
        do {
            let result = try await api.organize(filable)
            let filedFolders = Set(result.organized.keys)
            withAnimation { messages.removeAll { $0.folder.map(filedFolders.contains) ?? false } }
            note = "Filed \(result.total) into \(filedFolders.count) boxes\(result.failed > 0 ? ", \(result.failed) failed" : ""). Nothing was deleted."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func run(_ action: Action, _ m: Message) async {
        guard let api = session.api else { return }
        do {
            try await api.perform(action, on: m)
            withAnimation { messages.removeAll { $0.id == m.id } }
        } catch { self.error = error.localizedDescription }
    }
}
