# Coinbase Trading Integration - Quick Start Guide

## 🚀 **5-Minute Integration Guide**

### **Step 1: Initialize Trading Engine on App Launch**

Add to `CryptoSageAIApp.swift`:

```swift
import SwiftUI

@main
struct CryptoSageAIApp: App {
    @StateObject private var tradingEngine = EnhancedTradingEngine.shared
    @StateObject private var portfolioVM = PortfolioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tradingEngine)
                .environmentObject(portfolioVM)
                .task {
                    // Initialize trading engine
                    if TradingCredentialsManager.shared.hasCredentials(for: .coinbase) {
                        try? await tradingEngine.initialize()
                    }

                    // Start Coinbase auto-sync
                    await portfolioVM.startCoinbaseAutoSync()
                }
        }
    }
}
```

---

### **Step 2: Add Trading Controls to CoinDetailView**

Add to `CoinDetailView.swift`:

```swift
struct CoinDetailView: View {
    let coin: MarketCoin

    // Add trading engine
    @StateObject private var tradingEngine = EnhancedTradingEngine.shared

    // Add sheet state
    @State private var showingOrderEntry = false
    @State private var selectedOrderSide: TradeSide = .buy

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Existing coin details...

                // NEW: Trading Controls
                if tradingEngine.tradingEnabled {
                    tradingControlsSection
                }
            }
        }
        .sheet(isPresented: $showingOrderEntry) {
            CoinbaseOrderEntryView(
                productId: "\(coin.symbol.uppercased())-USD",
                currentPrice: coin.priceUsd ?? 0,
                side: selectedOrderSide
            )
        }
    }

    // NEW: Trading Controls Section
    private var tradingControlsSection: some View {
        VStack(spacing: 16) {
            Text("Quick Trade")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // Buy Button
                Button(action: {
                    showingOrderEntry = true
                    selectedOrderSide = .buy
                }) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Buy")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                // Sell Button
                Button(action: {
                    showingOrderEntry = true
                    selectedOrderSide = .sell
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Sell")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

            // Show balance if available
            if tradingEngine.isConnected {
                let balance = tradingEngine.getBalance(for: coin.symbol)
                if balance > 0 {
                    HStack {
                        Text("Balance:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(balance, specifier: "%.8f") \(coin.symbol)")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}
```

---

### **Step 3: Add Sync Button to Portfolio Section**

Add to `HomeView.swift` or portfolio view:

```swift
struct PortfolioHeaderView: View {
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @State private var isSyncing = false

    var body: some View {
        HStack {
            Text("Portfolio")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            // NEW: Coinbase Sync Button
            Button(action: syncCoinbase) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(isSyncing ? 360 : 0))
                        .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                    Text("Sync")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .disabled(isSyncing)
        }
    }

    private func syncCoinbase() {
        isSyncing = true
        Task {
            await portfolioVM.syncCoinbasePortfolio()
            isSyncing = false
        }
    }
}
```

---

### **Step 4: Add Trading Settings View**

Create `TradingSettingsView.swift`:

```swift
import SwiftUI

struct TradingSettingsView: View {
    @StateObject private var tradingEngine = EnhancedTradingEngine.shared

    var body: some View {
        List {
            // Connection Status
            Section("Connection") {
                HStack {
                    Circle()
                        .fill(tradingEngine.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(tradingEngine.connectionStatus.rawValue)
                    Spacer()
                    if !tradingEngine.isConnected && tradingEngine.tradingEnabled {
                        Button("Connect") {
                            Task {
                                try? await tradingEngine.initialize()
                            }
                        }
                    }
                }
            }

            // Trading Mode
            Section("Trading Mode") {
                Toggle("Paper Trading", isOn: $tradingEngine.isPaperTrading)
                Text("Practice with virtual money before live trading")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Portfolio Sync
            Section("Portfolio Sync") {
                Button("Sync Now") {
                    Task {
                        await tradingEngine.syncPortfolio()
                    }
                }
            }

            // Statistics
            Section("Statistics") {
                let stats = tradingEngine.getTradingStats()

                LabeledContent("Total Trades", value: "\(stats.totalTrades)")
                LabeledContent("Paper Trades", value: "\(stats.paperTrades)")
                LabeledContent("Live Trades", value: "\(stats.liveTrades)")
                LabeledContent("Active Orders", value: "\(stats.activeOrders)")
                LabeledContent("Portfolio Value", value: "$\(stats.portfolioValue, specifier: "%.2f")")
            }
        }
        .navigationTitle("Trading Settings")
    }
}
```

