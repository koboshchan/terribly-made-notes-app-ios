import UIKit

/// Delivers background URLSession events for uploads started by the app or by
/// the share extension (extension sessions are handed to the containing app).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploader.appSessionID || identifier == BackgroundUploader.shareSessionID else {
            completionHandler()
            return
        }
        BackgroundUploader.shared(identifier: identifier).reconnect(eventsCompletion: completionHandler)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundUploader.shared(identifier: BackgroundUploader.appSessionID).reconnect()
        return true
    }
}
