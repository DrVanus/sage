//
//  OpenOrderRowView.swift
//  CryptoSage
//
//  Reusable row component for displaying an open/pending order.
//  Premium design with swipe-to-cancel gesture.
//

import SwiftUI

// MARK: - Open Order Row View

struct OpenOrderRowView: View {
    let order: OpenOrder
    let onCancel: () -> Void
    let showSymbol: Bool
    let isDemoMode: Bool
    
    @State private var showDetails: Bool = false
    @State private var isCancelling: Bool = false
    @State private var showCancelConfirmation: Bool = false
    
    // Swipe gesture state
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipedOpen: Bool = false
    @GestureState private var isDragging: Bool = false
    
    private let swipeThreshold: CGFloat = 80
    private let cancelButtonWidth: CGFloat = 100
    
    init(order: OpenOrder, showSymbol: Bool = true, isDemoMode: Bool = false, onCancel: @escaping () -> Void) {
        self.order = order
        self.showSymbol = showSymbol
        self.isDemoMode = isDemoMode
        self.onCancel = onCancel
    }
    
    private var isBuy: Bool { order.side == .buy }
    private var sideColor: Color { isBuy ? .green : .red }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Swipe action background (Cancel button) - hidden in demo mode
            if !isDemoMode {
                swipeActionBackground
            }
            
