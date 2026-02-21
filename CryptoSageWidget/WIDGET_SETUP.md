# CryptoSage Widget Setup Guide

This directory contains the source code for iOS Home Screen and Lock Screen widgets for CryptoSage. To enable widgets in your app, follow these steps:

## Setup Instructions

### 1. Add Widget Extension Target in Xcode

1. Open `CryptoSage.xcodeproj` in Xcode
2. Go to **File → New → Target**
3. Select **Widget Extension**
4. Configure:
   - Product Name: `CryptoSageWidget`
   - Include Configuration App Intent: **No** (we use StaticConfiguration)
5. Click **Finish**
6. When prompted about scheme activation, click **Activate**

### 2. Add Source Files

1. Delete the auto-generated template files in the new `CryptoSageWidget` folder
2. Add the following files from this directory to the target:
   - `CryptoSageWidget.swift`
   - `SharedDataProvider.swift`
   - `PriceTickerWidget.swift`
   - `PortfolioWidget.swift`
   - `FearGreedWidget.swift`

### 3. Configure App Groups

App Groups enable data sharing between the main app and the widget.

1. Select the main **CryptoSage** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** and add **App Groups**
4. Add group: `group.com.cryptosage.shared`

5. Repeat for the **CryptoSageWidget** target:
   - Select the widget target
   - **Signing & Capabilities → App Groups**
   - Add the same group: `group.com.cryptosage.shared`

### 4. Update Main App to Share Data

Add this code to sync data from the main app to the widget. In `CryptoSageAIApp.swift` or `PortfolioViewModel.swift`:

```swift
import WidgetKit

// Call this whenever portfolio data updates
func updateWidgetData() {
    let provider = WidgetDataProvider.shared
    
    // Update portfolio data
    let portfolioData = WidgetPortfolioData(
        totalValue: portfolioViewModel.totalValue,
        change24h: portfolioViewModel.change24h,
        changePercent: portfolioViewModel.changePercent,
        topHoldings: portfolioViewModel.holdings.prefix(5).map { holding in
            WidgetHolding(
                id: holding.coinID,
                symbol: holding.symbol.uppercased(),
                value: holding.currentValue,
                percentage: holding.portfolioPercent
            )
        },
        lastUpdate: Date()
    )
    provider.savePortfolioData(portfolioData)
    
    // Update watchlist data
    let watchlistData = watchlistCoins.map { coin in
        WidgetCoinData(
            id: coin.id,
            symbol: coin.symbol.uppercased(),
            name: coin.name,
            price: coin.currentPrice,
            change24h: coin.priceChangePercent24h,
            imageURL: coin.image
        )
    }
    provider.saveWatchlistData(watchlistData)
    
    // Refresh widgets
    WidgetCenter.shared.reloadAllTimelines()
}
```

### 5. Build and Test

1. Build the main app first
2. Build the widget extension
3. Run on a device or simulator
4. Long-press on the Home Screen → Tap **+** → Search for "CryptoSage"
5. Add the desired widget

## Available Widgets

### Price Ticker (Small/Medium)
- Shows single coin price and 24h change
- Rotates through watchlist coins
- Lock Screen support (Circular, Rectangular)

### Portfolio (Small/Medium/Large)
- Total portfolio value
- 24h change
- Top holdings breakdown
- Visual allocation bars (Large)

### Fear & Greed (Small)
- Current Fear & Greed Index value
- Sentiment classification
- Visual gauge
- Lock Screen support

## Troubleshooting

### Widget shows placeholder data
- Ensure App Groups are configured correctly
- Check that the main app has called `updateWidgetData()` at least once

### Widget not appearing in widget picker
- Clean build folder (Cmd + Shift + K)
- Delete app from simulator/device and reinstall
- Restart simulator

### Data not syncing
- Verify both targets have the same App Group identifier
- Check that `UserDefaults(suiteName:)` is using the correct identifier

## Notes

- Widgets refresh every 15 minutes minimum (iOS limitation)
- Lock Screen widgets have limited interactivity
- Widget data should be kept lightweight for performance
