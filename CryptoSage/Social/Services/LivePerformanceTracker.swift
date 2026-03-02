//
//  LivePerformanceTracker.swift
//  CryptoSage
//
//  Tracks live trading performance from connected exchange portfolios
//  for leaderboard participation. Requires explicit user consent.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Live Performance Tracker

/// Tracks and calculates trading performance from live portfolio data
/// for leaderboard participation. Requires explicit user consent.
@MainActor
public final class LivePerformanceTracker: ObservableObject {
    
    public static let shared = LivePerformanceTracker()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var currentStats: LivePerformanceStats?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var hasConsent: Bool = false
    @Published public private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "live_performance_tracking"
    private let statsStorageKey = "live_performance_stats"
    private let snapshotsStorageKey = "portfolio_snapshots"
    private let updateInterval: TimeInterval = 300 // 5 minutes
    
    // Historical portfolio snapshots for P&L calculation
    private var portfolioSnapshots: [PortfolioSnapshot] = []
    
    // MARK: - Initialization
    
    private init() {
        loadStoredData()
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    /// Request consent for live performance tracking
    public func requestConsent() async -> Bool {
        // In a real implementation, this would show a consent dialog
        // For now, we just track the consent state
        return true
    }
    
    /// Grant consent for live performance tracking
    public func grantConsent() {
        hasConsent = true
        UserDefaults.standard.set(true, forKey: "live_tracking_consent")
        UserDefaults.standard.set(Date(), forKey: "live_tracking_consent_date")
        
        // Update user profile
        Task {
            await updateUserProfileConsent(granted: true)
        }
        
        startTracking()
    }
    
    /// Revoke consent and stop tracking
    public func revokeConsent() {
        hasConsent = false
        UserDefaults.standard.set(false, forKey: "live_tracking_consent")
        UserDefaults.standard.removeObject(forKey: "live_tracking_consent_date")
        
        // Update user profile
        Task {
            await updateUserProfileConsent(granted: false)
        }
        
        stopTracking()
        clearStoredData()
    }
    
    /// Start tracking live performance (requires consent)
    public func startTracking() {
        guard hasConsent else {
            errorMessage = "Consent required for live performance tracking"
            return
        }
        
        isTracking = true
        errorMessage = nil
        
        // Take initial snapshot
        Task {
            await takePortfolioSnapshot()
        }
        
        // Schedule periodic updates
        schedulePeriodicUpdates()
    }
    
    /// Stop tracking
    public func stopTracking() {
        isTracking = false
        cancellables.removeAll()
    }
    
    /// Manually refresh performance stats
    public func refreshStats() async {
        guard hasConsent && isTracking else { return }
        
        await takePortfolioSnapshot()
        calculatePerformanceStats()
    }
    
    /// Get performance stats for a specific period
    public func getStats(for period: StatsPeriod) -> LivePerformanceStats? {
        guard hasConsent else { return nil }
        return calculateStatsForPeriod(period)
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Load consent status
        hasConsent = UserDefaults.standard.bool(forKey: "live_tracking_consent")
        
        // Auto-start if consent was previously granted
        if hasConsent {
            startTracking()
        }
    }
    
    private func loadStoredData() {
        // Load snapshots
        if let data = UserDefaults.standard.data(forKey: snapshotsStorageKey),
           let snapshots = try? JSONDecoder().decode([PortfolioSnapshot].self, from: data) {
            portfolioSnapshots = snapshots
        }
        
        // Load stats
        if let data = UserDefaults.standard.data(forKey: statsStorageKey),
           let stats = try? JSONDecoder().decode(LivePerformanceStats.self, from: data) {
            currentStats = stats
            lastUpdated = stats.lastUpdated
        }
    }
    
    private func saveStoredData() {
        // Save snapshots (keep last 90 days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recentSnapshots = portfolioSnapshots.filter { $0.timestamp > cutoffDate }
        
        if let data = try? JSONEncoder().encode(recentSnapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsStorageKey)
        }
        
        // Save stats
        if let stats = currentStats,
           let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsStorageKey)
        }
    }
    
    private func clearStoredData() {
        portfolioSnapshots = []
        currentStats = nil
        lastUpdated = nil
        
        UserDefaults.standard.removeObject(forKey: snapshotsStorageKey)
        UserDefaults.standard.removeObject(forKey: statsStorageKey)
    }
    
    private func schedulePeriodicUpdates() {
        // Cancel existing timers
        cancellables.removeAll()
        
        // Schedule periodic snapshot
        Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.takePortfolioSnapshot()
                    self?.calculatePerformanceStats()
                }
            }
            .store(in: &cancellables)
    }
    
    private func takePortfolioSnapshot() async {
        // Get current portfolio value from PortfolioRepository
        // This would integrate with the existing portfolio tracking system
        
        // For now, simulate getting portfolio data
        let totalValue = await getCurrentPortfolioValue()
        let holdings = await getCurrentHoldings()
        
        let snapshot = PortfolioSnapshot(
            timestamp: Date(),
            totalValueUSD: totalValue,
            holdings: holdings
        )
        
        portfolioSnapshots.append(snapshot)
        saveStoredData()
    }
    
    private func getCurrentPortfolioValue() async -> Double {
        // In production, this would fetch from PortfolioRepository
        // For now, return a simulated value
        
        // TODO: Integrate with PortfolioRepository
        // return PortfolioRepository.shared.getTotalValue()
        
        return 10000.0 // Placeholder
    }
    
    private func getCurrentHoldings() async -> [HoldingSnapshot] {
        // In production, fetch from connected exchanges via PortfolioRepository
        
        // TODO: Integrate with PortfolioRepository
        // return PortfolioRepository.shared.holdings.map { ... }
        
        return [] // Placeholder
    }
    
    private func calculatePerformanceStats() {
        guard portfolioSnapshots.count >= 2 else {
            currentStats = LivePerformanceStats.empty
            return
        }
        
        // Calculate stats based on snapshots
        let stats = calculateStatsForPeriod(.allTime)
        currentStats = stats
        lastUpdated = Date()
        
        saveStoredData()
    }
    
    private func calculateStatsForPeriod(_ period: StatsPeriod) -> LivePerformanceStats {
        let cutoffDate: Date
        
        switch period {
        case .day:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        case .week:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .threeMonths:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        case .year:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        case .allTime:
            cutoffDate = Date.distantPast
        }
        
        let periodSnapshots = portfolioSnapshots.filter { $0.timestamp >= cutoffDate }
        
        guard let firstSnapshot = periodSnapshots.first,
              let lastSnapshot = periodSnapshots.last,
              firstSnapshot.totalValueUSD > 0 else {
            return .empty
        }
        
        let pnl = lastSnapshot.totalValueUSD - firstSnapshot.totalValueUSD
        let pnlPercent = (pnl / firstSnapshot.totalValueUSD) * 100
        
        // Calculate max drawdown
        var maxDrawdown: Double = 0
        var peak = firstSnapshot.totalValueUSD
        
        for snapshot in periodSnapshots {
            if snapshot.totalValueUSD > peak {
                peak = snapshot.totalValueUSD
            }
            let drawdown = (peak - snapshot.totalValueUSD) / peak
            maxDrawdown = max(maxDrawdown, drawdown)
        }
        
        return LivePerformanceStats(
            totalPnL: pnl,
            pnlPercent: pnlPercent,
            startingValue: firstSnapshot.totalValueUSD,
            currentValue: lastSnapshot.totalValueUSD,
            maxDrawdown: maxDrawdown * 100,
            peakValue: peak,
            snapshotCount: periodSnapshots.count,
            period: period,
            startDate: firstSnapshot.timestamp,
            endDate: lastSnapshot.timestamp,
            lastUpdated: Date()
        )
    }
    
    private func updateUserProfileConsent(granted: Bool) async {
        // Update the user's social profile with consent status
        guard let profile = SocialService.shared.currentProfile else { return }
        
        var newLeaderboardMode = profile.leaderboardMode
        if !granted {
            // Also update leaderboard mode if they were only competing in live
            if profile.leaderboardMode == .liveOnly {
                newLeaderboardMode = .none
            } else if profile.leaderboardMode == .both {
                newLeaderboardMode = .paperOnly
            }
        }
        
        _ = try? await SocialService.shared.createOrUpdateProfile(
            username: profile.username,
            displayName: profile.displayName,
            avatarPresetId: profile.avatarPresetId,
            bio: profile.bio,
            isPublic: profile.isPublic,
            showOnLeaderboard: profile.showOnLeaderboard,
            leaderboardMode: newLeaderboardMode,
            liveTrackingConsent: granted,
            primaryTradingMode: profile.primaryTradingMode,
            socialLinks: profile.socialLinks
        )
    }
}

