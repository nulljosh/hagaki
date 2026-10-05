#if os(macOS)
import SwiftUI

/// Settings (Cmd-comma): the accounts Mailbag sees, and sign out.
struct SettingsView: View {
    @EnvironmentObject var session: Session
    @AppStorage("aiSort") private var aiSort = true
    @State private var rows: [(name: String, detail: String, count: Int)] = []

    var body: some View {
        Form {
            Section("Accounts") {
                if session.token == nil {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.name) { r in
                    LabeledContent {
                        Text("\(r.count) in inbox").monospacedDigit()
                    } label: {
                        Text(r.name)
                        Text(r.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle("Smart sorting", isOn: $aiSort)
            } footer: {
                Text("Rules sort most mail. For the rest, the sender, subject and a short preview go to a language model on our server. Turn this off to use rules only.")
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
        .task(id: session.token) { await load() }
    }

    private func load() async {
        guard session.token != nil else { rows = []; return }
        #if DEBUG
        if session.isMacMail, let all = try? MacMail.accounts() {
            rows = all.map { ($0.name, $0.isGmail ? "Gmail in Mail.app, sign in to Gmail to clear" : "Mail on this Mac", $0.count) }
            return
        }
        #endif
        let n = (try? await session.api?.messages().count) ?? 0
        rows = [(session.label, "Signed in", n)]
    }
}
#endif
