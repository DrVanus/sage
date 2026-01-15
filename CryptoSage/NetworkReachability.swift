import Foundation
import Network
import Combine

/// Shared network reachability state for the app.
/// - Publishes `isReachable` so services can pause/resume work based on connectivity.
final class NetworkReachability: ObservableObject {
    static let shared = NetworkReachability()

    @Published private(set) var isReachable: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachability.queue")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isReachable = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
