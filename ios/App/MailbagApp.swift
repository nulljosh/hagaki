import SwiftUI

/// The one accent. A lighter blue in dark mode so it still reads on a dark window.
#if os(macOS)
let brandBlue = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.36, green: 0.56, blue: 0.94, alpha: 1) : NSColor(red: 0.12, green: 0.37, blue: 0.82, alpha: 1) })
#else
let brandBlue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.56, blue: 0.94, alpha: 1) : UIColor(red: 0.12, green: 0.37, blue: 0.82, alpha: 1) })
#endif

/// Launch flags are passed as `-name YES`. A bare `-name` swallows the next argument and AppKit then opens no window.
func launchFlag(_ name: String) -> Bool { UserDefaults.standard.bool(forKey: name) }

@main
struct MailbagApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.token == nil { SignInView() } else {
                    #if os(macOS)
                    SimpleInboxView()
                    #else
                    InboxView()
                    #endif
                }
            }
            .environmentObject(session)
            .tint(brandBlue)
            // `-dark YES` forces dark mode for screenshots
            .preferredColorScheme(launchFlag("dark") ? .dark : nil)
            .task {
                // `-demo YES` opens straight into the sample inbox, so screenshots need no taps. `-signedOut YES` shows sign-in.
                if launchFlag("signedOut") { session.signOut() }
                if launchFlag("demo"), !session.isDemo { await session.demo() }
                #if os(macOS) && DEBUG
                if launchFlag("macMail"), !session.isMacMail { await session.macMail() }
                #endif
            }
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        #endif
        #if os(macOS)
        Settings { SettingsView().environmentObject(session).tint(brandBlue) }
        #endif
    }
}
