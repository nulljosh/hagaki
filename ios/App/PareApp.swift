import SwiftUI

@main
struct PareApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.token == nil { SignInView() } else { InboxView() }
            }
            .environmentObject(session)
            .tint(Color(red: 0.71, green: 0.31, blue: 0.17))
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 760)
        #endif
    }
}
