import Foundation
import Network
import Combine

/// Shared network reachability state for the app.
/// - Publishes `isReachable` so services can pause/resume work based on connectivity.
/// - Publishes `isConstrained` for slow/expensive networks (cellular, metered connections)
final class NetworkReachability: ObservableObject {
    static let shared = NetworkReachability()

    @Published private(set) var isReachable: Bool = true
    
    /// True when on cellular or constrained/metered connection
    /// Use this to reduce data-heavy operations like sparkline pre-fetching
    @Published private(set) var isConstrained: Bool = false
    
    /// True when explicitly on cellular (not WiFi)
    @Published private(set) var isCellular: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachability.queue")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isReachable = (path.status == .satisfied)
                // Check for constrained (metered/data saver) or expensive (cellular) connections
                self?.isConstrained = path.isConstrained || path.isExpensive
                // Check if using cellular interface
                self?.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
    
    /// Returns the recommended sparkline pre-fetch count based on network conditions
    /// - Fast network (WiFi, unconstrained): 32 coins ahead
    /// - Slow network (cellular, constrained): 16 coins ahead
    var recommendedPrefetchCount: Int {
        isConstrained || isCellular ? 16 : 32
    }
}