---

## 📱 **Usage Examples**

### **Example 1: Place Market Order**

```swift
let tradingEngine = EnhancedTradingEngine.shared

try await tradingEngine.placeMarketOrder(
    productId: "BTC-USD",
    side: .buy,
    size: 0.001
)
```

### **Example 2: Setup DCA Strategy**

```swift
try await tradingEngine.setupDCAStrategy(
    productId: "BTC-USD",
    amountUSD: 100,
    frequency: .weekly
)
```

### **Example 3: Get Real-Time Prices**

```swift
tradingEngine.priceUpdatePublisher
    .sink { ticker in
        print("Price: \(ticker.product_id) = \(ticker.price)")
    }
    .store(in: &cancellables)
```

### **Example 4: Check Trading Status**

```swift
if tradingEngine.canTrade() {
    // Place order
} else {
    // Show error
}
```

---

## 🧪 **Testing Checklist**

### **Phase 1: Paper Trading (Required)**
- [ ] Add Coinbase API keys in Settings
- [ ] Test connection (should show "Connected")
- [ ] Place paper market order ($10)
- [ ] Place paper limit order
- [ ] Verify orders in PaperTradingManager
- [ ] Test order cancellation
- [ ] Verify portfolio sync
- [ ] Test WebSocket connection

### **Phase 2: Live Trading (⚠️ USE SMALL AMOUNTS)**
- [ ] Disable paper trading mode
- [ ] Place $1 market order
- [ ] Verify order executes on Coinbase
- [ ] Check order in "Open Orders"
- [ ] Test limit order ($1)
- [ ] Cancel limit order
- [ ] Test stop-loss order
- [ ] Monitor for errors

### **Phase 3: DCA Testing**
- [ ] Create DCA strategy ($1 daily)
- [ ] Wait for first execution
- [ ] Verify order placed automatically
- [ ] Check strategy statistics
- [ ] Test manual execution
- [ ] Remove strategy

---

## ⚙️ **Configuration**

### **Enable Live Trading**

In `AppConfig.swift`:

```swift
static let liveTradingEnabled = false  // Set to true for live trading
```

### **Configure WebSocket Products**

```swift
let products = ["BTC-USD", "ETH-USD", "SOL-USD"]
try await EnhancedTradingEngine.shared.subscribeToPriceUpdates(products: products)
```

### **Adjust Sync Frequency**

In `CoinbasePortfolioSyncService.swift`, change:

```swift
try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
```

---

## 🔒 **Safety Features**

1. **Paper Trading Default** - All trades are paper by default
2. **Live Trading Kill Switch** - `AppConfig.liveTradingEnabled` must be true
3. **Risk Acknowledgment** - Required before live trades
4. **Order Validation** - Size limits enforced
5. **Rate Limiting** - WebSocket reconnect with backoff
6. **Error Handling** - Comprehensive error types

---

## 📊 **Monitoring & Debugging**

### **Check Connection Status**

```swift
print("Connected: \(EnhancedTradingEngine.shared.isConnected)")
print("Status: \(EnhancedTradingEngine.shared.connectionStatus)")
```

### **View Trading Stats**

```swift
let stats = EnhancedTradingEngine.shared.getTradingStats()
print("Total trades: \(stats.totalTrades)")
print("Portfolio value: $\(stats.portfolioValue)")
```

### **Check Last Sync Time**

```swift
if let lastSync = await portfolioVM.getLastCoinbaseSyncTime() {
    print("Last sync: \(lastSync)")
}
```

---

## 🎯 **Next Steps**

1. ✅ Add trading controls to CoinDetailView
2. ✅ Initialize trading engine on app launch
3. ✅ Test with paper trading mode
4. ⚠️ Test with small live amounts ($1-5)
5. 📱 Submit to App Store with paper trading default

---

## 📞 **Support**

**Common Issues:**

- "Not connected" → Check API keys in Settings
- "Live trading disabled" → Set `AppConfig.liveTradingEnabled = true`
- "Risk acknowledgment required" → Accept risk disclosure
- WebSocket not connecting → Check network, verify JWT

**Debug Logging:**

```swift
// Enable in AppConfig
static let debugLogging = true
```

---

**Built for CryptoSage iOS** 🚀
