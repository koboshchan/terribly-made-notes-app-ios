import Foundation

/// Application configuration pointing to the Notes backend API and Clerk Authentication.
enum AppConfig {
    /// Points the app at the production Notes backend.
    nonisolated(unsafe) static var baseURL = URL(string: "https://notes.kobosh.com")!

    /// Production Clerk publishable key for notes.kobosh.com.
    nonisolated(unsafe) static var clerkPublishableKey = "pk_live_Y2xlcmsubm90ZXMua29ib3NoLmNvbSQ"
}
