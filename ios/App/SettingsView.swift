#if os(macOS)
import SwiftUI

/// Settings (Cmd-comma): the accounts Mailbag sees, and sign out.
struct SettingsView: View {
    @EnvironmentObject var session: Session
    @AppStorage("aiSort") private var aiSort = true
    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let name: String, detail: String, count: Int
        /// Set for a Gmail account in Mail.app mode: its address, and whether it has been signed in to.
        var gmail: (email: String, connected: Bool)?
        var id: String { name }
    }

    var body: some View {
        Form {
            Section("Accounts") {
                if session.token == nil {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    LabeledContent {
                        HStack(spacing: 12) {
                            Text("\(r.count) in inbox").monospacedDigit()
                            if let g = r.gmail {
                                if g.connected {
                                    Button("Disconnect") { session.forgetGmail(g.email) }
                                } else {
                                    Button("Sign in") { session.addGmail(hint: g.email) }.disabled(session.busy)
                                }
                            }
                        }
                    } label: {
                        Text(r.name)
                        Text(r.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = session.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Toggle("Smart sorting", isOn: $aiSort)
            } footer: {
                Text("Rules sort most mail. For machine mail they cannot place, the sender, subject and a short preview go to a language model on our server. Mail from people is never sent. Turn this off to use rules only.")
            }
            if session.token != nil {
                Section {
                    Button("Sign out", role: .destructive) { session.signOut() }
                        .accessibilityIdentifier("signout")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440).fixedSize(horizontal: false, vertical: true)
        .task(id: [session.token ?? ""] + session.gmailTokens.keys.sorted()) { await load() }
    }

    private func load() async {
        guard session.token != nil else { rows = []; return }
        #if DEBUG
        if session.isMacMail, let all = try? MacMail.accounts() {
            rows = all.map { a in
                guard a.isGmail else { return Row(name: a.name, detail: "Mail on this Mac", count: a.count) }
                let connected = session.gmailAPI(for: a.email) != nil
                return Row(name: a.name, detail: connected ? "\(a.email), signed in" : "\(a.email), needs a Gmail sign-in to be cleared", count: a.count, gmail: (a.email, connected))
            }
            return
        }
        #endif
        let n = (try? await session.api?.messages().count) ?? 0
        rows = [Row(name: session.label, detail: "Signed in", count: n)]
    }
}
#endif