            // Main content with swipe gesture
            VStack(spacing: 0) {
                mainRowContent
                
                if showDetails {
                    expandedDetails
                }
            }
            .background(rowBackground)
            .overlay(rowOverlay)
            .offset(x: isDemoMode ? 0 : swipeOffset)
            .gesture(isDemoMode ? nil : swipeGesture)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: swipeOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .confirmationDialog(
            "Cancel Order",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Order", role: .destructive) {
                performCancel()
            }
            Button("Keep Order", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel this \(order.side == .buy ? "buy" : "sell") order for \(formatQuantity(order.quantity)) \(order.baseAsset) at \(formatPrice(order.price))?")
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                // Snap to open or closed based on threshold
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if abs(swipeOffset) > swipeThreshold {
                        swipeOffset = -cancelButtonWidth
                        isSwipedOpen = true
                    } else {
                        swipeOffset = 0
                        isSwipedOpen = false
                    }
                }
            }
        }
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let translation = value.translation.width
                if isSwipedOpen {
                    // Already open, allow dragging to close
                    swipeOffset = min(0, -cancelButtonWidth + translation)
                } else {
                    // Closed, allow dragging to open (only left swipe)
                    swipeOffset = min(0, translation)
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.width - value.translation.width
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if isSwipedOpen {
                        // If swiping right (closing) with velocity or past threshold
                        if velocity > 100 || swipeOffset > -swipeThreshold {
                            swipeOffset = 0
                            isSwipedOpen = false
                        } else {
                            swipeOffset = -cancelButtonWidth
                        }
                    } else {
                        // If swiping left (opening) with velocity or past threshold
                        if velocity < -100 || swipeOffset < -swipeThreshold {
                            swipeOffset = -cancelButtonWidth
                            isSwipedOpen = true
                        } else {
                            swipeOffset = 0
                        }
                    }
                }
            }
    }
    
    // MARK: - Swipe Action Background
    
    private var swipeActionBackground: some View {
        HStack(spacing: 0) {
            Spacer()
            
            // Cancel action button
            Button {
                // Haptic feedback
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                showCancelConfirmation = true
            } label: {
                VStack(spacing: 6) {
                    if isCancelling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                        Text("Cancel")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(width: cancelButtonWidth)
                .frame(maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.red.opacity(0.9), Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .disabled(isCancelling)
        }
    }
    
    // MARK: - Main Row Content
    
    private var mainRowContent: some View {
        HStack(spacing: 12) {
            // Side indicator
            sideIndicator
            
            // Order info
            VStack(alignment: .leading, spacing: 4) {
                // Symbol and side
                HStack(spacing: 6) {
                    if showSymbol {
                        Text(order.baseAsset)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Text(isBuy ? "BUY" : "SELL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(sideColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sideColor.opacity(0.15))
                        .cornerRadius(4)
                    
                    Text(order.type == .limit ? "LIMIT" : "MARKET")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(3)
                    
                    // Swipe hint when not swiped
                    if !isSwipedOpen {
                        Image(systemName: "chevron.left.2")
                            .font(.system(size: 8))
                            .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                    }
                }
                
                // Price and quantity
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Price")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatPrice(order.price))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Quantity")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatQuantity(order.quantity))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Total")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatUSD(order.totalValue))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Cancel button (always visible, but more prominent when swiped)
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showCancelConfirmation = true
                } label: {
                    if isCancelling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.red.opacity(0.9), Color.red],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                }
                .disabled(isCancelling)
                
                // Expand button
                Button {
                    // Close swipe if open, then toggle details
                    if isSwipedOpen {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            swipeOffset = 0
                            isSwipedOpen = false
                        }
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showDetails.toggle()
                    }
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            // Close swipe if open
            if isSwipedOpen {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    swipeOffset = 0
                    isSwipedOpen = false
                }
            }
        }
    }
    
    // MARK: - Side Indicator
    
    private var sideIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(sideColor.opacity(0.15))
                .frame(width: 40, height: 40)
            
            Image(systemName: isBuy ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(sideColor)
        }
    }
    
    // MARK: - Expanded Details
    
    private var expandedDetails: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            VStack(spacing: 12) {
                // Price distance indicator (simulated market price for demo)
                priceDistanceIndicator
                
                // Fill progress
                if order.filledQuantity > 0 {
                    fillProgressRow
                }
                
                // Details grid
                detailsGrid
                
                // Exchange info
                exchangeRow
            }
            .padding(14)
        }
    }
    
    // MARK: - Price Distance Indicator
    
    /// Shows how far the current market price is from the order price
    private var priceDistanceIndicator: some View {
        // Simulated market price for visualization (in production, fetch from real-time data)
        let simulatedMarketPrice = order.price * (isBuy ? 1.02 : 0.98) // 2% away for demo
        let priceDifference = simulatedMarketPrice - order.price
        let percentDifference = (priceDifference / order.price) * 100
        let isCloseToFill = abs(percentDifference) < 1.0
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    // Pulsing dot for close-to-fill orders
                    if isCloseToFill {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.green.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(1.5)
                            )
                    }
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11))
                        .foregroundColor(BrandColors.goldBase)
                    
                    Text("Price Distance")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Distance badge
                HStack(spacing: 4) {
                    Image(systemName: isBuy ? (priceDifference > 0 ? "arrow.up.right" : "arrow.down.right") : (priceDifference > 0 ? "arrow.up.right" : "arrow.down.right"))
                        .font(.system(size: 9))
                    
                    Text("\(String(format: "%.2f", abs(percentDifference)))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(priceDistanceColor(percentDifference: percentDifference))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(priceDistanceColor(percentDifference: percentDifference).opacity(0.15))
                )
            }
            
            // Visual price range indicator
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    
                    // Order price marker
                    let orderPosition = isBuy ? 0.3 : 0.7
                    Circle()
                        .fill(sideColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .position(x: geo.size.width * orderPosition, y: 3)
                    
                    // Market price indicator
                    let marketPosition = isBuy ? min(0.7, 0.3 + abs(percentDifference) / 10) : max(0.3, 0.7 - abs(percentDifference) / 10)
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(BrandColors.goldBase)
                        .frame(width: 2, height: 12)
                        .position(x: geo.size.width * marketPosition, y: 3)
                    
                    // Connection line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [sideColor.opacity(0.5), BrandColors.goldBase.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: abs(geo.size.width * marketPosition - geo.size.width * orderPosition),
                            height: 2
                        )
                        .position(
                            x: (geo.size.width * orderPosition + geo.size.width * marketPosition) / 2,
                            y: 3
                        )
                }
            }
            .frame(height: 12)
            
            // Labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Order Price")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatPrice(order.price))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(sideColor)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Market Price")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatPrice(simulatedMarketPrice))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrandColors.goldBase)
                }
            }
            
            // Urgency message for close fills
            if isCloseToFill {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("Close to fill!")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isCloseToFill ? Color.green.opacity(0.3) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func priceDistanceColor(percentDifference: Double) -> Color {
        let absPercent = abs(percentDifference)
        if absPercent < 1.0 {
            return .green // Close to fill
        } else if absPercent < 3.0 {
            return BrandColors.goldBase // Moderate distance
        } else if absPercent < 5.0 {
            return .orange // Further away
        } else {
            return .red // Very far
        }
    }
    
    private var fillProgressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fill Progress")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text("\(String(format: "%.1f", order.filledPercent))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(order.filledPercent > 0 ? .green : .gray)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.8), Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (order.filledPercent / 100), height: 4)
                }
            }
            .frame(height: 4)
            
            HStack {
                Text("Filled: \(formatQuantity(order.filledQuantity))")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text("Remaining: \(formatQuantity(order.remainingQuantity))")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }
    
    private var detailsGrid: some View {
        HStack(spacing: 20) {
            detailItem(label: "Order ID", value: String(order.id.prefix(8)) + "...")
            detailItem(label: "Status", value: order.status.rawValue, color: statusColor)
            detailItem(label: "Created", value: formatDate(order.createdAt))
        }
    }
    
    private var exchangeRow: some View {
        HStack {
            Image(systemName: "building.columns")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(order.exchange.displayName)
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textTertiary)
            Spacer()
            Text(order.symbol)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.top, 4)
    }
    
    private var statusColor: Color {
        switch order.status {
        case .new, .pending: return .blue
        case .partiallyFilled: return .orange
        case .filled: return .green
        case .canceled: return .gray
        case .rejected: return .red
        case .expired: return .gray
        }
    }
    
    // MARK: - Background
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
    }
    
    private var rowOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(sideColor.opacity(0.2), lineWidth: 1)
    }
    
    // MARK: - Actions
    
    private func performCancel() {
        isCancelling = true
        Task {
            // Small delay for visual feedback
            try? await Task.sleep(nanoseconds: 100_000_000)
            onCancel()
            isCancelling = false
        }
    }
    
    // MARK: - Helpers
    
    private func detailItem(label: String, value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return "$\(String(format: "%.2f", price))"
        } else if price >= 1 {
            return "$\(String(format: "%.4f", price))"
        } else {
            return "$\(String(format: "%.6f", price))"
        }
    }
    
    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1 {
            return String(format: "%.4f", qty)
        } else {
            return String(format: "%.6f", qty)
        }
    }
    
    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if value >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Compact Order Row

