import Foundation
import Network
import SwiftUI

@Observable
@MainActor
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    public private(set) var isConnected: Bool = true
    public private(set) var isExpensive: Bool = false
    public private(set) var isConstrained: Bool = false

    @ObservationIgnored
    private let monitor = NWPathMonitor()
    @ObservationIgnored
    private let monitorQueue = DispatchQueue(label: "com.kobosh.notes.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = (path.status == .satisfied)
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
