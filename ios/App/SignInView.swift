import SwiftUI

/// The name on the store listing, read from the bundle so a rename never touches the views.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mail"

private let pitch = "Machine mail goes into seven folders. People go to your archive. Nothing is deleted, and nothing moves until you press a button."
private let aiNote = "To sort what the rules cannot, the sender, subject and a short preview go to a language model on our server. You can turn that off in Settings."

struct SignInView: View {
    @EnvironmentObject var session: Session
    @State private var showICloud = false
    @State private var email = ""
    @State private var appPassword = ""

    @ViewBuilder private var icloudFields: some View {
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

    #if os(macOS)
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(appName).font(.system(size: 34, weight: .semibold)).padding(.top, 10)
            Text("Inbox zero, one button.").font(.title3).foregroundStyle(.secondary).padding(.top, 4)

            VStack(spacing: 10) {
                wide("Continue with Gmail", prominent: true) { session.gmail() }
                wide("Continue with iCloud Mail") { withAnimation { showICloud.toggle() } }
                if showICloud {
                    VStack(spacing: 8) { icloudFields }.textFieldStyle(.roundedBorder).frame(width: 260).padding(.vertical, 4)
                }
                #if DEBUG
                wide("Use Mail on this Mac") { Task { await session.macMail() } }
                #endif
            }
            .padding(.top, 28)

            Button("Try the demo inbox") { Task { await session.demo() } }
                .buttonStyle(.link).padding(.top, 16)

            if let error = session.error {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center).padding(.top, 14)
            }
            Text(pitch + " " + aiNote)
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
        }
        .padding(.horizontal, 48).padding(.top, 44).padding(.bottom, 36)
        .frame(width: 440)
        .background(paper.ignoresSafeArea())
        .fixedSize(horizontal: false, vertical: true)
        .disabled(session.busy)
        .overlay { if session.busy { ProgressView() } }
    }

    private func wide(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let label = Text(title).font(.body.weight(prominent ? .semibold : .regular)).frame(width: 236, height: 22)
        return Group {
            if prominent {
                Button(action: action) { label }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button(action: action) { label }.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
    #else
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(pitch).foregroundStyle(.secondary)
                }
                Section("Sign in") {
                    Button("Continue with Gmail") { session.gmail() }
                    Button("Continue with iCloud Mail") { withAnimation { showICloud.toggle() } }
                    if showICloud { icloudFields }
                }
                Section {
                    Button("Try the demo inbox") { Task { await session.demo() } }
                } footer: {
                    Text("Sample mail. No account needed and nothing real is touched.")
                }
                Section {} footer: {
                    Text(aiNote.replacingOccurrences(of: "in Settings", with: "from the menu in the inbox"))
                }
                if let error = session.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .disabled(session.busy)
            .overlay { if session.busy { ProgressView() } }
            .navigationTitle(appName)
        }
    }
    #endif
}