// MARK: - Supporting Types

/// Snapshot of portfolio state at a point in time
public struct PortfolioSnapshot: Codable {
    public let timestamp: Date
    public let totalValueUSD: Double
    public let holdings: [HoldingSnapshot]
    
    public init(timestamp: Date, totalValueUSD: Double, holdings: [HoldingSnapshot]) {
        self.timestamp = timestamp
        self.totalValueUSD = totalValueUSD
        self.holdings = holdings
    }
}

/// Snapshot of a single holding
public struct HoldingSnapshot: Codable {
    public let symbol: String
    public let quantity: Double
    public let valueUSD: Double
    public let priceUSD: Double
    
    public init(symbol: String, quantity: Double, valueUSD: Double, priceUSD: Double) {
        self.symbol = symbol
        self.quantity = quantity
        self.valueUSD = valueUSD
        self.priceUSD = priceUSD
    }
}

/// Performance statistics calculated from live portfolio data
public struct LivePerformanceStats: Codable {
    public let totalPnL: Double
    public let pnlPercent: Double
    public let startingValue: Double
    public let currentValue: Double
    public let maxDrawdown: Double
    public let peakValue: Double
    public let snapshotCount: Int
    public let period: StatsPeriod
    public let startDate: Date
    public let endDate: Date
    public let lastUpdated: Date
    
