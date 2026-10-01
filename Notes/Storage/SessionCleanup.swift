import Foundation

/// Everything that must be removed from the device when a user signs out.
enum SessionCleanup {
    static func signedOut() {
        LocalDataCache.shared.clearAll()
        do { try SharedAuthStore.clear() } catch { print("Shared session clear failed: \(error.localizedDescription)") }
        UploadStore.shared.clearAll()
    }
}
