import Foundation

/// Application configuration pointing to the Notes backend API and Clerk Authentication.
enum AppConfig {
    /// Points the app at the Notes backend (the Next.js REST API).
    ///
    /// iOS App Transport Security exempts loopback addresses, so plain
    /// `http://localhost:3000` works for the Simulator talking to Next.js on the same Mac.
    /// For a physical device, change this to your Mac's LAN IP (e.g. `http://192.168.1.50:3000`)
    /// or your production HTTPS domain.
    nonisolated(unsafe) static var baseURL = URL(string: "http://localhost:3000")!

    /// Clerk publishable key.
    /// Matches the backend's `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` so JWT session tokens
    /// issued by Clerk on iOS match the backend's `CLERK_SECRET_KEY`.
    nonisolated(unsafe) static var clerkPublishableKey = "pk_test_cmVmaW5lZC1iZWV0bGUtMzguY2xlcmsuYWNjb3VudHMuZGV2JA"
}
