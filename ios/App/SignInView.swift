import SwiftUI

struct SignInView: View {
    @EnvironmentObject var session: Session
    @State private var showICloud = false
    @State private var email = ""
    @State private var appPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Hagaki reads your inbox, scores the junk, and clears it in a tap. It only acts when you tap.")
                        .foregroundStyle(.secondary)
                }
                Section("Sign in") {
                    Button("Continue with Gmail") { session.gmail() }
                    Button("Continue with iCloud Mail") { withAnimation { showICloud.toggle() } }
                    if showICloud {
                        TextField("you@icloud.com", text: $email)
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            #endif
                        SecureField("App-specific password", text: $appPassword)
                        Link("How to make an app-specific password", destination: URL(string: "https://support.apple.com/en-us/102654")!)
                            .font(.footnote)
                        Button("Sign in to iCloud") { Task { await session.icloud(email: email, appPassword: appPassword) } }
                            .disabled(email.isEmpty || appPassword.isEmpty)
                    }
                }
                Section {
                    Button("Try the demo inbox") { Task { await session.demo() } }
                } footer: {
                    Text("Sample mail. No account needed and nothing real is touched.")
                }
                if let error = session.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .disabled(session.busy)
            .overlay { if session.busy { ProgressView() } }
            .navigationTitle("Hagaki")
        }
    }
}