/// A more compact version of the order row for inline displays
struct CompactOpenOrderRowView: View {
    let order: OpenOrder
    let onCancel: () -> Void
    let isDemoMode: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCancelConfirmation: Bool = false
    @State private var isCancelling: Bool = false
    
    private var isBuy: Bool { order.side == .buy }
    private var sideColor: Color { isBuy ? .green : .red }
    
    init(order: OpenOrder, isDemoMode: Bool = false, onCancel: @escaping () -> Void) {
        self.order = order
        self.isDemoMode = isDemoMode
        self.onCancel = onCancel
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Side indicator dot
            Circle()
                .fill(sideColor)
                .frame(width: 6, height: 6)
            
            // Order info
            VStack(alignment: .leading, spacing: 3) {
                // Buy/Sell @ Price
                HStack(spacing: 4) {
                    Text(isBuy ? "Buy" : "Sell")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(sideColor)
                    
                    Text("@")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(formatPrice(order.price))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                // Quantity
                Text("\(formatQuantity(order.quantity)) \(order.baseAsset)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            // Cancel button - hidden in demo mode, uses subtle X icon
            if !isDemoMode {
                Button {
                    showCancelConfirmation = true
                } label: {
                    if isCancelling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .red))
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(DS.Adaptive.overlay(0.08))
                            )
                    }
                }
                .disabled(isCancelling)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .confirmationDialog(
            "Cancel Order",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Order", role: .destructive) {
                isCancelling = true
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    onCancel()
                    isCancelling = false
                }
            }
            Button("Keep Order", role: .cancel) {}
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return "$\(String(format: "%.2f", price))"
        } else if price >= 1 {
            return "$\(String(format: "%.4f", price))"
        } else {
            return "$\(String(format: "%.6f", price))"
        }
    }
    
    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1 {
            return String(format: "%.4f", qty)
        } else {
            return String(format: "%.6f", qty)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OpenOrderRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            OpenOrderRowView(
                order: OpenOrder(
                    id: "12345678",
                    exchange: .binance,
                    symbol: "BTCUSDT",
                    side: .buy,
                    type: .limit,
                    price: 42500.00,
                    quantity: 0.05,
                    filledQuantity: 0.02,
                    status: .partiallyFilled,
                    createdAt: Date().addingTimeInterval(-3600)
                ),
                onCancel: {}
            )
            
            OpenOrderRowView(
                order: OpenOrder(
                    id: "87654321",
                    exchange: .coinbase,
                    symbol: "ETHUSDT",
                    side: .sell,
                    type: .limit,
                    price: 2250.00,
                    quantity: 1.5,
                    filledQuantity: 0,
                    status: .new,
                    createdAt: Date()
                ),
                onCancel: {}
            )
            
            CompactOpenOrderRowView(
                order: OpenOrder(
                    id: "compact123",
                    exchange: .binance,
                    symbol: "BTCUSDT",
                    side: .buy,
                    type: .limit,
                    price: 41000.00,
                    quantity: 0.1,
                    filledQuantity: 0,
                    status: .new,
                    createdAt: Date()
                ),
                onCancel: {}
            )
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
