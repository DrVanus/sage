//
//  ExchangePickerView.swift
//  CryptoSage
//
//  Exchange selection picker for trading.
//

import SwiftUI

// MARK: - Styled Exchange Logos

/// A styled logo for exchanges - creates recognizable brand-like appearance without external assets
struct ExchangeLogo: View {
    let exchange: TradingExchange
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Outer glow ring matching brand color
            Circle()
                .fill(shadowColor.opacity(0.25))
                .frame(width: size + 6, height: size + 6)
            
            // Background circle with gradient
            Circle()
                .fill(backgroundGradient)
            
            // Inner circle for depth - enhanced 3D effect
            Circle()
                .fill(innerGradient)
                .padding(size * 0.06)
            
            // Highlight arc for 3D depth
            Circle()
                .trim(from: 0.0, to: 0.35)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size * 0.04
                )
                .rotationEffect(.degrees(-45))
                .padding(size * 0.04)
            
            // Letter mark or symbol
            logoContent
        }
        .frame(width: size, height: size)
    }
    
    private var backgroundGradient: LinearGradient {
        switch exchange {
        case .binance, .binanceUS:
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.76, blue: 0.15), Color(red: 0.85, green: 0.65, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .coinbase:
            return LinearGradient(
                colors: [Color(red: 0.25, green: 0.52, blue: 0.96), Color(red: 0.15, green: 0.38, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .kraken:
            return LinearGradient(
                colors: [Color(red: 0.55, green: 0.30, blue: 0.85), Color(red: 0.40, green: 0.20, blue: 0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .kucoin:
            return LinearGradient(
                colors: [Color(red: 0.20, green: 0.75, blue: 0.55), Color(red: 0.10, green: 0.60, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .bybit:
            return LinearGradient(
                colors: [Color(red: 0.96, green: 0.65, blue: 0.14), Color(red: 0.85, green: 0.55, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .okx:
            return LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.10), Color(red: 0.05, green: 0.05, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var innerGradient: LinearGradient {
        switch exchange {
        case .binance, .binanceUS:
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.82, blue: 0.20), Color(red: 0.90, green: 0.70, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .coinbase:
            return LinearGradient(
                colors: [Color(red: 0.30, green: 0.55, blue: 0.98), Color(red: 0.20, green: 0.42, blue: 0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .kraken:
            return LinearGradient(
                colors: [Color(red: 0.60, green: 0.35, blue: 0.90), Color(red: 0.45, green: 0.25, blue: 0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .kucoin:
            return LinearGradient(
                colors: [Color(red: 0.25, green: 0.80, blue: 0.60), Color(red: 0.15, green: 0.65, blue: 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .bybit:
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.70, blue: 0.18), Color(red: 0.90, green: 0.60, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .okx:
            return LinearGradient(
                colors: [Color(red: 0.15, green: 0.15, blue: 0.15), Color(red: 0.08, green: 0.08, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var shadowColor: Color {
        switch exchange {
        case .binance, .binanceUS: return .yellow
        case .coinbase: return .blue
        case .kraken: return .purple
        case .kucoin: return .green
        case .bybit: return .orange
        case .okx: return .gray
        }
    }
    
    @ViewBuilder
    private var logoContent: some View {
        switch exchange {
        case .binance, .binanceUS:
            // Binance-style "B" with diamond shape
            BinanceLogoMark(size: size)
        case .coinbase:
            // Coinbase-style "$" or "C"
            CoinbaseLogoMark(size: size)
        case .kraken:
            // Kraken-style "K" logo
            KrakenLogoMark(size: size)
        case .kucoin:
            // KuCoin-style "K" logo
            KuCoinLogoMark(size: size)
        case .bybit:
            // Bybit-style logo
            BybitLogoMark(size: size)
        case .okx:
            // OKX-style "O" logo
            OKXLogoMark(size: size)
        }
    }
}

/// Binance-style logo mark - simplified diamond/rhombus B
private struct BinanceLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Text("B")
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Coinbase-style logo mark - stylized dollar sign
private struct CoinbaseLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Text("$")
            .font(.system(size: size * 0.52, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Kraken-style logo mark
private struct KrakenLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Image(systemName: "waveform.circle.fill")
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// KuCoin-style logo mark
private struct KuCoinLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Text("K")
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Bybit-style logo mark
private struct BybitLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Text("B")
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

private struct OKXLogoMark: View {
    let size: CGFloat
    
    var body: some View {
        Text("O")
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.80)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Compact exchange logo for use in buttons and tight spaces
struct ExchangeLogoCompact: View {
    let exchange: TradingExchange
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Outer glow ring for visibility on dark backgrounds
            Circle()
                .fill(glowColor.opacity(0.3))
                .frame(width: size + 2, height: size + 2)
            
            // Main background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [backgroundColorLight, backgroundColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Inner highlight for depth
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            Text(letterMark)
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundColor(letterColor)
        }
        .frame(width: size, height: size)
    }
    
    private var backgroundColor: Color {
        switch exchange {
        case .binance, .binanceUS: return Color(red: 0.95, green: 0.76, blue: 0.15)
        case .coinbase: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .kraken: return Color(red: 0.55, green: 0.30, blue: 0.85)
        case .kucoin: return Color(red: 0.20, green: 0.75, blue: 0.55)
        case .bybit: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .okx: return Color(red: 0.10, green: 0.10, blue: 0.10)
        }
    }
    
    private var backgroundColorLight: Color {
        switch exchange {
        case .binance, .binanceUS: return Color(red: 1.0, green: 0.85, blue: 0.35)
        case .coinbase: return Color(red: 0.35, green: 0.58, blue: 0.98)
        case .kraken: return Color(red: 0.65, green: 0.40, blue: 0.92)
        case .kucoin: return Color(red: 0.30, green: 0.85, blue: 0.65)
        case .bybit: return Color(red: 1.0, green: 0.75, blue: 0.30)
        case .okx: return Color(red: 0.20, green: 0.20, blue: 0.20)
        }
    }
    
    private var glowColor: Color {
        switch exchange {
        case .binance, .binanceUS: return Color(red: 0.98, green: 0.82, blue: 0.20)
        case .coinbase: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .kraken: return Color(red: 0.60, green: 0.35, blue: 0.90)
        case .kucoin: return Color(red: 0.25, green: 0.80, blue: 0.60)
        case .bybit: return Color(red: 0.98, green: 0.70, blue: 0.18)
        case .okx: return Color(red: 0.30, green: 0.30, blue: 0.30)
        }
    }
    
    private var letterMark: String {
        switch exchange {
        case .binance, .binanceUS: return "B"
        case .coinbase: return "$"
        case .kraken: return "K"
        case .kucoin: return "K"
        case .bybit: return "B"
        case .okx: return "O"
        }
    }
    
    private var letterColor: Color {
        switch exchange {
        case .binance, .binanceUS, .bybit: return .black.opacity(0.9)
        case .coinbase, .kraken, .kucoin: return .white
        case .okx: return .white
        }
    }
}

// MARK: - Exchange Picker Button

/// A button that shows the selected exchange and presents a picker
struct ExchangePickerButton: View {
    @Binding var selectedExchange: TradingExchange?
    var connectedExchanges: [TradingExchange]
    @State private var showPicker = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showPicker = true
        } label: {
            HStack(spacing: 5) {
                // Exchange icon - increased size for better visibility
                exchangeIcon
                    .frame(width: 16, height: 16)
                
                // Exchange name - compact text
                Text(displayText)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                
                // Dropdown chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(hasExchange ? (colorScheme == .dark ? .white : .black) : .orange)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(hasExchange
                          ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                          : Color.orange.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(hasExchange ? Color.clear : Color.orange.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .sheet(isPresented: $showPicker) {
            ExchangePickerSheet(
                selectedExchange: $selectedExchange,
                connectedExchanges: connectedExchanges,
                isPresented: $showPicker
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    
    /// Compact display text for the button
    private var displayText: String {
        if let exchange = selectedExchange {
            // Shorten exchange names for compact display
            switch exchange {
            case .binance: return "Binance"
            case .binanceUS: return "Binance US"
            case .coinbase: return "Coinbase"
            case .kraken: return "Kraken"
            case .kucoin: return "KuCoin"
            case .bybit: return "Bybit"
            case .okx: return "OKX"
            }
        }
        return "Exchange" // Shorter than "Select Exchange"
    }
    
    private var hasExchange: Bool {
        selectedExchange != nil
    }
    
    @ViewBuilder
    private var exchangeIcon: some View {
        if let exchange = selectedExchange {
            exchangeIconImage(for: exchange)
        } else {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 11))
        }
    }
    
    @ViewBuilder
    private func exchangeIconImage(for exchange: TradingExchange) -> some View {
        // Use ExchangeLogoView which loads actual brand logos
        ExchangeLogoView(name: exchange.displayName, size: 16)
    }
}

// MARK: - Exchange Picker Sheet

struct ExchangePickerSheet: View {
    @Binding var selectedExchange: TradingExchange?
    let connectedExchanges: [TradingExchange]
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var sheetBackground: Color {
        colorScheme == .dark ? Color.black : Color(UIColor.systemBackground)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if connectedExchanges.isEmpty {
                    noExchangesView
                } else {
                    exchangeList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sheetBackground)
            .navigationTitle("Select Exchange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CSNavButton(icon: "xmark", action: { isPresented = false }, accessibilityText: "Close", compact: true)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
        .presentationBackground(sheetBackground)
    }
    
    // MARK: - No Exchanges View
    
    private var noExchangesView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 32))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text("Track Your Portfolio")
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
            
            Text("Connect an exchange to sync your holdings and track your portfolio.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            NavigationLink {
                PortfolioPaymentMethodsView()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Connect Exchange")
                }
                .font(.headline)
                .foregroundColor(.black)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldBase, BrandColors.goldLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(sheetBackground)
    }
    
    // MARK: - Exchange List
    
    private var exchangeList: some View {
        List {
            Section {
                ForEach(connectedExchanges) { exchange in
                    ExchangeRow(
                        exchange: exchange,
                        isSelected: selectedExchange == exchange,
                        onSelect: {
                            selectedExchange = exchange
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            isPresented = false
                        }
                    )
                }
            } header: {
                Text("Connected Exchanges")
            } footer: {
                Text("Select an exchange to trade on. Your orders will be executed on the selected exchange.")
            }
            
            Section {
                NavigationLink {
                    PortfolioPaymentMethodsView()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                        Text("Connect Another Exchange")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Exchange Row

private struct ExchangeRow: View {
    let exchange: TradingExchange
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Exchange logo - using ExchangeLogoView which loads actual brand logos
                ExchangeLogoView(name: exchange.displayName, size: 44)
                
                // Exchange info
                VStack(alignment: .leading, spacing: 2) {
                    Text(exchange.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(exchangeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var brandColor: Color {
        ExchangeLogos.brandColor(for: exchange.displayName)
    }
    
    private var exchangeDescription: String {
        switch exchange {
        case .binance: return "Global • USDT pairs"
        case .binanceUS: return "US • USDT pairs"
        case .coinbase: return "US/EU • USD pairs"
        case .kraken: return "Global • USD/EUR pairs"
        case .kucoin: return "Global • USDT pairs"
        case .bybit: return "Global • USDT pairs"
        case .okx: return "Global • USDT pairs"
        }
    }
}

// MARK: - Preview

#Preview("Exchange Picker Button") {
    VStack(spacing: 20) {
        ExchangePickerButton(
            selectedExchange: .constant(.binance),
            connectedExchanges: [.binance, .coinbase]
        )
        
        ExchangePickerButton(
            selectedExchange: .constant(nil),
            connectedExchanges: []
        )
    }
    .padding()
    .background(Color.black)
}

#Preview("Exchange Picker Sheet") {
    ExchangePickerSheet(
        selectedExchange: .constant(.binance),
        connectedExchanges: [.binance, .binanceUS, .coinbase],
        isPresented: .constant(true)
    )
}