    public static let empty = LivePerformanceStats(
        totalPnL: 0,
        pnlPercent: 0,
        startingValue: 0,
        currentValue: 0,
        maxDrawdown: 0,
        peakValue: 0,
        snapshotCount: 0,
        period: .allTime,
        startDate: Date(),
        endDate: Date(),
        lastUpdated: Date()
    )
    
    /// Convert to PerformanceStats for leaderboard compatibility
    public func toPerformanceStats() -> PerformanceStats {
        return PerformanceStats(
            totalPnL: totalPnL,
            pnlPercent: pnlPercent,
            winRate: 0, // Not tracked from portfolio snapshots
            totalTrades: 0, // Not tracked from portfolio snapshots
            winningTrades: 0,
            losingTrades: 0,
            avgHoldTime: 0,
            avgProfitPerTrade: 0,
            sharpeRatio: nil,
            maxDrawdown: maxDrawdown,
            bestTrade: nil,
            worstTrade: nil,
            period: period,
            lastUpdated: lastUpdated
        )
    }
}

// MARK: - Consent View

/// View for requesting live tracking consent
public struct LiveTrackingConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var tracker = LivePerformanceTracker.shared
    
    let onConsent: (Bool) -> Void
    
    private var isDark: Bool { colorScheme == .dark }
    
    public init(onConsent: @escaping (Bool) -> Void) {
        self.onConsent = onConsent
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                    }
                    .padding(.top, 20)
                    
                    // Title
                    Text("Track Live Performance")
                        .font(.title2.weight(.bold))
                    
                    // Description
                    Text("Allow CryptoSage to track your portfolio performance to compete on the Portfolio leaderboard.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // What we track
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What we track:")
                            .font(.headline)
                        
                        infoRow(icon: "chart.bar.fill", text: "Portfolio value changes over time")
                        infoRow(icon: "arrow.up.arrow.down", text: "Overall profit and loss percentage")
                        infoRow(icon: "chart.line.downtrend.xyaxis", text: "Maximum drawdown")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .padding(.horizontal)
                    
                    // Privacy notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Your Privacy")
                                .font(.headline)
                        }
                        
                        Text("Your actual trade details and holdings are never shared. Only aggregate performance metrics are used for leaderboard rankings. You can revoke consent at any time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            tracker.grantConsent()
                            onConsent(true)
                            dismiss()
                        } label: {
                            Text("Enable Live Tracking")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            onConsent(false)
                            dismiss()
                        } label: {
                            Text("Not Now")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(isDark ? Color.black : Color(UIColor.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
        }
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}
