import Foundation

/// Everything that must be removed from the device when a user signs out.
enum SessionCleanup {
    /// Cancels in-flight uploads on BOTH background sessions before wiping the
    /// queue, so nothing is sent with the previous account's token afterwards.
    @MainActor
    static func signedOut() async {
        await BackgroundUploader.shared(identifier: BackgroundUploader.appSessionID).cancelAll()
        await BackgroundUploader.shared(identifier: BackgroundUploader.shareSessionID).cancelAll()
        UploadStore.shared.clearAll()
        LocalDataCache.shared.clearAll()
        do { try SharedAuthStore.clear() } catch { print("Shared session clear failed: \(error.localizedDescription)") }
    }
}
