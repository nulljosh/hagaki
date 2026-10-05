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
    @State private var gmailLeft = 0
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
            bigButton("Sign in to Gmail") { clearAfterSignIn = true; session.gmail() }
                .disabled(session.busy)
                .accessibilityIdentifier("gmail")
        } else if isZero {
            Button("Check again") { Task { await load() } }.buttonStyle(.link).accessibilityIdentifier("again")
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
        do {
            let n = try await inbox().count
            try refreshAccounts()
            withAnimation { count = n }
            if failed { line = "" }
            failed = false
        } catch {
            // a newer load replaced this one (the session changed mid-flight): not an error
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if error.localizedDescription.hasPrefix("Session expired") { session.signOut(); return }
            failed = true; line = error.localizedDescription; return
        }
        // `-clear`, or arriving from "Sign in to Gmail": an empty inbox was already asked for, so finish the job.
        if (count ?? 0) > 0, autoClear || (clearAfterSignIn && !session.isMacMail) {
            autoClear = false; clearAfterSignIn = false
            await clear()
        }
    }

    private func clear() async {
        busy = true; defer { busy = false }
        do {
            let messages = try await inbox()
            let filed = messages.filter { $0.folder != nil }.count
            var moved = 0
            #if DEBUG
            if session.isMacMail { moved = try MacMail.clear(messages) } else { moved = try await clearAccount(messages) }
            #else
            moved = try await clearAccount(messages)
            #endif
            // ponytail: the demo inbox is fixed sample mail on the server, so a cleared demo is zero by definition
            let after = try await inbox().count
            try refreshAccounts()
            withAnimation { count = session.isDemo ? 0 : after; failed = false }
            line = "Filed \(min(filed, moved)), archived \(max(moved - filed, 0)). Nothing was deleted."
        } catch { line = error.localizedDescription }
    }

    /// Gmail accounts in Mail.app still count toward the number, they just cannot be cleared from here.
    private func refreshAccounts() throws {
        #if DEBUG
        if session.isMacMail { gmailLeft = try MacMail.accounts().filter(\.isGmail).map(\.count).reduce(0, +); return }
        #endif
        gmailLeft = 0
    }

    private func clearAccount(_ messages: [Message]) async throws -> Int {
        guard let api = session.api else { return 0 }
        let filed = try await api.organize(messages.filter { $0.folder != nil }).total
        let people = messages.filter { $0.folder == nil }
        for m in people { try await api.perform(.archive, on: m) }
        return filed + people.count
    }
}
#endif
