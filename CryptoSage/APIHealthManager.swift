import Foundation
import Combine

/// Centralized manager to track the health status of various API services
/// and provide a global "degraded mode" flag when multiple services are unavailable.
@MainActor
final class APIHealthManager: ObservableObject {
    static let shared = APIHealthManager()
    
    // MARK: - Service Status
    
    enum ServiceID: String, CaseIterable {
        case binance = "Binance"
        case coinGecko = "CoinGecko"
        case pumpFun = "PumpFun"
        case coinbase = "Coinbase"
    }
    
    enum ServiceStatus {
        case healthy
        case degraded(reason: String)
        case blocked(until: Date, reason: String)
    }
    
    // MARK: - Published State
    
    /// True when multiple services are in degraded/blocked state
    @Published private(set) var isDegradedMode: Bool = false
    
    /// Number of services currently blocked or degraded
    @Published private(set) var degradedServiceCount: Int = 0
    
    /// Human-readable summary of API health
    @Published private(set) var healthSummary: String = "All services healthy"
    
    /// Timestamp of when degraded mode was entered (nil if not degraded)
    @Published private(set) var degradedModeStartedAt: Date? = nil
    
    // MARK: - Internal State
    
    private var serviceStatuses: [ServiceID: ServiceStatus] = [:]
    private var lastStatusUpdate: [ServiceID: Date] = [:]
    
    /// Threshold for considering the app in "degraded mode"
    private let degradedThreshold: Int = 2 // 2+ services down = degraded
    
    /// Cooldown multiplier when in degraded mode (slows retry attempts)
    private let degradedCooldownMultiplier: Double = 2.0
    
    // MARK: - Rate-Limited Logging
    
    private var lastLogAt: Date = .distantPast
    private let logMinInterval: TimeInterval = 120.0  // PERFORMANCE v26: Increased from 30s to 120s to reduce repetitive blocked status logs
    
    // MARK: - Debouncing for @Published Updates
    
    /// Last time recalculateDegradedMode was called - prevents rapid UI updates
    private var lastRecalculateAt: Date = .distantPast
    /// Minimum interval between recalculate calls to reduce SwiftUI redraws
    private let recalculateMinInterval: TimeInterval = 5.0
    
    private init() {
        // Initialize all services as healthy
        for service in ServiceID.allCases {
            serviceStatuses[service] = .healthy
        }
    }
    
    // MARK: - Public API
    
    /// Report a service as healthy
    func reportHealthy(_ service: ServiceID) {
        let wasUnhealthy: Bool
        switch serviceStatuses[service] {
        case .blocked, .degraded:
            wasUnhealthy = true
        default:
            wasUnhealthy = false
        }
        
        serviceStatuses[service] = .healthy
        lastStatusUpdate[service] = Date()
        
        // Recalculate if previously blocked OR degraded
        if wasUnhealthy {
            recalculateDegradedMode()
        }
    }
    
    /// Report a service as degraded (experiencing issues but not fully blocked)
    func reportDegraded(_ service: ServiceID, reason: String) {
        serviceStatuses[service] = .degraded(reason: reason)
        lastStatusUpdate[service] = Date()
        recalculateDegradedMode()
    }
    
    /// Report a service as blocked until a specific time
    func reportBlocked(_ service: ServiceID, until: Date, reason: String) {
        serviceStatuses[service] = .blocked(until: until, reason: reason)
        lastStatusUpdate[service] = Date()
        recalculateDegradedMode()
        
        // Rate-limited logging
        let now = Date()
        if now.timeIntervalSince(lastLogAt) >= logMinInterval {
            #if DEBUG
            print("🔴 [APIHealth] \(service.rawValue) blocked until \(until): \(reason)")
            #endif
            lastLogAt = now
        }
    }
    
    /// Get the current status of a service
    func status(for service: ServiceID) -> ServiceStatus {
        // Check if a blocked service has expired
        if case .blocked(let until, _) = serviceStatuses[service], Date() > until {
            serviceStatuses[service] = .healthy
            recalculateDegradedMode()
        }
        return serviceStatuses[service] ?? .healthy
    }
    
