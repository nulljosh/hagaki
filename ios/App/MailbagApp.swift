import SwiftUI

/// The one accent. A lighter blue in dark mode so it still reads on a dark window.
#if os(macOS)
let brandBlue = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.36, green: 0.56, blue: 0.94, alpha: 1) : NSColor(red: 0.12, green: 0.37, blue: 0.82, alpha: 1) })
#else
let brandBlue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.56, blue: 0.94, alpha: 1) : UIColor(red: 0.12, green: 0.37, blue: 0.82, alpha: 1) })
#endif

/// Launch flags are passed as `-name YES`. A bare `-name` swallows the next argument.
func launchFlag(_ name: String) -> Bool { UserDefaults.standard.bool(forKey: name) }

/// Sign-in or the inbox, whichever the session calls for. Shared by the Mac window and the iOS scene.
struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        Group {
            if session.token == nil { SignInView() } else {
                #if os(macOS)
                SimpleInboxView()
                #else
                InboxView()
                #endif
            }
        }
        .tint(brandBlue)
        // `-dark YES` forces dark mode for screenshots
        .preferredColorScheme(launchFlag("dark") ? .dark : nil)
        // runs at launch, and again whenever the app ends up with no session
        .task(id: session.token == nil) {
            // `-demo YES` opens straight into the sample inbox, so screenshots need no taps. `-signedOut YES` shows
            // sign-in. Both run on a throwaway session (see Session.scripted) and leave the real sign-in alone.
            if launchFlag("demo"), !session.isDemo { await session.demo() }
            #if os(macOS) && DEBUG
            // The personal build exists to clear this Mac's own mail, so with nothing saved it starts there.
            if !session.isMacMail, launchFlag("macMail") || (session.token == nil && !session.scripted && !session.choseToSignOut) { await session.macMail() }
            #endif
        }
    }
}

@main
struct MailbagApp: App {
    @StateObject private var session = Session.shared

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacWindow.self) private var macWindow

    // The main window belongs to MacWindow, not to a WindowGroup. See the note there.
    var body: some Scene {
        Settings { SettingsView().environmentObject(session).tint(brandBlue) }
    }
    #else
    var body: some Scene {
        WindowGroup { RootView().environmentObject(session) }
    }
    #endif
}

#if os(macOS)
/// Owns the one Mac window. A SwiftUI WindowGroup did not present its window when the app was launched without
/// being brought to the front (opened while another app had focus, or by the test runner), and bringing the app
/// forward later did not help: the app ran with no window at all. AppKit makes the window here at launch, every
/// time, and brings it back whenever the app is reopened.
@MainActor
final class MacWindow: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) { show() }

    /// A Dock click or a second launch while the window is closed or minimised.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    /// One window is the whole app, so closing it quits. No running-but-invisible state to get stuck in.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: RootView().environmentObject(Session.shared))
            host.sizingOptions = [.preferredContentSize] // the window is exactly as big as its content
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = appName
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif
