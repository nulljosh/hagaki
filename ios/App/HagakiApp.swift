import SwiftUI

@main
struct HagakiApp: App {
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
            .tint(Color(red: 0.71, green: 0.31, blue: 0.17))
            .task {
                // `-hagakiDemo` opens straight into the sample inbox, so screenshots need no taps.
                if CommandLine.arguments.contains("-hagakiDemo"), session.token == nil { await session.demo() }
                #if os(macOS) && DEBUG
                if CommandLine.arguments.contains("-hagakiClear"), !session.isMacMail { await session.macMail() }
                #endif
            }
        }
        #if os(macOS)
        .defaultSize(width: 560, height: 640)
        #endif
    }
}
