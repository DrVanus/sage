# CLAUDE.md — CryptoSage AI Codebase Guide

## Project Overview
CryptoSage AI is a crypto portfolio/trading iOS app built with SwiftUI + MVVM.
- **462 Swift files, ~380K lines** — large, complex codebase
- **Bundle ID:** com.dee.CryptoSage
- **Firebase project:** cryptosage-ai
- **GitHub:** github.com/DrVanus/sage

## Architecture
- **UI:** SwiftUI with MVVM pattern
- **Backend:** Firebase (45+ Cloud Functions)
- **Key directories:**
  - `CryptoSage/` — all Swift source files (flat structure)
  - `CryptoSageWidget/` — iOS widget extension
  - `CryptoSageTests/` / `CryptoSageUITests/` — tests
  - `firebase/` — Cloud Functions
  - `docs/` — landing page (privacy, terms, support)

## Critical Rules
1. **NEVER make broad changes.** This codebase has delicate performance optimizations.
2. **Homepage is FRAGILE** — LazyVStack with 16+ sections, heavy memory management. Don't restructure.
3. **PremiumGlassCard** is the card wrapper used across sections.
4. **Keep changes surgical** — small, targeted, well-tested.
5. **Don't introduce new architecture patterns** without explicit approval.
6. **Always list files changed and what was modified** when reporting back.

## Key Files (by feature area)
- **Homepage:** `HomePageView.swift`, `HomePageViewModel.swift`
- **Portfolio:** `PortfolioView.swift`, `PortfolioViewModel.swift`
- **Trading:** `TradingView.swift`, `TradingViewModel.swift`, `UnifiedOrderEntryView.swift`
- **Market:** `MarketView.swift`, `MarketViewModel.swift`
- **AI Chat:** `AIChatView.swift`, `AIService.swift`, `AIProviderService.swift`
- **AI Predictions:** `AIPricePredictionService.swift`, `AIPredictionCard.swift`
- **Watchlist:** `WatchlistView.swift`, `WatchlistViewModel.swift`
- **Settings:** `SettingsView.swift`, `APIKeySettingsView.swift`
- **Subscription:** `SubscriptionView.swift`
- **Onboarding:** Look for `Onboarding*.swift`
- **Auth:** `GoogleSignIn*.swift`, Firebase Auth integration
- **Notifications:** `NotificationManager.swift` (if exists)
- **App Entry:** `CryptoSageApp.swift`

## Build
- Open `CryptoSage.xcodeproj` in Xcode
- No CocoaPods/SPM workspace — direct `.xcodeproj`
- Target: iOS 17+

## Git Workflow
- Branch: `main`
- Always `git add -A && git commit -m "descriptive message"` after changes
- Keep commits atomic — one logical change per commit

## Current Launch Blockers (HIGH PRIORITY)
1. Build & test all recent fixes in Xcode
2. Onboarding popup copy rewrite ("Unlock Your Trading Potential")
3. Google Sign-In branding fix (shows project ID instead of "CryptoSage")
4. Push notifications (FCM + APNs)
5. App Store listing prep (screenshots, ASO, metadata)
6. Firebase App Check (secure Cloud Functions)

## Style Guide
- Dark theme, green accent (#00FF7F-ish)
- SF Pro fonts, SF Symbols for icons
- Glass/premium card aesthetic (PremiumGlassCard)
- Consistent spacing: 16pt padding, 12pt inter-item
