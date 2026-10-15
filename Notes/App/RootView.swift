import SwiftUI
import ClerkKit
import ClerkKitUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false

    var body: some View {
        Group {
            if clerk.user != nil {
                HomeView()
            } else {
                WelcomeView { authIsPresented = true }
            }
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
    }
}