    /// Check if a specific service is currently available
    func isServiceAvailable(_ service: ServiceID) -> Bool {
        switch status(for: service) {
        case .healthy:
            return true
        case .degraded:
            return true // Still usable, just slower
        case .blocked(let until, _):
            return Date() > until
        }
    }
    
    /// Get the recommended cooldown multiplier for retry attempts
    /// Returns 1.0 normally, or degradedCooldownMultiplier when in degraded mode
    func cooldownMultiplier() -> Double {
        isDegradedMode ? degradedCooldownMultiplier : 1.0
    }
    
    /// Get a list of currently blocked services
    func blockedServices() -> [ServiceID] {
        ServiceID.allCases.filter { service in
            if case .blocked(let until, _) = serviceStatuses[service], Date() <= until {
                return true
            }
            return false
        }
    }
    
    // MARK: - Private
    
    private func recalculateDegradedMode() {
        // Debounce to prevent rapid @Published updates that trigger SwiftUI redraws
        let now = Date()
        guard now.timeIntervalSince(lastRecalculateAt) >= recalculateMinInterval else { return }
        lastRecalculateAt = now
        
        var blockedCount = 0
        var degradedCount = 0
        var reasons: [String] = []
        
        for service in ServiceID.allCases {
            switch serviceStatuses[service] {
            case .blocked(let until, let reason):
                if Date() <= until {
                    blockedCount += 1
                    reasons.append("\(service.rawValue): \(reason)")
                }
            case .degraded(let reason):
                degradedCount += 1
                reasons.append("\(service.rawValue): \(reason)")
            case .healthy, .none:
                break
            }
        }
        
        let totalDegraded = blockedCount + degradedCount
        let newDegradedMode = totalDegraded >= degradedThreshold
        
        // Track when we entered degraded mode
        if newDegradedMode && !isDegradedMode {
            degradedModeStartedAt = Date()
            #if DEBUG
            print("⚠️ [APIHealth] Entering degraded mode: \(totalDegraded) services affected")
            #endif
        } else if !newDegradedMode && isDegradedMode {
            degradedModeStartedAt = nil
            #if DEBUG
            print("✅ [APIHealth] Exiting degraded mode")
            #endif
        }
        
        isDegradedMode = newDegradedMode
        degradedServiceCount = totalDegraded
        
        // Update human-readable summary
        if totalDegraded == 0 {
            healthSummary = "All services healthy"
        } else if blockedCount > 0 {
            healthSummary = "\(blockedCount) service(s) blocked"
        } else {
            healthSummary = "\(degradedCount) service(s) degraded"
        }
    }
    
    // MARK: - Request Budget Coordinator
    
    /// Tracks requests per minute to prevent thundering herd and rate limiting
    private var requestsThisMinute: Int = 0
    private var minuteResetAt: Date = Date()
    
    /// Normal mode: 60 requests/minute, Degraded mode: 20 requests/minute
    private let normalRequestLimit: Int = 60
    private let degradedRequestLimit: Int = 20
    
    /// Check if a request can be made within the budget
    /// Call this before making API requests to prevent rate limiting
    func canMakeRequest() -> Bool {
        let now = Date()
        
        // Reset counter at the start of a new minute
        if now.timeIntervalSince(minuteResetAt) > 60 {
            requestsThisMinute = 0
            minuteResetAt = now
        }
        
        let limit = isDegradedMode ? degradedRequestLimit : normalRequestLimit
        if requestsThisMinute >= limit {
            #if DEBUG
            if requestsThisMinute == limit {
                print("⚠️ [APIHealth] Request budget exhausted (\(limit)/min), throttling")
            }
            #endif
            return false
        }
        
        requestsThisMinute += 1
        return true
    }
    
    /// Record a request (useful when request was made without checking budget first)
    func recordRequest() {
        let now = Date()
        if now.timeIntervalSince(minuteResetAt) > 60 {
            requestsThisMinute = 1
            minuteResetAt = now
        } else {
            requestsThisMinute += 1
        }
    }
    
    /// Get current request budget stats
    var requestBudgetStats: (used: Int, limit: Int, resetIn: TimeInterval) {
        let limit = isDegradedMode ? degradedRequestLimit : normalRequestLimit
        let resetIn = max(0, 60 - Date().timeIntervalSince(minuteResetAt))
        return (requestsThisMinute, limit, resetIn)
    }
}
