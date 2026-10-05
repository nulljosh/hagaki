#if os(macOS)
import SwiftUI

/// White in light mode, the system dark in dark mode.
let paper = Color(nsColor: .textBackgroundColor)

/// The whole Mac app: how much mail there is, one button, inbox zero. Nothing is deleted.
struct SimpleInboxView: View {
    @EnvironmentObject var session: Session
    @AppStorage("aiSort") private var aiSort = true
    @State private var count: Int?
    @State private var busy = false
    @State private var line = ""
    @State private var failed = false
    /// Mail in Gmail accounts that Mail.app shows but nobody has signed in to yet.
    @State private var gmailLeft = 0
    /// The unconnected Gmail address to offer in Google's chooser, if there is one.
    @State private var gmailToConnect: String?
    @State private var clearAfterSignIn = false
    @State private var autoClear = launchFlag("clear")

    /// Mail.app cannot move Gmail, so once the rest is clear the button becomes the Gmail sign-in.
    private var needsGmail: Bool { count == 0 && gmailLeft > 0 }
    private var isZero: Bool { count == 0 && gmailLeft == 0 }

    var body: some View {
        VStack(spacing: 0) {
            headline.frame(height: 150)
            Text(caption)
                .font(isZero ? .title.weight(.semibold) : .title2)
                .foregroundStyle(isZero ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("caption")
            action.padding(.top, 28)
            if !line.isEmpty {
                Text(line)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .accessibilityIdentifier("result")
            }
        }
        .padding(.horizontal, 48).padding(.top, 52).padding(.bottom, 56)
        .frame(width: 440)
        .background(paper.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            SettingsLink { Image(systemName: "gearshape").font(.title3) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
                .accessibilityLabel("Settings").accessibilityIdentifier("settings")
                .padding(18)
        }
        // Cmd-R checks again without a visible control
        .background(Button("Check again") { Task { await load() } }.keyboardShortcut("r").opacity(0).accessibilityHidden(true))
        .fixedSize(horizontal: false, vertical: true)
        .task(id: session.token) { await load() }
        .onChange(of: aiSort) { Task { await load() } }
        .onChange(of: session.gmailTokens) { Task { await load() } }
        // Mail is only read when you look: on launch and whenever the app comes forward.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !busy, !session.busy { Task { await load() } }
        }
    }

    @ViewBuilder private var headline: some View {
        if failed {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 64, weight: .medium)).foregroundStyle(.secondary)
        } else if count == nil {
            ProgressView().controlSize(.large)
        } else if isZero {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 96, weight: .medium)).foregroundStyle(brandBlue)
                .accessibilityIdentifier("zero")
        } else {
            Text("\((count ?? 0) + gmailLeft)")
                .font(.system(size: 124, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityIdentifier("count")
        }
    }

    private var caption: String {
        if failed { return "Could not reach your mail." }
        if count == nil { return "Checking your mail" }
        if isZero { return session.isDemo ? "Demo inbox zero" : "Inbox zero" }
        if session.isDemo { return "in the demo inbox" }
        return needsGmail ? "left in Gmail" : "in your inbox"
    }

    @ViewBuilder private var action: some View {
        if failed {
            bigButton("Try again") { Task { await load() } }
        } else if needsGmail {
            bigButton("Sign in to Gmail") { clearAfterSignIn = true; session.addGmail(hint: gmailToConnect) }
                .disabled(session.busy)
                .accessibilityIdentifier("gmail")
        } else if isZero {
            VStack(spacing: 10) {
                Button("Check again") { Task { await load() } }.buttonStyle(.link).accessibilityIdentifier("again")
                // a Gmail account with an empty inbox still needs its sign-in before the next mail can be cleared
                if let gmailToConnect {
                    Button("Connect \(gmailToConnect)") { session.addGmail(hint: gmailToConnect) }
                        .buttonStyle(.link).disabled(session.busy).accessibilityIdentifier("connect")
                }
            }
        } else {
            bigButton(busy ? "Clearing..." : "Clear inbox") { Task { await clear() } }
                .disabled(busy || count == nil)
                .accessibilityIdentifier("clear")
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.title3.weight(.semibold)).frame(width: 260, height: 32) }
            .controlSize(.extraLarge).buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }

    /// One place mail comes from. `api` is nil for Mail.app itself, which is moved over Apple Events.
    private struct Source { let api: API?; let messages: [Message] }

    /// Every inbox this window covers. In Mail.app mode that is Mail's own non-Gmail accounts plus each
    /// Gmail account that has been signed in to; otherwise the one signed-in account.
    private func sources() async throws -> [Source] {
        guard let api = session.api else { return [] }
        #if DEBUG
        if session.isMacMail {
            var out: [Source] = []
            let items = try MacMail.inbox()
            if !items.isEmpty { out.append(Source(api: nil, messages: try await sortInMailMode(items))) }
            var unconnected: [(email: String, count: Int)] = []
            for account in try MacMail.accounts() where account.isGmail {
                guard let gmail = session.gmailAPI(for: account.email) else { unconnected.append((account.email, account.count)); continue }
                do {
                    let messages = try await gmail.messages()
                    if !messages.isEmpty { out.append(Source(api: gmail, messages: messages)) }
                } catch let error as APIError where error.message.hasPrefix("Session expired") {
                    // that Gmail sign-in ran out: drop it and offer the sign-in again, the rest still works
                    session.forgetGmail(account.email)
                    unconnected.append((account.email, account.count))
                }
            }
            gmailLeft = unconnected.map(\.count).reduce(0, +)
            gmailToConnect = gmailToOffer(unconnected)
            return out
        }
        #endif
        gmailLeft = 0; gmailToConnect = nil
        let messages = try await api.messages()
        return messages.isEmpty ? [] : [Source(api: api, messages: messages)]
    }

    #if DEBUG
    /// The Mail.app session only exists to call /api/sort and holds no mailbox, so when it runs out get a new one.
    private func sortInMailMode(_ items: [MailItem]) async throws -> [Message] {
        do { return try await session.api?.sort(items) ?? [] } catch let error as APIError where error.message.hasPrefix("Session expired") {
            await session.macMail()
            guard let api = session.api else { throw error }
            return try await api.sort(items)
        }
    }
    #endif

    private func load() async {
        do {
            let n = try await sources().map(\.messages.count).reduce(0, +)
            withAnimation { count = n }
            if failed { line = "" }
            failed = false
        } catch {
            // a newer load replaced this one (the session changed mid-flight): not an error
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if error.localizedDescription.hasPrefix("Session expired") { session.signOut(); return }
            failed = true; line = error.localizedDescription; return
        }
        // `-clear YES`, or arriving from "Sign in to Gmail": an empty inbox was already asked for, so finish the job.
        if (count ?? 0) > 0, autoClear || clearAfterSignIn {
            autoClear = false; clearAfterSignIn = false
            await clear()
        }
    }

    private func clear() async {
        busy = true; defer { busy = false }
        var filed = 0, archived = 0
        do {
            // Gmail hands over 30 at a time, so go round again until a pass moves nothing.
            for _ in 0..<5 {
                var moved = 0
                for source in try await sources() {
                    let (f, a) = try await clear(source)
                    filed += f; archived += a; moved += f + a
                }
                // ponytail: the demo inbox is fixed sample mail on the server, so one pass is all there is
                if moved == 0 || session.isDemo { break }
            }
            let after = session.isDemo ? 0 : try await sources().map(\.messages.count).reduce(0, +)
            withAnimation { count = after; failed = false }
            line = "Filed \(filed), archived \(archived). Nothing was deleted."
        } catch { line = error.localizedDescription }
    }

    /// Files what has a folder and archives the rest. Returns how many of each actually moved.
    private func clear(_ source: Source) async throws -> (filed: Int, archived: Int) {
        let folderMail = source.messages.filter { $0.folder != nil }
        let people = source.messages.filter { $0.folder == nil }
        guard let api = source.api else {
            #if DEBUG
            return try MacMail.clear(source.messages)
            #else
            return (0, 0)
            #endif
        }
        let filed = folderMail.isEmpty ? 0 : try await api.organize(folderMail).total
        for m in people { try await api.perform(.archive, on: m) }
        return (filed, people.count)
    }
}

/// The Gmail account to offer for sign-in: the first unconnected one that has mail waiting, else the first unconnected.
func gmailToOffer(_ unconnected: [(email: String, count: Int)]) -> String? {
    (unconnected.first { $0.count > 0 } ?? unconnected.first)?.email
}
#endif
