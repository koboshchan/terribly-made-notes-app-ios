import SwiftUI
import ClerkKit

@main
struct NotesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Clerk.shared)
        }
    }
}
