//
//  CoinbaseDCAService.swift
//  CryptoSage
//
//  DCA (Dollar-Cost Averaging) automation service
//  Manages recurring buy strategies with intelligent execution
//

import Foundation
import Combine

/// DCA (Dollar-Cost Averaging) configuration
public struct DCAStrategy: Codable, Identifiable {
    public let id: UUID
    public let productId: String
    public let amountUSD: Double
    public let frequency: DCAFrequency
    public var isActive: Bool
    public var nextExecutionDate: Date
    public let createdAt: Date
    public var lastExecutionDate: Date?
    public var totalInvested: Double
    public var totalExecutions: Int

    public enum DCAFrequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case biweekly = "Biweekly"
        case monthly = "Monthly"

        var interval: TimeInterval {
            switch self {
            case .daily: return 86400 // 1 day
            case .weekly: return 604800 // 7 days
            case .biweekly: return 1209600 // 14 days
            case .monthly: return 2592000 // 30 days
            }
        }
    }

    public init(
        id: UUID = UUID(),
        productId: String,
        amountUSD: Double,
        frequency: DCAFrequency,
        isActive: Bool = true,
        nextExecutionDate: Date = Date(),
        createdAt: Date = Date(),
        lastExecutionDate: Date? = nil,
        totalInvested: Double = 0,
        totalExecutions: Int = 0
    ) {
        self.id = id
        self.productId = productId
        self.amountUSD = amountUSD
        self.frequency = frequency
        self.isActive = isActive
        self.nextExecutionDate = nextExecutionDate
        self.createdAt = createdAt
        self.lastExecutionDate = lastExecutionDate
        self.totalInvested = totalInvested
        self.totalExecutions = totalExecutions
    }
}

/// Service for managing DCA strategies
public actor CoinbaseDCAService {
    public static let shared = CoinbaseDCAService()
    private init() {
        Task {
            await loadStrategies()
            await startExecutionTimer()
        }
    }

    private var activeStrategies: [DCAStrategy] = []
    private var executionTimer: Task<Void, Never>?
    private let coinbaseService = CoinbaseAdvancedTradeService.shared

    // Storage key
    private let storageKey = "coinbaseDCAStrategies"

    // Publishers
    private let strategiesSubject = CurrentValueSubject<[DCAStrategy], Never>([])
    public var strategiesPublisher: AnyPublisher<[DCAStrategy], Never> {
        strategiesSubject.eraseToAnyPublisher()
    }

    // MARK: - Strategy Management

    /// Add a new DCA strategy
    public func addStrategy(_ strategy: DCAStrategy) async throws {
        activeStrategies.append(strategy)
        await saveStrategies()
        strategiesSubject.send(activeStrategies)
        await startExecutionTimer()
        #if DEBUG
        print("✅ DCA strategy added: \(strategy.productId) - $\(strategy.amountUSD) \(strategy.frequency.rawValue)")
        #endif
    }

    /// Remove a DCA strategy
    public func removeStrategy(id: UUID) async throws {
        activeStrategies.removeAll { $0.id == id }
        await saveStrategies()
        strategiesSubject.send(activeStrategies)
        #if DEBUG
        print("🗑️ DCA strategy removed")
        #endif
    }

    /// Update strategy (activate/deactivate)
    public func updateStrategy(_ updatedStrategy: DCAStrategy) async {
        if let index = activeStrategies.firstIndex(where: { $0.id == updatedStrategy.id }) {
            activeStrategies[index] = updatedStrategy
            await saveStrategies()
            strategiesSubject.send(activeStrategies)
        }
    }

    /// Get all strategies
    public func getAllStrategies() -> [DCAStrategy] {
        activeStrategies
    }

    // MARK: - Execution

    /// Execute pending DCA orders
    public func executePendingOrders() async {
        let now = Date()

        for var strategy in activeStrategies where strategy.isActive {
            if strategy.nextExecutionDate <= now {
                do {
                    // Execute market buy order
                    #if DEBUG
                    print("🔄 Executing DCA order: \(strategy.productId) - $\(strategy.amountUSD)")
                    #endif

                    let response = try await coinbaseService.placeMarketOrder(
                        productId: strategy.productId,
                        side: "BUY",
                        size: strategy.amountUSD,
                        isSizeInQuote: true
                    )

                    if response.success {
                        #if DEBUG
                        print("✅ DCA order executed: \(strategy.productId) - $\(strategy.amountUSD)")
                        #endif

                        // Update strategy stats
                        strategy.lastExecutionDate = now
                        strategy.totalInvested += strategy.amountUSD
                        strategy.totalExecutions += 1
                        strategy.nextExecutionDate = calculateNextExecution(
                            from: now,
                            frequency: strategy.frequency
                        )

                        // Save updated strategy
                        if let index = activeStrategies.firstIndex(where: { $0.id == strategy.id }) {
                            activeStrategies[index] = strategy
                        }

                        // Send notification
                        await sendExecutionNotification(strategy: strategy)
                    } else {
                        #if DEBUG
                        print("❌ DCA order failed: \(response.errorResponse?.message ?? "Unknown error")")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("❌ DCA order error: \(error.localizedDescription)")
                    #endif

                    // Retry on next check (don't update nextExecutionDate)
                    // This allows retry on next execution cycle
                }
            }
        }

        await saveStrategies()
        strategiesSubject.send(activeStrategies)
    }

    /// Manually execute a strategy immediately
    public func executeStrategyNow(_ strategyId: UUID) async throws {
        guard let strategy = activeStrategies.first(where: { $0.id == strategyId }) else {
            throw DCAError.strategyNotFound
        }

        guard strategy.isActive else {
            throw DCAError.strategyInactive
        }

        let response = try await coinbaseService.placeMarketOrder(
            productId: strategy.productId,
            side: "BUY",
            size: strategy.amountUSD,
            isSizeInQuote: true
        )

        if !response.success {
            throw DCAError.executionFailed(response.errorResponse?.message ?? "Unknown error")
        }

        #if DEBUG
        print("✅ Manual DCA execution successful")
        #endif
    }

    // MARK: - Helpers

    private func calculateNextExecution(from date: Date, frequency: DCAStrategy.DCAFrequency) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }

    private func startExecutionTimer() async {
        // Cancel existing timer
        executionTimer?.cancel()

        // Start new timer (check every hour)
        executionTimer = Task {
            while !Task.isCancelled {
                await executePendingOrders()
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
            }
        }

        #if DEBUG
        print("⏰ DCA execution timer started (checking every hour)")
        #endif
    }

    private func saveStrategies() async {
        do {
            let encoded = try JSONEncoder().encode(activeStrategies)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } catch {
            #if DEBUG
            print("❌ Failed to save DCA strategies: \(error)")
            #endif
        }
    }

    private func loadStrategies() async {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DCAStrategy].self, from: data) {
            activeStrategies = decoded
            strategiesSubject.send(activeStrategies)
            #if DEBUG
            print("✅ Loaded \(activeStrategies.count) DCA strategies")
            #endif
        }
    }

    private func sendExecutionNotification(strategy: DCAStrategy) async {
        // Post notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("DCAOrderExecuted"),
                object: nil,
                userInfo: ["strategy": strategy]
            )
        }
    }
}

// MARK: - Errors

public enum DCAError: LocalizedError {
    case strategyNotFound
    case strategyInactive
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .strategyNotFound:
            return "DCA strategy not found"
        case .strategyInactive:
            return "DCA strategy is currently inactive"
        case .executionFailed(let message):
            return "DCA execution failed: \(message)"
        }
    }
}
