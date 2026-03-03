// MARK: - TradeView.swift
import SwiftUI
import Combine
import QuartzCore

fileprivate enum QuotePreferenceMode: String, CaseIterable { case auto, usd, usdt }

enum ChartSource { case sage, trading }
enum DepthMode: String, CaseIterable { case qty, notional, cumulative }  // Qty first (standard)

/// Price level grouping for order book aggregation
enum PriceGrouping: String, CaseIterable, Identifiable {
    case p001 = "0.01"
    case p01 = "0.1"
    case p1 = "1"
    case p10 = "10"
    case p100 = "100"
    
    var id: String { rawValue }
    
    var tickSize: Double {
        switch self {
        case .p001: return 0.01
        case .p01: return 0.10
        case .p1: return 1.00
        case .p10: return 10.00
        case .p100: return 100.00
        }
    }
    
    var displayLabel: String {
        switch self {
        case .p001: return "0.01"
        case .p01: return "0.1"
        case .p1: return "1"
        case .p10: return "10"
        case .p100: return "100"
        }
    }

    static func recommended(for price: Double) -> PriceGrouping {
        guard price > 0, price.isFinite else { return .p1 }
        if price < 2 { return .p001 }       // XRP/DOGE style prices
        if price < 50 { return .p01 }       // Single/double-digit assets
        if price < 5000 { return .p1 }      // SOL/ETH + most majors
        if price < 500000 { return .p10 }   // BTC/high-priced assets (keep depth visible)
        return .p100                        // Ultra-high priced assets only
    }
}

// MARK: - Cached USD formatters to avoid per-row NumberFormatter costs
enum USDFormatters {
    static let small: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 8
        return f
    }()
    static let normal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}

func formatUSD(_ value: Double) -> String {
    guard value > 0 else { return "$0.00" }
    let formatter = (value < 1.0) ? USDFormatters.small : USDFormatters.normal
    return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
}

// MARK: - TradingPriceDisplay
/// A price display that smoothly animates between value changes using spring animation.
/// Prevents jarring jumps by interpolating the displayed value toward the target.
private struct TradingPriceDisplay: View {
    let targetPrice: Double
    let isDark: Bool
    
    @State private var displayedPrice: Double = 0
    @State private var lastTargetPrice: Double = 0
    @State private var priceDirection: Int = 0 // -1 down, 0 neutral, 1 up
    @State private var highlightOpacity: Double = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var appearTime: Date = .distantPast
    @State private var lastAnimationAt: Date = .distantPast
    @State private var directionStreak: Int = 0 // Track consecutive same-direction changes
    @State private var lastDirection: Int = 0 // Previous direction for streak tracking
    
    // Rate limiting: minimum time between visual updates
    private let minUpdateInterval: TimeInterval = 0.35
    // Cold start grace period to avoid animation on initial load
    private let coldStartDuration: TimeInterval = 0.6
    
    var body: some View {
        // Adaptive styling for light/dark mode
        let chipBG = isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.95)
        let chipStroke: Color = isDark ? DS.Neutral.stroke : Color.black.opacity(0.06)
        
        Text(displayedPrice > 0 ? formatUSD(displayedPrice) : "—")
            .font(DS.Fonts.priceXL)
            .monospacedDigit()
            // Dark mode: gold gradient text; Light mode: clean dark text
            .foregroundStyle(displayedPrice > 0
                ? AnyShapeStyle(isDark ? AdaptiveGradients.chipGold(isDark: true) : LinearGradient(colors: [Color(white: 0.08), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.gray))
            .scaleEffect(scaleEffect)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipBG)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(chipStroke, lineWidth: isDark ? 1 : 0.5)
                    )
            )
            .padding(.vertical, 5)  // Balanced: enough for shadow, but tighter overall
            .padding(.horizontal, 10)
            .onAppear {
                DispatchQueue.main.async {
                    appearTime = Date()
                    if targetPrice > 0 {
                        displayedPrice = targetPrice
                        lastTargetPrice = targetPrice
                    }
                }
            }
            .onChange(of: targetPrice) { _, newTarget in
                // STARTUP FIX v25: Allow significant price corrections during startup
                let significantCorrection = lastTargetPrice > 0 ? abs(newTarget - lastTargetPrice) / lastTargetPrice > 0.01 : newTarget > 0
                if isInGlobalStartupPhase() && !significantCorrection { return }
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    guard newTarget > 0 else { return }
                    
                    let now = Date()
                    let isColdStart = now.timeIntervalSince(appearTime) < coldStartDuration
                    let tooSoon = now.timeIntervalSince(lastAnimationAt) < minUpdateInterval
                    
                    // Calculate the change magnitude
                    let oldPrice = lastTargetPrice > 0 ? lastTargetPrice : displayedPrice
                    let delta = newTarget - oldPrice
                    let pctChange = abs(delta) / max(oldPrice, 1e-9)
                    
                    // Threshold: only animate if change is significant enough to be visible
                    // For high-value coins like BTC, we need at least ~0.01% change to show
                    let shouldAnimate = !isColdStart && !tooSoon && pctChange > 0.0001
                    
                    if shouldAnimate {
                        // Determine direction
                        let newDirection = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
                        
                        // Track momentum: consecutive same-direction changes increase streak
                        let newStreak: Int
                        if newDirection == lastDirection && newDirection != 0 {
                            newStreak = min(directionStreak + 1, 5) // Cap at 5 for max effect
                        } else {
                            newStreak = 1
                        }
                        
                        // Haptic feedback for significant price movements (>0.5%)
                        #if os(iOS)
                        if pctChange > 0.005 {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        #endif
                        
                        // Quick spring animation for snappy, professional feel
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            displayedPrice = newTarget
                            priceDirection = newDirection
                            directionStreak = newStreak
                            scaleEffect = newDirection != 0 ? 1.015 : 1.0
                            highlightOpacity = 1.0
                        }
                        
                        lastAnimationAt = now
                        lastDirection = newDirection
                        
                        // Quick fade out for snappier transitions
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                highlightOpacity = 0
                                scaleEffect = 1.0
                                priceDirection = 0
                            }
                        }
                    } else {
                        // Update silently without animation
                        displayedPrice = newTarget
                    }
                    
                    lastTargetPrice = newTarget
                }
            }
    }
}

// MARK: – SingleTrackSlider
private struct SingleTrackSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0
    var trackHeight: CGFloat = 4
    var knobSize: CGFloat = 28
    var activeColor: Color = BrandColors.goldBase
    var inactiveColor: Color = DS.Neutral.bg(0.15)
    var snapMarks: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var snapThreshold: Double = 0.025
    var onChanged: (Double) -> Void = { _ in }
    
    // Derived knob dimensions for a pill-shaped handle (wider than tall)
    private var knobWidth: CGFloat { max(28, knobSize * 1.6) }
    private var knobHeight: CGFloat { max(trackHeight + 10, knobSize * 0.6) }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let progress = CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
            let xPos = progress * width

            ZStack(alignment: .leading) {
                // Inactive single track
                Capsule()
                    .fill(inactiveColor)
                    .frame(height: trackHeight)
                // Active filled portion
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [activeColor.opacity(colorScheme == .dark ? 0.92 : 0.86), activeColor.opacity(colorScheme == .dark ? 0.72 : 0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: xPos, height: trackHeight)
                // Knob (pill)
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: knobWidth, height: knobHeight)
                    .offset(x: max(0, min(width - knobWidth, xPos - knobWidth/2)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = max(0, min(width, g.location.x))
                        var newVal = Double(x / width) * (range.upperBound - range.lowerBound) + range.lowerBound
                        if step > 0 {
                            let inv = 1.0 / step
                            newVal = (newVal * inv).rounded() / inv
                        }
                        let clamped = min(max(newVal, range.lowerBound), range.upperBound)
                        if abs(clamped - value) > 0.001 {
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.85, blendDuration: 0.1)) {
                                value = clamped
                            }
                            // Gentle haptic on hitting quarter marks when using stepped mode
                            if step > 0 {
                                let pct = clamped - range.lowerBound
                                let norm = pct / (range.upperBound - range.lowerBound)
                                let marks: [Double] = [0, 0.25, 0.5, 0.75, 1]
                                if marks.contains(where: { abs($0 - norm) < (step * 1.5) }) {
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                }
                            }
                        }
                        Task { @MainActor in onChanged(value) }
                    }
                    .onEnded { g in
                        let width = max(1, geo.size.width)
                        let x = max(0, min(width, g.location.x))
                        let rawVal = Double(x / width) * (range.upperBound - range.lowerBound) + range.lowerBound
                        let clamped = min(max(rawVal, range.lowerBound), range.upperBound)
                        let norm = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
                        // VELOCITY GATE: Only snap when the drag is ending slowly.
                        // If the user is swiping fast through a snap zone, don't lock onto it.
                        let dragVelocity = abs(g.predictedEndLocation.x - g.location.x)
                        let isSlowEnough = dragVelocity < 20  // points of predicted overshoot
                        // Find nearest snap mark (only if drag is slow enough)
                        if isSlowEnough, let nearest = snapMarks.min(by: { abs($0 - norm) < abs($1 - norm) }), abs(nearest - norm) <= snapThreshold {
                            let snapped = range.lowerBound + nearest * (range.upperBound - range.lowerBound)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                value = snapped
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            Task { @MainActor in onChanged(value) }
                        }
                    }
            )
        }
        .frame(height: max(knobHeight, trackHeight))
    }
}

// MARK: - OrderBookSkeleton (lightweight placeholder)
private struct OrderBookSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    var rows: Int = 10
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                        .frame(width: 120, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                        .frame(width: 80, height: 12)
                }
                .frame(height: DS.Spacing.orderBookRowHeight)
            }
        }
    }
}

// MARK: – TradeFormView
struct TradeFormView: View {
    @Binding var quantity: String
    @Binding var limitPrice: String
    @Binding var stopPrice: String
    @Binding var selectedSide: TradeSide
    @Binding var orderType: OrderType
    @Binding var sliderValue: Double

    @ObservedObject var vm: TradeViewModel
    @ObservedObject var priceVM: PriceViewModel
    let symbol: String
    let quoteSymbol: String
    let horizontalSizeClass: UserInterfaceSizeClass?
    // Focus binding passed from parent TradeView for proper keyboard toolbar support
    var quantityFieldFocused: FocusState<Bool>.Binding
    // Keyboard visibility passed from parent to hide submit button when keyboard is shown
    let isKeyboardVisible: Bool

    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Risk Acknowledgment State
    @State private var showingToSAcceptance: Bool = false
    @State private var showingRiskAcknowledgment: Bool = false
    @State private var showingPreTradeConfirmation: Bool = false
    @State private var showingPaperTradeConfirmation: Bool = false
    @State private var pendingTradeAction: (() -> Void)? = nil
    // Track explicitly selected percentage button (nil = no button selected, user is typing/dragging)
    @State private var selectedPercentage: Int? = nil
    private var cardFillColor: Color { colorScheme == .dark ? DS.Neutral.surface : DS.Adaptive.cardBackground }
    private var cardStrokeColor: Color { colorScheme == .dark ? DS.Neutral.stroke : Color.black.opacity(0.08) }
    private var cardTopHighlightOpacity: Double { colorScheme == .dark ? 0.16 : 0.05 }
    private var labelPrimary: Color { colorScheme == .dark ? .white : .black }
    private var fieldBG: Color { colorScheme == .dark ? Color.white.opacity(0.10) : Color(UIColor.systemGray5) }
    private var topHighlightOpacity: Double { colorScheme == .dark ? 0.16 : 0.04 }
    private var bottomShadeOpacity: Double { colorScheme == .dark ? 1.0 : 0.0 }

    // Robust validation for enabling/disabling the submit button
    private var isSubmitDisabled: Bool {
        let qty = Double(quantity) ?? 0
        if qty <= 0 { return true }
        
        // Validate order type specific inputs
        if orderType == .limit {
            let lp = Double(limitPrice) ?? 0
            if lp <= 0 { return true }
        } else if orderType == .stopLimit {
            let sp = Double(stopPrice) ?? 0
            let lp = Double(limitPrice) ?? 0
            if sp <= 0 || lp <= 0 { return true }
        } else if orderType == .stop {
            let sp = Double(stopPrice) ?? 0
            if sp <= 0 { return true }
        }
        
        // Skip balance check if balance is still loading
        if vm.isLoadingBalance { return false }
        
        // Use trading price (exchange-specific if available, otherwise aggregate)
        let priceForCalc = vm.tradingPrice > 0 ? vm.tradingPrice : vm.currentPrice
        
        // Validate sufficient balance (with small buffer for fees/slippage)
        if selectedSide == .buy {
            guard priceForCalc > 0 else { return true }  // Need valid price for buy calc
            let requiredQuote = qty * priceForCalc * 1.005  // 0.5% buffer for fees
            if requiredQuote > vm.quoteBalance { return true }
        } else {
            if qty > vm.balance { return true }
        }
        
        return false
    }

    private func formatPriceWithCommas(_ value: Double) -> String { formatUSD(value) }

    // MARK: – Section Subviews to reduce body complexity
    private struct FeeCostSection: View {
        let fee: Double
        let totalCost: Double
        @Binding var selectedSide: TradeSide

        @Environment(\.colorScheme) private var colorScheme
        private var labelPrimary: Color { colorScheme == .dark ? .white : .black }
        private var labelSecondary: Color { Color.secondary }
        private var labelPrimaryOpaque: Color { labelPrimary.opacity(0.85) }
        
        var body: some View {
            HStack(spacing: 6) {
                // 3) Increase contrast on Fee/Total HStack:
                Text("Fee")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.75))
                Text(formatPriceWithCommas(fee))
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.75))
                Text("•")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.6))
                Text("Total")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.85))
                Text(formatPriceWithCommas(totalCost))
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }

        private func formatPriceWithCommas(_ value: Double) -> String { formatUSD(value) }
    }

    // MARK: – OrderType Picker Section
    private func orderTypePickerSection() -> some View {
        OrderTypeToggle(selected: $orderType)
            .accessibilityLabel("Order type")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 0)
    }

    // MARK: – Limit/Stop Price Section
    @ViewBuilder
    private func priceInputsSection() -> some View {
        if orderType == .limit {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limit Price")
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.75))
                    TextField("0.00", text: $limitPrice)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .padding(8)
                        .background(fieldBG)
                        .cornerRadius(8)
                }
                Spacer(minLength: 0)
                Text(quoteSymbol)
                    .font(.caption2)
                    .foregroundColor(.primary.opacity(0.65))
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 10)
        } else if orderType == .stopLimit {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stop Price")
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.75))
                    TextField("0.00", text: $stopPrice)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .padding(8)
                        .background(fieldBG)
                        .cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limit Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $limitPrice)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .padding(8)
                        .background(fieldBG)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Quantity Controls Sub-Components
    // Plus/minus buttons adjust allocation by 25% increments (not raw quantity)
    @ViewBuilder
    private func qtyMinusBtn(height: CGFloat) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            // Decrement by 25% allocation, clamped to 0
            let newSlider = max(0, sliderValue - 0.25)
            sliderValue = newSlider
            let pct = Int(newSlider * 100)
            quantity = vm.fillQuantity(forPercent: pct, side: selectedSide)
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(labelPrimary)
        .frame(width: height, height: height)
        .background(Capsule().fill(DS.Adaptive.chipBackground))
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Decrease allocation by 25%")
    }

    @ViewBuilder
    private func qtyPlusBtn(height: CGFloat) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            // Increment by 25% allocation, clamped to 100%
            let newSlider = min(1.0, sliderValue + 0.25)
            sliderValue = newSlider
            let pct = Int(newSlider * 100)
            quantity = vm.fillQuantity(forPercent: pct, side: selectedSide)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(labelPrimary)
        .frame(width: height, height: height)
        .background(Capsule().fill(DS.Adaptive.chipBackground))
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Increase allocation by 25%")
    }

    @ViewBuilder
    private func qtyTextInput(height: CGFloat) -> some View {
        ZStack {
            TextField("Quantity", text: $quantity)
                .keyboardType(.decimalPad)
                .foregroundColor(.primary)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .padding(.trailing, quantity.isEmpty ? 0 : 24)
                .frame(height: height)
                .background(Capsule().fill(DS.Adaptive.chipBackground))
                .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
                .focused(quantityFieldFocused)

            if !quantity.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.easeOut(duration: 0.15)) {
                            quantity = ""
                            sliderValue = 0
                            selectedPercentage = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Clear quantity")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(minWidth: 90, maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: quantity.isEmpty)
        .contextMenu {
            Button("Max") {
                selectedPercentage = 100
                sliderValue = 1.0
                quantity = vm.fillQuantity(forPercent: 100, side: selectedSide)
            }
            Button("75%") {
                selectedPercentage = 75
                sliderValue = 0.75
                quantity = vm.fillQuantity(forPercent: 75, side: selectedSide)
            }
            Button("50%") {
                selectedPercentage = 50
                sliderValue = 0.5
                quantity = vm.fillQuantity(forPercent: 50, side: selectedSide)
            }
            Button("25%") {
                selectedPercentage = 25
                sliderValue = 0.25
                quantity = vm.fillQuantity(forPercent: 25, side: selectedSide)
            }
            Button("Clear") {
                quantity = ""
                sliderValue = 0
                selectedPercentage = nil
            }
        }
    }

    @ViewBuilder
    private func pctBtn(pct: Int, isCompact: Bool, height: CGFloat) -> some View {
        // Use explicit selection tracking to avoid rounding issues
        let isSelected = selectedPercentage == pct
        let isDark = colorScheme == .dark
        let selectionAccent: Color = isDark ? BrandColors.goldBase : BrandColors.silverBase
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedPercentage = pct  // Track explicit selection
            sliderValue = Double(pct) / 100.0
            quantity = vm.fillQuantity(forPercent: pct, side: selectedSide)
        } label: {
            ZStack {
                if isSelected {
                    // Semantic accent by current trading mode / side
                    Capsule()
                        .fill(selectionAccent.opacity(isDark ? 0.85 : 0.8))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(isDark ? 0.12 : 0.25), .clear], startPoint: .top, endPoint: .center))
                    Capsule()
                        .stroke(selectionAccent.opacity(isDark ? 0.55 : 0.42), lineWidth: 0.8)
                }
                Text(pct == 100 ? "Max" : "\(pct)%")
                    .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(isSelected ? .white : labelPrimary.opacity(0.6))
                    .padding(.horizontal, isCompact ? 4 : 6)
            }
            .frame(height: height - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func pctAllocBtns(isCompact: Bool, height: CGFloat) -> some View {
        HStack(spacing: 2) {
            pctBtn(pct: 25, isCompact: isCompact, height: height)
            pctBtn(pct: 50, isCompact: isCompact, height: height)
            pctBtn(pct: 75, isCompact: isCompact, height: height)
            pctBtn(pct: 100, isCompact: isCompact, height: height)
        }
        .padding(1)
        .background(Capsule().fill(DS.Adaptive.chipBackground))
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
    }


    // MARK: - Quantity Controls Section (Two-row layout for compact screens)
    private func quantityControlsSection() -> some View {
        // Use nil-coalescing to treat nil as compact (prevents layout shift)
        let isCompact = (horizontalSizeClass ?? .compact) == .compact
        let controlHeight: CGFloat = isCompact ? 28 : 30
        let rowSpacing: CGFloat = isCompact ? 6 : 10

        return AnyView(
            VStack(spacing: 8) {
                HStack(spacing: rowSpacing) {
                    qtyMinusBtn(height: controlHeight)
                    qtyTextInput(height: controlHeight)
                    qtyPlusBtn(height: controlHeight)
                    pctAllocBtns(isCompact: isCompact, height: controlHeight)
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
        )
    }

    // MARK: – Fee + Balance in one row
    @ViewBuilder
    private func costAndBalanceRow(fee: Double, totalCost: Double, balanceCrypto: Double, balanceUSD: Double, feeRate: Double) -> some View {
        let isBuy = selectedSide == .buy
        let quoteSymbol = vm.quoteAsset
        let feePercentText = String(format: "%.2f%%", feeRate * 100)
        // Use appropriate label: "Total" for buy (cost), "Proceeds" for sell (what user receives)
        let totalLabel = isBuy ? "Total" : "Proceeds"
        
        HStack(spacing: 8) {
            // Left: Fee (rate) • Total/Proceeds
            HStack(spacing: 4) {
                Text("Fee")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.75))
                Text(formatPriceWithCommas(fee))
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.75))
                // Show fee percentage for transparency
                Text("(\(feePercentText))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.5))
                Text(totalLabel)
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.85))
                Text(formatPriceWithCommas(totalCost))
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            // Right: Balance (context-aware - show quote for buy, base for sell)
            if vm.isLoadingBalance {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if isBuy {
                // For BUY: show quote balance (what we spend)
                Text("Available: \(formatBalanceCompact(vm.quoteBalance)) \(quoteSymbol)")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            } else {
                // For SELL: show base balance (what we sell)
                Text("Available: \(formatBalanceCompact(balanceCrypto)) \(symbol.uppercased())")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 10)
    }
    
    // Format balance compactly
    private func formatBalanceCompact(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f", value)
        } else if value >= 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    // MARK: – Balance Row Section
    @ViewBuilder
    private func balanceBotRowSection(balanceCrypto: Double, balanceUSD: Double) -> some View {
        let isBuy = selectedSide == .buy
        let quoteSymbol = vm.quoteAsset
        
        Group {
            if vm.isLoadingBalance {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading balance...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if isBuy {
                Text("Available: \(formatBalanceCompact(vm.quoteBalance)) \(quoteSymbol)")
                    .font(.caption2)
                    .foregroundColor(.primary)
            } else {
                Text("Balance: \(formatBalanceCompact(balanceCrypto)) \(symbol.uppercased())  ≈ \(formatPriceWithCommas(balanceUSD))")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 10)
    }

    // MARK: – Slider Row Section
    private func sliderRowSection() -> some View {
        HStack {
            SingleTrackSlider(
                value: $sliderValue,
                range: 0...1,
                step: 0,
                trackHeight: 3,
                knobSize: 24,
                activeColor: colorScheme == .dark ? BrandColors.goldBase : BrandColors.silverBase,
                inactiveColor: colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.20)
            ) { newVal in
                let pct = Int(newVal * 100)
                quantity = vm.fillQuantity(forPercent: pct, side: selectedSide)
                // Clear explicit percentage selection when user drags slider freely
                selectedPercentage = nil
            }
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 10)
    }
    
    // MARK: – Buy/Sell Segmented
    private func sideSegmentedControl() -> some View {
        TradeSideToggle(selected: $selectedSide)
            .accessibilityLabel("Order side")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 0)
    }

    // MARK: – Submit Button Section
    @ViewBuilder
    private func submitButtonSection() -> some View {
        let isSell = (selectedSide == .sell)
        let isExecuting = vm.isExecutingOrder
        let hasNoExchange = !vm.hasConnectedExchange
        let isPaperMode = PaperTradingManager.isEnabled
        // Don't disable button for no exchange when paper trading is enabled
        let isDisabled = isSubmitDisabled || isExecuting || (hasNoExchange && !isPaperMode)
        
        VStack(spacing: 6) {
            // Error message if any
            if let errorMsg = vm.orderErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .transition(.opacity)
            }
            
            Button {
                // Allow trading in paper trading mode even without exchange
                guard !hasNoExchange || PaperTradingManager.isEnabled else { return }
                
                // Store the pending trade action
                pendingTradeAction = { [selectedSide, symbol, orderType, quantity, limitPrice, stopPrice] in
                    vm.executeTrade(side: selectedSide, symbol: symbol, orderType: orderType, quantity: quantity, limitPriceStr: limitPrice, stopPriceStr: stopPrice)
                }
                
                // Paper trading: show confirmation dialog (no ToS/risk needed for simulated money)
                if PaperTradingManager.isEnabled {
                    showingPaperTradeConfirmation = true
                    return
                }
                
                // Step 1: Check if user has accepted Terms of Service
                if TradingRiskAcknowledgmentManager.shared.needsToSAcceptance {
                    showingToSAcceptance = true
                    return
                }
                
                // Step 2: Check if user has acknowledged trading risks
                if !TradingRiskAcknowledgmentManager.shared.hasValidAcknowledgment {
                    showingRiskAcknowledgment = true
                    return
                }
                
                // Step 3: Show pre-trade confirmation for real trades (every time)
                showingPreTradeConfirmation = true
            } label: {
                ZStack {
                    // Gradient background with subtle top highlight and stroke
                    // Use blue gradient for paper trading mode
                    let isPaperMode = PaperTradingManager.isEnabled
                    // Adaptive disabled background - darker in light mode for contrast
                    let disabledBg = colorScheme == .dark
                        ? Color.gray.opacity(0.4)
                        : Color(red: 0.85, green: 0.83, blue: 0.81) // Warm gray for light mode
                    
                    // LIGHT MODE FIX: In light mode, use green gradient for Buy (trading convention)
                    // instead of charcoal/silver which looks dull and doesn't communicate "buy" action.
                    // Dark mode keeps gold for brand identity.
                    let greenBuyGradient = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.25, green: 0.78, blue: 0.42), location: 0.0),
                            .init(color: Color(red: 0.18, green: 0.68, blue: 0.34), location: 0.52),
                            .init(color: Color(red: 0.12, green: 0.55, blue: 0.26), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    let buttonGradient: AnyShapeStyle = {
                        if isDisabled {
                            return AnyShapeStyle(disabledBg)
                        } else if isPaperMode {
                            return AnyShapeStyle(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                        } else if isSell {
                            return AnyShapeStyle(redButtonGradient)
                        } else {
                            // Light mode: green for "Buy" clarity; Dark mode: gold for brand
                            return colorScheme == .dark
                                ? AnyShapeStyle(AdaptiveGradients.goldButton(isDark: true))
                                : AnyShapeStyle(greenBuyGradient)
                        }
                    }()
                    
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(buttonGradient)
                        .overlay(
                            LinearGradient(colors: [(isSell ? Color.white.opacity(0.10) : Color.white.opacity(0.16)), Color.clear], startPoint: .top, endPoint: .center)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .opacity(isDisabled ? 0.5 : 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isDisabled
                                        ? AnyShapeStyle(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(red: 0.75, green: 0.72, blue: 0.70))
                                        : (isPaperMode
                                            ? AnyShapeStyle(Color.white.opacity(0.3))
                                            : AnyShapeStyle(isSell
                                                ? ctaRimStrokeGradientRed
                                                : (colorScheme == .dark
                                                    ? AdaptiveGradients.ctaRimStroke(isDark: true)
                                                    // LIGHT MODE FIX: Green rim for Buy button
                                                    : LinearGradient(colors: [Color.white.opacity(0.35), Color(red: 0.10, green: 0.50, blue: 0.22).opacity(0.25)], startPoint: .top, endPoint: .bottom)))),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            AdaptiveGradients.ctaBottomShade(isDark: colorScheme == .dark)
                                .opacity(isDisabled ? 0 : bottomShadeOpacity)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        )
                    
                    HStack(spacing: 8) {
                        // LIGHT MODE FIX: Buy button text is white on green in light mode
                        let buyTextColor: Color = colorScheme == .dark ? .black.opacity(0.96) : .white
                        
                        if isExecuting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(isPaperMode || isSell || colorScheme == .light ? .white : .black)
                        }
                        
                        // Show "Paper" prefix when paper trading is enabled
                        if isPaperMode {
                            Image(systemName: "doc.text.fill")
                                .font(.subheadline)
                                .foregroundColor(isDisabled ? (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.45)) : .white)
                        }
                        
                        // Show Buy/Sell text with Paper prefix if in paper mode
                        // Adaptive text color - dark in light mode for disabled state
                        let disabledTextColor = colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.45)
                        Text(isPaperMode ? "Paper \(selectedSide.rawValue.capitalized) \(symbol.uppercased())" : "\(selectedSide.rawValue.capitalized) \(symbol.uppercased())")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isDisabled ? disabledTextColor : (isPaperMode || isSell ? .white : buyTextColor))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(PaperTradingManager.isEnabled ? "Paper \(selectedSide.rawValue.capitalized) \(symbol.uppercased())" : "\(selectedSide.rawValue.capitalized) \(symbol.uppercased())")
            .accessibilityHint("Submits a \(selectedSide.rawValue) order")
            .buttonStyle(GlowButtonStyle(isSell: isSell && !isDisabled))
            .padding(.horizontal, 10)
            .padding(.vertical, 0)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.7 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.orderErrorMessage)
    }

    var body: some View {
        let qtyVal     = Double(quantity) ?? 0
        // Use trading price (exchange-specific if available) for consistent calculations
        let priceForCalc = vm.tradingPrice > 0 ? vm.tradingPrice : (priceVM.price > 0 ? priceVM.price : vm.currentPrice)
        let tradeAmount = qtyVal * priceForCalc
        let fee        = tradeAmount * vm.currentFeeRate  // Use exchange-specific fee rate
        // For BUY: total cost = trade amount + fee (user pays)
        // For SELL: total proceeds = trade amount - fee (user receives)
        let totalCostOrProceeds = selectedSide == .buy ? (tradeAmount + fee) : (tradeAmount - fee)
        let balanceCrypto = vm.balance
        let balanceUSD = balanceCrypto * priceForCalc

        VStack(spacing: 4) {
            orderTypePickerSection()
            priceInputsSection()
            quantityControlsSection()
            sliderRowSection()
            Divider().background(DS.Neutral.divider(0.10))
            costAndBalanceRow(fee: fee, totalCost: totalCostOrProceeds, balanceCrypto: balanceCrypto, balanceUSD: balanceUSD, feeRate: vm.currentFeeRate)
            sideSegmentedControl()
            // Hide submit button when keyboard is visible to avoid duplicate with keyboardSubmitButton
            if !isKeyboardVisible {
                submitButtonSection()
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        .overlay(
            LinearGradient(colors: [Color.white.opacity(topHighlightOpacity), Color.clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            ctaBottomShade
                .opacity(bottomShadeOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: quantity) { _, newVal in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let q = Double(newVal) ?? 0
                
                // Reset slider and clear selection when quantity is empty
                if q <= 0 {
                    sliderValue = 0
                    selectedPercentage = nil
                    return
                }
                
                // Clear percentage button selection when user is actively typing
                // (quantityFieldFocused indicates the text field has keyboard focus)
                if quantityFieldFocused.wrappedValue {
                    selectedPercentage = nil
                }
                
                let pct: Double
                if selectedSide == .buy {
                    // For BUY: calculate what percentage of quoteBalance this quantity represents
                    // (quantity * price) / quoteBalance
                    let totalCost = q * vm.currentPrice
                    let denom = max(vm.quoteBalance, 0.01)
                    pct = min(max(totalCost / denom, 0), 1)
                } else {
                    // For SELL: calculate what percentage of base balance this quantity represents
                    let denom = max(vm.balance, 0.00000001)
                    pct = min(max(q / denom, 0), 1)
                }
                
                // Only update slider if the user typed a value reasonably within 0-100% of balance
                if pct.isFinite {
                    Task { @MainActor in sliderValue = pct }
                }
            }
        }
        .modifier(TradeFormConfirmationModifiers(
            showingToSAcceptance: $showingToSAcceptance,
            showingRiskAcknowledgment: $showingRiskAcknowledgment,
            showingPreTradeConfirmation: $showingPreTradeConfirmation,
            showingPaperTradeConfirmation: $showingPaperTradeConfirmation,
            pendingTradeAction: $pendingTradeAction,
            confirmButtonLabel: confirmButtonLabel,
            orderSummaryText: orderSummaryText,
            symbol: symbol,
            selectedSide: selectedSide,
            quantity: quantity,
            currentPrice: vm.currentPrice
        ))
    }
    
    // MARK: - Confirmation Helpers
    
    /// Builds a detailed order summary for the confirmation dialog.
    private func orderSummaryText(isPaper: Bool) -> String {
        let side = selectedSide == .buy ? "BUY" : "SELL"
        let sym = symbol.uppercased()
        let qty = Double(quantity) ?? 0
        let price = vm.tradingPrice > 0 ? vm.tradingPrice : vm.currentPrice
        
        let effectivePrice: Double
        let priceLabel: String
        switch orderType {
        case .market:
            effectivePrice = price
            priceLabel = "Market Price"
        case .limit:
            effectivePrice = Double(limitPrice) ?? price
            priceLabel = "Limit Price"
        case .stop, .stopLoss:
            effectivePrice = Double(stopPrice) ?? price
            priceLabel = "Stop Price"
        case .stopLimit:
            effectivePrice = Double(limitPrice) ?? price
            priceLabel = "Stop-Limit Price"
        }

        let subtotal = qty * effectivePrice
        let feeRate = vm.currentFeeRate
        let fee = subtotal * feeRate
        let feePercent = String(format: "%.2f", feeRate * 100)
        let total = selectedSide == .buy ? subtotal + fee : subtotal - fee

        let orderTypeName: String = {
            switch orderType {
            case .market:    return "Market Order"
            case .limit:     return "Limit Order"
            case .stop, .stopLoss: return "Stop Order"
            case .stopLimit: return "Stop-Limit Order"
            }
        }()

        var lines: [String] = []
        lines.append("\(side) \(quantity) \(sym)")
        lines.append("Order Type: \(orderTypeName)")
        lines.append("\(priceLabel): \(formatUSD(effectivePrice))")

        if orderType == .stopLimit, let sp = Double(stopPrice), sp > 0 {
            lines.append("Stop Trigger: \(formatUSD(sp))")
        }

        lines.append("")
        lines.append("Subtotal: \(formatUSD(subtotal))")
        lines.append("Fee (\(feePercent)%): \(formatUSD(fee))")

        if selectedSide == .buy {
            lines.append("Total Cost: \(formatUSD(total))")
        } else {
            lines.append("You Receive: \(formatUSD(total))")
        }

        if isPaper {
            lines.append("")
            lines.append("This is a simulated trade using virtual funds. No real money is involved.")
        } else {
            lines.append("")
            lines.append("⚠️ This will execute a REAL trade on your connected exchange. This action cannot be undone. You may lose money.")
        }

        return lines.joined(separator: "\n")
    }

    /// Format the confirm button label to include the dollar amount.
    private func confirmButtonLabel(isPaper: Bool) -> String {
        let side = selectedSide == .buy ? "Buy" : "Sell"
        let sym = symbol.uppercased()
        let qty = Double(quantity) ?? 0
        let price = vm.tradingPrice > 0 ? vm.tradingPrice : vm.currentPrice
        let effectivePrice: Double = {
            switch orderType {
            case .limit, .stopLimit: return Double(limitPrice) ?? price
            case .stop, .stopLoss: return Double(stopPrice) ?? price
            case .market: return price
            }
        }()
        let total = qty * effectivePrice
        let prefix = isPaper ? "Paper " : ""
        return "\(prefix)\(side) \(formatUSD(total)) \(sym)"
    }
}

// MARK: - Confirmation Sheet/Alert Modifiers (extracted to reduce body complexity)
private struct TradeFormConfirmationModifiers: ViewModifier {
    @Binding var showingToSAcceptance: Bool
    @Binding var showingRiskAcknowledgment: Bool
    @Binding var showingPreTradeConfirmation: Bool
    @Binding var showingPaperTradeConfirmation: Bool
    @Binding var pendingTradeAction: (() -> Void)?
    let confirmButtonLabel: (Bool) -> String
    let orderSummaryText: (Bool) -> String
    let symbol: String
    let selectedSide: TradeSide
    let quantity: String
    let currentPrice: Double
    
    func body(content: Content) -> some View {
        content
            // Terms of Service acceptance sheet (shown first for real trades)
            .sheet(isPresented: $showingToSAcceptance) {
                TermsOfServiceAcceptanceView(
                    onAccept: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !TradingRiskAcknowledgmentManager.shared.hasValidAcknowledgment {
                                showingRiskAcknowledgment = true
                            } else {
                                showingPreTradeConfirmation = true
                            }
                        }
                    },
                    onDecline: {
                        pendingTradeAction = nil
                    }
                )
            }
            // Trading risk acknowledgment sheet (shown after ToS acceptance)
            .sheet(isPresented: $showingRiskAcknowledgment) {
                TradingRiskAcknowledgmentView(
                    onAcknowledge: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingPreTradeConfirmation = true
                        }
                    },
                    onDecline: {
                        pendingTradeAction = nil
                    }
                )
            }
            // Pre-trade confirmation dialog (real trades)
            .alert("⚠️ Review Real Trade", isPresented: $showingPreTradeConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingTradeAction = nil
                }
                Button(confirmButtonLabel(false), role: .destructive) {
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    #endif
                    TradingRiskAcknowledgmentManager.shared.logTradeConfirmation(
                        symbol: symbol,
                        side: selectedSide.rawValue,
                        quantity: Double(quantity) ?? 0,
                        price: currentPrice
                    )
                    pendingTradeAction?()
                    pendingTradeAction = nil
                }
            } message: {
                Text(orderSummaryText(false))
            }
            // Paper trade confirmation dialog
            .alert("Review Paper Trade", isPresented: $showingPaperTradeConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingTradeAction = nil
                }
                Button(confirmButtonLabel(true)) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    pendingTradeAction?()
                    pendingTradeAction = nil
                }
            } message: {
                Text(orderSummaryText(true))
            }
    }
}
    
// MARK: - Other code unchanged...

// MARK: - TradeView
struct TradeView: View {
    @Namespace private var depthNamespace
    
    // The symbol to trade (default "BTC")
    @State private var symbol: String
    
    // Whether to show a "Back" button
    private let showBackButton: Bool
    
    // Main ViewModels - using shared singletons for performance (prevents recreation on tab switches)
    @ObservedObject private var vm = TradeViewModel.shared
    @ObservedObject private var orderBookVM = OrderBookViewModel.shared
    @StateObject private var priceVM: PriceViewModel
    @EnvironmentObject private var marketVM: MarketViewModel
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // UI states
    @State private var selectedInterval: ChartInterval
    @State private var selectedSide: TradeSide = .buy
    @State private var orderType: OrderType = .market

    @State private var quantity: String = ""
    @State private var limitPrice: String = ""
    @State private var stopPrice: String = ""

    // Slider from 0..1 so user can pick a fraction of “balance”
    @State private var sliderValue: Double = 0.0
    @State private var showOrderBook: Bool = true  // Show order book immediately without skeleton

    // Coin/Pair picker
    @State private var isCoinPickerPresented = false
    @State private var isOrderBookModalPresented: Bool = false
    @State private var selectedQuote: String = "USDT"
    @State private var selectedPairExchange: String? = nil
    
    // Pending USD amount from AI trade config (will be converted to quantity when price is known)
    @State private var pendingUSDAmount: Double? = nil
    @State private var hasConvertedUSDAmount: Bool = false

    @State private var showBotSelectionSheet: Bool = false
    @State private var showBotHubFromSocial: Bool = false  // Navigation from Social tab copy
    @State private var hasPerformedInitialSetup: Bool = false  // Track first appearance for one-time setup
    @State private var showSmartTradingHub: Bool = false   // Smart Trading Hub navigation
    @State private var showDerivativesBotFromAI: Bool = false  // Navigation from AI Chat for derivatives trades
    @State private var showTradingBotFromAI: Bool = false  // Navigation from AI Chat for trading bots
    @State private var showPredictionBotFromAI: Bool = false  // Navigation from AI Chat for prediction bots
    @State private var showPaperTradingUpgrade: Bool = false  // Upgrade prompt for Free users (paper trading)
    @State private var showPaperTradingSettings: Bool = false  // Paper Trading settings sheet
    @State private var showSmartTradeUpgrade: Bool = false   // Upgrade prompt for non-Premium users (trading bots)
    @State private var showStrategiesHub: Bool = false       // Navigation to Strategies mode in SmartTradingHub
    @State private var showStrategiesUpgrade: Bool = false   // Upgrade prompt for strategies
    @State private var useLogScale: Bool = true
    @State private var depthMode: DepthMode = .qty  // Default to Qty like Binance/Coinbase
    @State private var priceGrouping: PriceGrouping = .p1  // Default to $1 grouping for BTC
    @State private var showDepthChart: Bool = false  // Toggle between table and depth chart
    @State private var isActiveTab: Bool = false
    
    // FIX: Track initial layout completion to prevent blank screen on cold start
    // When LazyView initializes TradeView after a long background period, GeometryReader
    // can return zero size on first layout pass, causing content to not render
    @State private var didCompleteInitialLayout: Bool = false
    
    // PERFORMANCE: Tab switch debouncing to prevent rapid start/stop cycles
    @State private var tabSwitchDebounceWork: DispatchWorkItem? = nil
    
    // PERFORMANCE: Track when app went to background for time-based scene phase guards
    @State private var lastBackgroundAt: Date? = nil
    
    // Risk acknowledgment states
    @State private var showingToSAcceptance: Bool = false
    @State private var showingRiskAcknowledgment: Bool = false
    @State private var showingPreTradeConfirmation: Bool = false
    @State private var showingPaperTradeConfirmation: Bool = false
    @State private var pendingTradeAction: (() -> Void)? = nil

    @AppStorage("Chart.ShowVolume") private var prefShowVolume: Bool = true
    @AppStorage("Chart.Indicators.SMA.Enabled") private var prefSMAEnabled: Bool = false
    @AppStorage("Chart.Indicators.EMA.Enabled") private var prefEMAEnabled: Bool = false
    @AppStorage("TV.Indicators.Selected") private var tvIndicatorsRaw: String = ""

    @AppStorage("Trade.ChartSource") private var storedChartSourceRaw: String = "sage"
    @AppStorage("Trade.Interval") private var storedIntervalRaw: String = ChartInterval.oneHour.rawValue
    
    @State private var tvReady: Bool = false
    @State private var tvExchangePrefix: String = "BINANCE"
    @State private var tvQuote: String = "USDT"
    
    @State private var chartWidth: CGFloat = 0
    @State private var chartLastLoadedAt: Date? = nil
    
    // CHART READJUST FIX: Stabilize the livePrice passed to CryptoChartView during cold start.
    // During the first ~1s, displayedPrice changes rapidly as it resolves through multiple
    // sources (0 -> cache -> bestPrice). Each change re-evaluates the chart body and can
    // trigger Y-domain recomputation. By caching the first valid price and only updating
    // after settling, we prevent the chart from readjusting during initial load.
    @State private var stabilizedChartPrice: Double = 0
    @State private var chartPriceSettledAt: Date = .distantPast
    private let chartPriceSettlingDuration: TimeInterval = 1.2

    @State private var mountTradingView: Bool = false
    @State private var showTimeframePopover: Bool = false
    @State private var timeframeButtonFrame: CGRect = .zero
    @State private var timeframePopoverEdge: Edge = .bottom
    @State private var timeframeFrameDebounce: DispatchWorkItem? = nil
    @State private var coinImageURL: URL? = nil

    // MARK: - Keyboard Height State
    @State private var keyboardHeight: CGFloat = 0
    // FocusState for quantity field - lifted from TradeFormView for proper keyboard toolbar support
    @FocusState private var isQuantityFocused: Bool
    // Publisher for keyboard height
    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
                .map { $0.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .eraseToAnyPublisher()
    }
    
    // Computed based on size class to prevent layout shift from state change
    // Use nil-coalescing to treat nil as compact (default for most iPhone users)
    // Reduced row counts for cleaner visual appearance (was 24:32)
    private var rowsToShow: Int { (horizontalSizeClass ?? .compact) == .compact ? 18 : 24 }

    // Added DispatchWorkItem state for debounced chartWidth update per instructions
    @State private var chartWidthDebounceWork: DispatchWorkItem? = nil
    
    private var contentHPad: CGFloat { (self.horizontalSizeClass ?? .compact) == .compact ? 10 : 16 }
    private var cardFillColor: Color { colorScheme == .dark ? DS.Neutral.surface : DS.Adaptive.cardBackground }
    private var cardStrokeColor: Color { colorScheme == .dark ? DS.Neutral.stroke : Color.black.opacity(0.08) }
    private var pageBackground: Color { colorScheme == .dark ? Color.black : DS.Adaptive.background }
    
    // Order book fill with elevated surface for better visual separation from main background
    private var orderBookFillColor: Color {
        colorScheme == .dark
            ? Color(UIColor(white: 0.11, alpha: 1.0)) // Elevated from 0.08 to 0.11 for better hierarchy
            : DS.Adaptive.cardBackground
    }
    // Subtle stroke for order book border - slightly stronger for definition
    private var orderBookStrokeColor: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10) }
    
    // Chart container theme with matched corner radius for seamless edges
    private var chartContainerTheme: ChartTheme {
        var theme = ChartTheme()
        theme.panelCornerRadius = 12  // Match outer card corner radius
        theme.panelBorderColor = .clear  // Outer card already has stroke
        // LIGHT MODE FIX: Replaced black tints with transparent/warm tones.
        // The black opacity was creating a grayish-green muddy tint over the chart in light mode.
        theme.panelTopShade = colorScheme == .dark ? Color.black.opacity(0.20) : Color.clear
        theme.panelBottomShade = colorScheme == .dark ? Color.black.opacity(0.10) : Color.clear
        // LIGHT MODE FIX: Disable vignette overlay in light mode - it darkens edges
        theme.disableVignette = colorScheme == .light
        return theme
    }

    private var cardBottomShadeOpacity: Double { colorScheme == .dark ? 1.0 : 0.08 }
    private var cardTopHighlightOpacity: Double { colorScheme == .dark ? 0.16 : 0.05 }
    
    // Shared validation used for bottom CTA when keyboard is shown
    private var isSubmitDisabledGlobal: Bool {
        let q = Double(quantity) ?? 0
        if q <= 0 { return true }
        if orderType == .limit {
            let lp = Double(limitPrice) ?? 0
            return lp <= 0
        } else if orderType == .stopLimit {
            let sp = Double(stopPrice) ?? 0
            let lp = Double(limitPrice) ?? 0
            return sp <= 0 || lp <= 0
        }
        return false
    }

    // Added part 1) app appearance override storage and helpers here:
    @AppStorage("App.Appearance") private var appAppearanceRaw: String = "system" // values: system, light, dark
    @AppStorage("Settings.DarkMode") private var settingsDarkMode: Bool = false
    enum AppearanceOverride: String { case system, light, dark }

    private var appAppearance: AppearanceOverride { AppearanceOverride(rawValue: appAppearanceRaw) ?? .system }
    
    // Paper trading promo banner dismiss tracking (24-hour cooldown)
    @AppStorage("Trade.PromoBannerDismissedAt") private var promoBannerDismissedAt: Double = 0
    
    /// Check if the promo banner should be shown (not dismissed within the last 24 hours)
    private var shouldShowPromoBanner: Bool {
        let dismissedDate = Date(timeIntervalSince1970: promoBannerDismissedAt)
        let hoursSinceDismiss = Date().timeIntervalSince(dismissedDate) / 3600
        return hoursSinceDismiss >= 24 // Show again after 24 hours
    }
    
    /// Dismiss the promo banner for 24 hours
    private func dismissPromoBanner() {
        promoBannerDismissedAt = Date().timeIntervalSince1970
    }

    // MARK: - Init
    init(symbol: String = "BTC", showBackButton: Bool = false, prefilledConfig: AITradeConfig? = nil) {
        let symbolToUse = prefilledConfig?.symbol.uppercased() ?? symbol.uppercased()
        _symbol = State(initialValue: symbolToUse)
        self.showBackButton = showBackButton
        _priceVM = StateObject(wrappedValue: PriceViewModel(symbol: symbolToUse, timeframe: .live))
        
        // Update shared ViewModels with the new symbol (instead of creating new instances)
        // This is done via Task to avoid "Modifying state during view update" warnings
        Task { @MainActor in
            TradeViewModel.shared.updateSymbol(symbolToUse)
        }
        
        // Initialize states from stored values to prevent layout shift on appear
        // Read directly from UserDefaults since @AppStorage isn't available in init
        let storedIntervalStr = UserDefaults.standard.string(forKey: "Trade.Interval") ?? ChartInterval.oneHour.rawValue
        _selectedInterval = State(initialValue: ChartInterval(rawValue: storedIntervalStr) ?? .oneHour)
        
        let storedSourceStr = UserDefaults.standard.string(forKey: "Trade.ChartSource") ?? "sage"
        _selectedChartSource = State(initialValue: storedSourceStr == "trading" ? .trading : .sage)
        
        // Apply prefilled config if provided (from AI trade configuration)
        if let config = prefilledConfig {
            _selectedSide = State(initialValue: config.direction == .buy ? .buy : .sell)
            _orderType = State(initialValue: config.orderType == .limit ? .limit : .market)
            _limitPrice = State(initialValue: config.price ?? "")
            
            // Set quote currency if provided
            if let quote = config.quoteCurrency {
                _selectedQuote = State(initialValue: quote)
            }
            
            // Handle USD amount vs quantity
            if let amount = config.amount {
                if config.isUSDAmount {
                    // Store USD amount for conversion when price is available
                    _pendingUSDAmount = State(initialValue: Double(amount))
                    _quantity = State(initialValue: "")
                    _hasConvertedUSDAmount = State(initialValue: false)
                } else {
                    // Direct quantity
                    _quantity = State(initialValue: amount)
                }
            }
            
            // Note: stopPrice and takeProfit can be shown as guidance in the UI
        }
    }
    
    private func imageURLForSymbol(_ symbol: String) -> URL? {
        let lower = symbol.lowercased()
        if let coin = marketVM.allCoins.first(where: { $0.symbol.lowercased() == lower }) {
            return coin.imageUrl
        }
        return nil
    }
    
    // Cache last known price per symbol to avoid showing $0.00 while feeds warm up
    private func cachedPrice(for symbol: String) -> Double {
        UserDefaults.standard.double(forKey: "LastPrice_\(symbol.uppercased())")
    }
    private func setCachedPrice(_ price: Double, for symbol: String) {
        guard price > 0 else { return }
        UserDefaults.standard.set(price, forKey: "LastPrice_\(symbol.uppercased())")
    }
    
    private func updateTVRouting() {
        let isUS = ComplianceManager.shared.isUSUser
        
        // EXCHANGE SELECTION: Use selected exchange for TradingView chart
        // This ensures the chart shows data from the same exchange the user picked
        if let exchange = selectedPairExchange?.lowercased() {
            switch exchange {
            case "coinbase":
                tvExchangePrefix = "COINBASE"
                tvQuote = "USD"
            case "kraken":
                tvExchangePrefix = "KRAKEN"
                tvQuote = "USD"
            case "kucoin":
                tvExchangePrefix = "KUCOIN"
                tvQuote = "USDT"
            case "binance":
                tvExchangePrefix = isUS ? "BINANCEUS" : "BINANCE"
                tvQuote = isUS ? "USD" : "USDT"
            default:
                // Default to Binance for unknown exchanges
                tvExchangePrefix = isUS ? "BINANCEUS" : "BINANCE"
                tvQuote = isUS ? "USD" : "USDT"
            }
        } else {
            // No exchange selected - use default based on region
            if isUS {
                tvExchangePrefix = "BINANCEUS"
                tvQuote = "USD"
                // Sync selectedQuote if it hasn't been explicitly set by user
                if selectedQuote == "USDT" { selectedQuote = "USD" }
            } else {
                tvExchangePrefix = "BINANCE"
                tvQuote = "USDT"
            }
        }
    }
    
    /// Apply pending trade configuration from AI Chat
    /// Called when user navigates to Trading tab after tapping Execute Trade button in AI Chat
    private func applyPendingTradeConfig() {
        guard let config = appState.pendingTradeConfig else { return }
        // Do not consume config before TradeView is actually active and initialized.
        guard appState.selectedTab == .trade, hasPerformedInitialSetup else { return }
        let normalizedSymbol = config.symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSymbol.isEmpty else { return }
        
        #if DEBUG
        print("[TradeView] Applying pending trade config: \(config.symbol) \(config.direction) \(config.orderType)")
        #endif
        
        // Update symbol if different
        if normalizedSymbol != symbol.uppercased() {
            symbol = normalizedSymbol
            // CRITICAL: Reset price before changing symbol to prevent stale cross-symbol prices
            vm.currentPrice = 0
            vm.currentSymbol = normalizedSymbol
            priceVM.updateSymbol(normalizedSymbol)
        }
        
        // Set quote currency if provided
        if let quote = config.quoteCurrency {
            selectedQuote = quote
        }
        
        // Set trade direction
        selectedSide = config.direction == .buy ? .buy : .sell
        
        // Set order type
        orderType = config.orderType == .limit ? .limit : .market
        
        // Set limit price if applicable
        if let price = config.price {
            limitPrice = price
        }

        // If AI provided risk levels as absolute prices, carry them into supported fields.
        if stopPrice.isEmpty, let guidedStop = normalizedRiskLevelAsPrice(config.stopLoss) {
            stopPrice = guidedStop
        }
        if limitPrice.isEmpty, orderType == .limit, let guidedTakeProfit = normalizedRiskLevelAsPrice(config.takeProfit) {
            limitPrice = guidedTakeProfit
        }
        
        // Handle amount
        if let amount = config.amount {
            if config.isUSDAmount {
                // Store for USD to quantity conversion when price is available
                pendingUSDAmount = Double(amount)
                hasConvertedUSDAmount = false
                quantity = ""
            } else {
                // Direct quantity
                quantity = amount
            }
        }
        
        // Start order book fetching for the new symbol with selected exchange
        orderBookVM.stopFetching()
        orderBookVM.startFetchingOrderBook(for: symbol, exchange: selectedPairExchange)
        refreshRecommendedPriceGrouping(for: symbol)
        
        // Update coin image
        coinImageURL = imageURLForSymbol(symbol)
        
        // Try immediate conversion if price is already available
        if priceVM.price > 0 {
            convertPendingUSDToQuantity()
        }
        
        // Fallback: retry conversion after short delays in case price loads shortly after
        // This handles race conditions where price arrives after config is applied
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.convertPendingUSDToQuantity()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.convertPendingUSDToQuantity()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.convertPendingUSDToQuantity()
        }
        
        // Clear only after the form has consumed the config.
        appState.pendingTradeConfig = nil
    }
    
    /// Convert pending USD amount to quantity when price becomes available
    /// Called when TradeView is opened from AI chat with a USD amount (e.g., "buy $100 of BTC")
    private func convertPendingUSDToQuantity() {
        guard let usdAmount = pendingUSDAmount,
              !hasConvertedUSDAmount,
              priceVM.price > 0 else { return }
        
        // Calculate quantity from USD amount and current price
        let calculatedQuantity = usdAmount / priceVM.price
        
        // Format with appropriate precision based on quantity size
        let formattedQuantity: String
        if calculatedQuantity >= 1 {
            formattedQuantity = String(format: "%.4f", calculatedQuantity)
        } else if calculatedQuantity >= 0.0001 {
            formattedQuantity = String(format: "%.6f", calculatedQuantity)
        } else {
            formattedQuantity = String(format: "%.8f", calculatedQuantity)
        }
        
        // Update the quantity field
        quantity = formattedQuantity
        hasConvertedUSDAmount = true
        pendingUSDAmount = nil
        
        #if DEBUG
        print("[TradeView] Converted $\(usdAmount) to \(formattedQuantity) \(symbol) at price $\(priceVM.price)")
        #endif
    }

    private func normalizedBaseSymbol(_ raw: String) -> String {
        let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if upper.isEmpty { return upper }
        if upper.contains("-") { return upper.split(separator: "-").first.map(String.init) ?? upper }
        if upper.contains("_") { return upper.split(separator: "_").first.map(String.init) ?? upper }
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        if let quote = quotes.first(where: { upper.hasSuffix($0) }), upper.count > quote.count {
            return String(upper.dropLast(quote.count))
        }
        return upper
    }

    private func refreshRecommendedPriceGrouping(for symbol: String) {
        let base = normalizedBaseSymbol(symbol)
        let resolvedPrice: Double = {
            if priceVM.price > 0 && priceVM.price.isFinite { return priceVM.price }
            if vm.currentPrice > 0 && vm.currentPrice.isFinite { return vm.currentPrice }
            if let p = MarketViewModel.shared.bestPrice(forSymbol: base), p > 0, p.isFinite { return p }
            return 0
        }()
        let recommended = PriceGrouping.recommended(for: resolvedPrice)
        if priceGrouping != recommended {
            priceGrouping = recommended
        }
    }

    /// Parse AI-provided risk strings into usable absolute prices when they look like prices.
    /// This ignores percentage-style values (e.g. "5" for "5% stop loss") to avoid bad prefills.
    private func normalizedRiskLevelAsPrice(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard let value = Double(cleaned), value > 0, value.isFinite else { return nil }

        let referencePrice = displayedPrice > 0 ? displayedPrice : priceVM.price
        if referencePrice > 0 {
            // Percentage-like values are usually tiny relative to market price; ignore them.
            guard value >= referencePrice * 0.3 else { return nil }
        }
        return cleaned
    }

    /// Get the CoinGecko ID for the current symbol (used for price lookups)
    private var currentCoinID: String {
        let symLower = symbol.lowercased()
        // Try to find the coin ID from allCoins
        if let coin = marketVM.allCoins.first(where: { $0.symbol.lowercased() == symLower }) {
            return coin.id
        }
        // Fallback: use symbol as ID (works for major coins like bitcoin, ethereum)
        return symLower
    }
    
    private var displayedPrice: Double {
        // UNIFIED PRICE LOGIC:
        // All views (Trading, Market, Watchlist, Home) use MarketViewModel.bestPrice()
        // as the single source of truth. bestPrice() returns CoinGecko prices via
        // Firebase/Firestore (LivePriceManager). Exchange-specific prices (order book
        // bid/ask) are NOT mixed in — they naturally differ from the aggregated price.
        // This ensures the Trading header always matches Market and Watchlist.
        
        // Priority 1: MarketViewModel.bestPrice (CoinGecko via Firebase — same across all views)
        if let best = marketVM.bestPrice(for: currentCoinID), best > 0 { return best }
        
        // Priority 2: TradeViewModel.currentPrice (from LivePriceManager stream)
        if vm.currentPrice > 0 { return vm.currentPrice }
        
        // Priority 3: PriceViewModel
        if priceVM.price > 0 { return priceVM.price }
        
        // Priority 4: allCoins cache (startup fallback)
        let symUpper = symbol.uppercased()
        if let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == symUpper }), let p = coin.priceUsd, p > 0 {
            return p
        }
        
        // Priority 5: Local cache (last resort)
        let cached = cachedPrice(for: symbol)
        return cached > 0 ? cached : 0
    }
    
    private var currentQuoteSymbol: String { selectedQuote }

    // Chart source & sheets
    @State private var selectedChartSource: ChartSource
    @State private var isChartSourceInitialized: Bool = true  // Start true - chart source is persisted via AppStorage
    @State private var showTimeframePicker: Bool = false
    @State private var showIndicatorMenu: Bool = false
    @State private var showTechnicals: Bool = false

    // Map preferences to TradingView study identifiers (synced across views)
    private var tvStudies: [String] {
        // Reference tvIndicatorsRaw to ensure SwiftUI detects changes and triggers view update
        _ = tvIndicatorsRaw
        return TVStudiesMapper.buildCurrentStudies()
    }

    // Persisted indicator set helpers
    private var tvIndicatorSet: Set<IndicatorType> {
        let parsed = parseIndicatorSet(from: tvIndicatorsRaw)
        if !parsed.isEmpty { return parsed }
        // Fallback to legacy boolean prefs if no set persisted yet
        var base: Set<IndicatorType> = []
        if prefShowVolume { base.insert(.volume) }
        if prefSMAEnabled { base.insert(.sma) }
        if prefEMAEnabled { base.insert(.ema) }
        return base
    }

    private func keyForIndicator(_ ind: IndicatorType) -> String {
        switch ind {
        case .volume: return "volume"
        case .sma: return "sma"
        case .ema: return "ema"
        case .bb: return "bb"
        case .rsi: return "rsi"
        case .macd: return "macd"
        case .stoch: return "stoch"
        case .vwap: return "vwap"
        case .ichimoku: return "ichimoku"
        case .atr: return "atr"
        case .obv: return "obv"
        case .mfi: return "mfi"
        }
    }

    private func parseIndicatorSet(from raw: String) -> Set<IndicatorType> {
        let keys = raw.split(separator: ",").map { String($0) }
        var out = Set<IndicatorType>()
        for k in keys {
            switch k {
            case "volume": out.insert(.volume)
            case "sma": out.insert(.sma)
            case "ema": out.insert(.ema)
            case "bb": out.insert(.bb)
            case "rsi": out.insert(.rsi)
            case "macd": out.insert(.macd)
            case "stoch": out.insert(.stoch)
            case "vwap": out.insert(.vwap)
            case "ichimoku": out.insert(.ichimoku)
            case "atr": out.insert(.atr)
            case "obv": out.insert(.obv)
            case "mfi": out.insert(.mfi)
            default: break
            }
        }
        return out
    }

    private func serializeIndicatorSet(_ set: Set<IndicatorType>) -> String {
        // Keep a deterministic order so diffs are stable
        let order: [IndicatorType] = [.volume, .sma, .ema, .bb, .rsi, .macd, .stoch, .vwap, .ichimoku, .atr, .obv, .mfi]
        let keys: [String] = order.compactMap { set.contains($0) ? keyForIndicator($0) : nil }
        return keys.joined(separator: ",")
    }

    private func syncTVIndicatorsFromBooleans() {
        var set = parseIndicatorSet(from: tvIndicatorsRaw)
        if prefShowVolume { set.insert(.volume) } else { set.remove(.volume) }
        if prefSMAEnabled { set.insert(.sma) } else { set.remove(.sma) }
        if prefEMAEnabled { set.insert(.ema) } else { set.remove(.ema) }
        tvIndicatorsRaw = serializeIndicatorSet(set)
    }

    @ViewBuilder
    private var tradeContent: some View {
        GeometryReader { geometry in
            // FIX: Guard against zero-frame GeometryReader on LazyView cold start
            // This can happen when the app returns from background after a long period
            // and LazyView initializes TradeView - the first layout pass may return zero size
            let hasValidFrame = geometry.size.width > 0 && geometry.size.height > 0
            
            if hasValidFrame || didCompleteInitialLayout {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            navBar
                            
                            // Show banner if no exchange connected
                            exchangeConnectionBanner

                            priceRow

                            chartSection
                                // PERFORMANCE: Use symbol-only ID to prevent full view recreation on timeframe switch
                                .id("chartSection-\(symbol)")
                                .padding(.top, 0)
                                .padding(.bottom, 2) // tightened spacing below chart card
                                .padding(.horizontal, contentHPad) // standardized horizontal padding
                                .transaction { $0.animation = nil }  // disable animation on id change

                            // Order entry form - gated for Free users who don't have paper trading access
                            lockedTradeFormWrapper
                                .id("tradeFormSection")
                                .padding(.top, 6)
                                .padding(.horizontal, contentHPad)

                            orderBookSection
                            
                            // Open Orders Section - shows pending limit orders for the current symbol
                            OpenOrdersSection(symbol: symbol)
                                .padding(.horizontal, contentHPad)
                                .padding(.top, 10)
                                .padding(.bottom, 16)
                            
                            // Extra padding when keyboard is visible to ensure content can scroll above keyboard
                            if keyboardHeight > 0 {
                                Spacer()
                                    .frame(height: 80)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                        .scrollDismissesKeyboard(.interactively)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            // Use simultaneousGesture to allow child buttons to receive taps
                            if isQuantityFocused {
                                isQuantityFocused = false
                            }
                        })
                    }
                    .scrollBounceBehavior(.basedOnSize) // Limits horizontal bounce on vertical scroll
                    // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + KVO tracking
                    .withUIKitScrollBridge()
                    .onChange(of: isQuantityFocused) { _, focused in
                        // Defer to avoid "Modifying state during view update"
                        DispatchQueue.main.async {
                            if focused {
                                // Scroll to the trade form when quantity field is focused
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    scrollProxy.scrollTo("tradeFormSection", anchor: .center)
                                }
                            }
                        }
                    }
                    .onAppear {
                        // Mark initial layout as complete once we have a valid frame
                        if hasValidFrame && !didCompleteInitialLayout {
                            DispatchQueue.main.async {
                                didCompleteInitialLayout = true
                            }
                        }
                    }
                }
            } else {
                // FIX: Show a loading placeholder while waiting for valid geometry
                // This prevents the blank gold screen bug on cold start
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(AppTradingMode.paper.color)
                    Text("Loading Trading...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // Force a layout refresh after a brief delay
                    // This ensures the GeometryReader gets recalculated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !didCompleteInitialLayout {
                            didCompleteInitialLayout = true
                        }
                    }
                }
            }
        }
        .clipped() // Prevents horizontal overflow when scrolling
    }

    // MARK: - Extracted lifecycle handlers to reduce type-checker burden
    private func handleInitialAppear() {
        // Record trading view for ad cooldown (user is actively trading, don't interrupt)
        AdManager.shared.recordChartViewShown()
        
        // SAFETY: Auto-enable paper trading when live trading is disabled at app config level
        // This ensures users are in paper trading mode for regulatory/legal compliance
        // For Free users without Paper Trading access, fall back to Demo Mode
        // Only perform this check on FIRST appearance to avoid auto-enabling Demo mode
        // when user navigates back from other screens (e.g., exchange connection page)
        if !hasPerformedInitialSetup {
            hasPerformedInitialSetup = true
            
            // Only apply auto-mode logic if user doesn't have connected accounts
            // Users with real portfolios should stay in their current state
            let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
            
            if !AppConfig.liveTradingEnabled && !PaperTradingManager.isEnabled && !hasConnectedAccounts {
                if PaperTradingManager.shared.hasAccess {
                    PaperTradingManager.shared.enablePaperTrading()
                } else if !DemoModeManager.isEnabled {
                    // Free users without Paper Trading access and no connected accounts
                    // can use Demo Mode to explore
                    DemoModeManager.shared.enableDemoMode()
                }
            }
        }
        
        // Check for pending trade config from AI Chat (immediate - user initiated)
        applyPendingTradeConfig()
        
        // If AI explicitly requested Spot Trade routing, force root destination.
        if appState.shouldShowSpotTradeFromAI {
            resetToSpotTradeRootFromAI()
            appState.shouldShowSpotTradeFromAI = false
        }
        
        // PRICE CONSISTENCY: Load saved exchange preference for the current symbol
        // This ensures the trading page uses the same exchange the user previously selected
        if selectedPairExchange == nil, let savedExchange = AppSettings.preferredExchange(for: symbol) {
            selectedPairExchange = savedExchange
            updateTVRouting()
        }
        
        // Set non-critical states that don't affect initial layout
        showOrderBook = true
        coinImageURL = imageURLForSymbol(symbol)
        isActiveTab = (appState.selectedTab == .trade)
        chartLastLoadedAt = nil
        
        // Background tasks that don't affect layout (immediate)
        Task { @MainActor in
            if tvIndicatorsRaw.isEmpty { syncTVIndicatorsFromBooleans() }
            #if os(iOS)
            let tick = UserDefaults.standard.double(forKey: "Haptics.TickInterval")
            let major = UserDefaults.standard.double(forKey: "Haptics.MajorInterval")
            if tick > 0 { ChartHaptics.shared.minTickInterval = tick }
            if major > 0 { ChartHaptics.shared.minMajorInterval = major }
            #endif
            if UserDefaults.standard.object(forKey: "Settings.DarkMode") != nil {
                let desired = settingsDarkMode ? "dark" : "light"
                if appAppearanceRaw != desired { appAppearanceRaw = desired }
            }
        }
        
        // TAB FREEZE FIX v5.1: Do NOT mount TradingView WebKit on every trade-tab entry.
        // Mount only when TradingView source is actually selected, otherwise WebKit process
        // startup (GPU/WebContent/Networking) can freeze tab transitions.
        if selectedChartSource == .trading && !mountTradingView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                mountTradingView = true
                updateTVRouting()
            }
        }
        
        // TAB FREEZE FIX v5.2: Defer initial order-book startup slightly so the first
        // Trade tab transition can complete before network/WS setup begins.
        if appState.selectedTab == .trade {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard appState.selectedTab == .trade else { return }
                orderBookVM.startFetchingOrderBook(for: symbol, exchange: selectedPairExchange)
                refreshRecommendedPriceGrouping(for: symbol)
            }
        }
        
        // Phase 2 (150ms): Refresh connected exchanges (slight delay, non-critical)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            guard appState.selectedTab == .trade else { return }
            vm.refreshConnectedExchanges()
        }
        
        // Phase 3 (500ms): Pre-warm technicals cache (lowest priority)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard appState.selectedTab == .trade else { return }
            TechnicalsViewModel.preWarmCache(symbol: symbol, interval: .oneDay)
        }
        
        // Convert pending USD amount to quantity if price is already available
        // (e.g., from cached price when opening from AI chat)
        if pendingUSDAmount != nil && !hasConvertedUSDAmount {
            Task { @MainActor in
                // Give price a moment to load, then try conversion
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                convertPendingUSDToQuantity()
            }
        }
    }
    
    /// Force AI-initiated spot-trade CTA flows back to the executable spot form root.
    private func resetToSpotTradeRootFromAI() {
        appState.tradeNavPath = NavigationPath()
        showSmartTradingHub = false
        showStrategiesHub = false
        showBotHubFromSocial = false
        showTradingBotFromAI = false
        showPredictionBotFromAI = false
        showDerivativesBotFromAI = false
        applyPendingTradeConfig()
    }

    private func handleSymbolChange(_ newSymbol: String) {
        // CRITICAL: Reset price immediately BEFORE updating the symbol.
        // The $currentSymbol publisher has a 150ms debounce, during which the old
        // price persists. Without this reset, a trade could execute at the WRONG
        // coin's price (e.g., BTC price used for an ETH trade).
        vm.currentPrice = 0
        
        // Update synchronous state immediately
        vm.currentSymbol = newSymbol
        priceVM.updateSymbol(newSymbol)
        orderBookVM.stopFetching()
        orderBookVM.startFetchingOrderBook(for: newSymbol, exchange: selectedPairExchange)
        refreshRecommendedPriceGrouping(for: newSymbol)
        vm.fetchBalance(for: newSymbol)
        coinImageURL = imageURLForSymbol(newSymbol)
        updateTVRouting()
        
        // Pre-warm technicals cache on background thread
        Task { @MainActor in
            TechnicalsViewModel.preWarmCache(symbol: newSymbol, interval: .oneDay)
        }
    }

    private func handleIntervalChange(_ newInterval: ChartInterval) {
        // Store the interval preference
        storedIntervalRaw = newInterval.rawValue
    }

    // MARK: - Extracted background view
    @ViewBuilder
    private var tradeBackground: some View {
        ZStack {
            pageBackground.ignoresSafeArea()
            FuturisticBackground()
                .ignoresSafeArea(edges: [.leading, .trailing])
                .opacity(colorScheme == .dark ? 1 : 0.0)
        }
    }

    // MARK: - Extracted keyboard submit button
    @ViewBuilder
    private var keyboardSubmitButton: some View {
        let disabled = isSubmitDisabledGlobal
        let isSell = (selectedSide == .sell)
        let isPaperMode = PaperTradingManager.isEnabled
        Button {
            guard !disabled else { return }
            
            // Store the pending trade action
            pendingTradeAction = { [selectedSide, symbol, orderType, quantity, limitPrice, stopPrice] in
                vm.executeTrade(side: selectedSide, symbol: symbol, orderType: orderType, quantity: quantity, limitPriceStr: limitPrice, stopPriceStr: stopPrice)
            }
            
            // Paper trading: show confirmation dialog (no ToS/risk needed for simulated money)
            if isPaperMode {
                showingPaperTradeConfirmation = true
                return
            }
            
            // Step 1: Check if user has accepted Terms of Service
            if TradingRiskAcknowledgmentManager.shared.needsToSAcceptance {
                showingToSAcceptance = true
                return
            }
            
            // Step 2: Check if user has acknowledged trading risks
            if !TradingRiskAcknowledgmentManager.shared.hasValidAcknowledgment {
                showingRiskAcknowledgment = true
                return
            }
            
            // Step 3: Show pre-trade confirmation for real trades (every time)
            showingPreTradeConfirmation = true
        } label: {
            ZStack {
                // LIGHT MODE FIX: Use green Buy gradient in light mode, matching main submit button
                let kbGreenBuyGradient = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 0.25, green: 0.78, blue: 0.42), location: 0.0),
                        .init(color: Color(red: 0.18, green: 0.68, blue: 0.34), location: 0.52),
                        .init(color: Color(red: 0.12, green: 0.55, blue: 0.26), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                let kbBuyGradient = colorScheme == .dark
                    ? AdaptiveGradients.goldButton(isDark: true)
                    : kbGreenBuyGradient
                let kbBuyStroke = colorScheme == .dark
                    ? AdaptiveGradients.ctaRimStroke(isDark: true)
                    : LinearGradient(colors: [Color.white.opacity(0.35), Color(red: 0.10, green: 0.50, blue: 0.22).opacity(0.25)], startPoint: .top, endPoint: .bottom)
                
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSell ? redButtonGradient : kbBuyGradient)
                    .overlay(
                        LinearGradient(colors: [(isSell ? Color.white.opacity(0.10) : Color.white.opacity(0.16)), Color.clear], startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSell ? ctaRimStrokeGradientRed : kbBuyStroke, lineWidth: 1)
                    )
                    .overlay(
                        AdaptiveGradients.ctaBottomShade(isDark: colorScheme == .dark)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                Text("\(selectedSide.rawValue.capitalized) \(symbol.uppercased())")
                    .font(.headline)
                    .fontWeight(.semibold)
                    // LIGHT MODE FIX: White text on green Buy button in light mode
                    .foregroundColor(isSell ? .white : (colorScheme == .dark ? .black.opacity(0.96) : .white))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("\(selectedSide.rawValue.capitalized) \(symbol.uppercased())")
        .accessibilityHint("Submits a \(selectedSide.rawValue) order")
        .buttonStyle(GlowButtonStyle(isSell: isSell))
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Body with lifecycle modifiers
    @ViewBuilder
    private var bodyWithLifecycle: some View {
        tradeContent
            .modifier(PreferredSchemeModifier(mode: appAppearance))
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .background(tradeBackground)
            .safeAreaInset(edge: .top) {
                Rectangle()
                    .fill(DS.Neutral.divider(0.08))
                    .opacity(colorScheme == .dark ? 1 : 0)
                    .frame(height: 1)
                    .background(colorScheme == .dark ? pageBackground : Color.clear)
            }
            .safeAreaInset(edge: .bottom) {
                if keyboardHeight > 0 {
                    keyboardSubmitButton
                } else {
                    EmptyView()
                }
            }
            // Tap anywhere to dismiss keyboard
            .onTapGesture {
                isQuantityFocused = false
            }
    }

    // MARK: - Order book modal content (extracted to reduce body complexity)
    @ViewBuilder
    private var orderBookModalContent: some View {
        VStack {
            HStack {
                Text("Order Book")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                Spacer()
                Button("Close") { isOrderBookModalPresented = false }
                    .foregroundColor(DS.Adaptive.gold)
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            // UI FIX: Use design system colors for consistency
                            Text("Bids").font(.headline).foregroundColor(DS.Colors.bid)
                            ForEach(orderBookVM.bids, id: \.price) { bid in
                                Text("\(bid.price) | \(bid.qty)").foregroundColor(.primary).font(.caption)
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            // UI FIX: Use design system colors for consistency
                            Text("Asks").font(.headline).foregroundColor(DS.Colors.ask)
                            ForEach(orderBookVM.asks, id: \.price) { ask in
                                Text("\(ask.price) | \(ask.qty)").foregroundColor(.primary).font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(pageBackground)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    // MARK: - Timeframe overlay (extracted) - uses anchored grid menu
    @ViewBuilder
    private var timeframeOverlay: some View {
        if showTimeframePopover {
            CSAnchoredGridMenu(
                isPresented: $showTimeframePopover,
                anchorRect: timeframeButtonFrame,
                items: supportedIntervals,  // Use curated list instead of all cases
                selectedItem: selectedInterval,
                titleForItem: { $0.rawValue },
                onSelect: { selectedInterval = $0 },
                columns: 3,
                preferredWidth: 240,
                edgePadding: 16,
                title: "Timeframe"
            )
        }
    }

    // MARK: - Body layer 1: Core with lifecycle
    @ViewBuilder
    private var bodyLayer1: some View {
        bodyWithLifecycle
            .onAppear { handleInitialAppear() }
            .onAppear { Task { @MainActor in updateTVRouting() } }
            .onDisappear {
                priceVM.stopPolling()
                orderBookVM.stopFetching()
            }
            .onReceive(keyboardPublisher) { height in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    keyboardHeight = height
                }
            }
    }

    // MARK: - Body layer 2a: App-state onChange handlers
    @ViewBuilder
    private var bodyLayer2a: some View {
        bodyLayer1
            .onChange(of: appState.selectedTab) { _, newTab in
                // PERFORMANCE: Cancel any pending debounced work
                tabSwitchDebounceWork?.cancel()
                
                // Update tab active state immediately for responsive UI
                isActiveTab = (newTab == .trade)
                
                if newTab == .trade {
                    // Check for pending trade config immediately (from AI Chat)
                    applyPendingTradeConfig()
                    
                    // TAB FREEZE FIX v5.1: Slightly defer network-heavy startup to let
                    // the tab transition finish first and avoid UI pause on switch.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        guard appState.selectedTab == .trade else { return }
                        orderBookVM.startFetchingOrderBook(for: symbol, exchange: selectedPairExchange)
                    }
                    vm.refreshConnectedExchanges()
                } else {
                    // Stop operations when leaving tab (data is cached for instant reload)
                    orderBookVM.stopFetching()
                }
            }
            .onChange(of: appState.pendingTradeConfig) { _, newConfig in
                // Apply trade config immediately when it's set (e.g., from AI Chat)
                if newConfig != nil, appState.selectedTab == .trade {
                    Task { @MainActor in
                        applyPendingTradeConfig()
                    }
                }
            }
            .onChange(of: appState.shouldShowSpotTradeFromAI) { _, shouldRouteToSpot in
                guard shouldRouteToSpot else { return }
                Task { @MainActor in
                    resetToSpotTradeRootFromAI()
                    appState.shouldShowSpotTradeFromAI = false
                }
            }
            .onChange(of: appState.shouldShowDerivativesBot) { _, shouldShow in
                // Navigate to derivatives bot when triggered from AI Chat
                if shouldShow {
                    Task { @MainActor in
                        showDerivativesBotFromAI = true
                        appState.shouldShowDerivativesBot = false
                    }
                }
            }
            .onChange(of: appState.shouldShowTradingBot) { _, shouldShow in
                // Navigate to trading bot when triggered from AI Chat
                if shouldShow {
                    Task { @MainActor in
                        showTradingBotFromAI = true
                        appState.shouldShowTradingBot = false
                    }
                }
            }
            .onChange(of: appState.shouldShowPredictionBot) { _, shouldShow in
                // Navigate to prediction bot when triggered from AI Chat
                if shouldShow {
                    Task { @MainActor in
                        showPredictionBotFromAI = true
                        appState.shouldShowPredictionBot = false
                    }
                }
            }
            // Return to previous tab (e.g. AI Chat) when user presses back from AI-triggered bot views
            .onChange(of: showTradingBotFromAI) { _, isShowing in
                if !isShowing, let previousTab = appState.tabBeforeBotCreation {
                    appState.tabBeforeBotCreation = nil
                    Task { @MainActor in
                        appState.selectedTab = previousTab
                    }
                }
            }
            .onChange(of: showDerivativesBotFromAI) { _, isShowing in
                if !isShowing, let previousTab = appState.tabBeforeBotCreation {
                    appState.tabBeforeBotCreation = nil
                    Task { @MainActor in
                        appState.selectedTab = previousTab
                    }
                }
            }
            .onChange(of: showPredictionBotFromAI) { _, isShowing in
                if !isShowing, let previousTab = appState.tabBeforeBotCreation {
                    appState.tabBeforeBotCreation = nil
                    Task { @MainActor in
                        appState.selectedTab = previousTab
                    }
                }
            }
    }

    // MARK: - Body layer 2b: Data/scene onChange handlers
    @ViewBuilder
    private var bodyLayer2: some View {
        bodyLayer2a
            .onChange(of: selectedChartSource) { _, newSource in
                Task { @MainActor in
                    storedChartSourceRaw = (newSource == .trading) ? "trading" : "sage"
                    if newSource == .trading {
                        mountTradingView = true
                        updateTVRouting()
                    }
                }
            }
            .onChange(of: symbol) { _, newValue in handleSymbolChange(newValue) }
            .onChange(of: selectedInterval) { _, newValue in handleIntervalChange(newValue) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // PERFORMANCE: Only restart services if background for >2 seconds
                    // This prevents unnecessary restarts for brief interruptions (notifications, etc.)
                    let wasBackgroundLongEnough: Bool
                    if let bgTime = lastBackgroundAt {
                        wasBackgroundLongEnough = Date().timeIntervalSince(bgTime) > 2.0
                    } else {
                        wasBackgroundLongEnough = false // First appearance, don't restart
                    }
                    
                    if isActiveTab && wasBackgroundLongEnough {
                        // PRICE CONSISTENCY FIX: Reduced delay from 200ms to 50ms
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                            guard appState.selectedTab == .trade else { return }
                            orderBookVM.startFetchingOrderBook(for: symbol, exchange: selectedPairExchange)
                            vm.refreshConnectedExchanges()
                        }
                    }
                    lastBackgroundAt = nil // Reset background timestamp
                    
                case .inactive, .background:
                    lastBackgroundAt = Date()
                    orderBookVM.stopFetching()
                    
                @unknown default: break
                }
            }
            .onChange(of: marketVM.allCoins.count) { _, _ in
                Task { @MainActor in coinImageURL = imageURLForSymbol(symbol) }
            }
            .onChange(of: demoModeManager.isDemoMode) { _, _ in
                // When demo mode changes, reset exchange selection to reflect actual connected exchanges
                Task { @MainActor in
                    vm.resetExchangeSelectionIfNeeded()
                }
            }
            .onChange(of: paperTradingManager.isPaperTradingEnabled) { _, _ in
                // When paper trading mode changes, refresh balances
                Task { @MainActor in
                    vm.refreshBalances()
                }
            }
            .onChange(of: appState.shouldShowBotHub) { _, shouldShow in
                // Navigate to BotHub from Social tab copy
                if shouldShow {
                    Task { @MainActor in
                        appState.shouldShowBotHub = false
                        showBotHubFromSocial = true
                    }
                }
            }
    }

    // MARK: - Body layer 3: Add sheets
    @ViewBuilder
    private var bodyLayer3: some View {
        bodyLayer2
            .sheet(isPresented: $isCoinPickerPresented) {
                // Use appropriate picker based on trading mode:
                // - Live trading enabled: Full exchange-specific pair picker
                // - Everyone else (paper trading, regular users): Simplified coin picker
                if AppConfig.liveTradingEnabled {
                    // Full TradingPairPickerView for live trading mode
                    TradingPairPickerView(
                        selectedPair: $symbol,
                        selectedQuote: $selectedQuote,
                        selectedExchange: $selectedPairExchange
                    ) { pair in
                        Task { @MainActor in
                            symbol = pair.baseSymbol
                            selectedQuote = pair.quoteSymbol
                            selectedPairExchange = pair.exchangeID
                            // CRITICAL: Reset price before changing symbol to prevent stale cross-symbol prices
                            vm.currentPrice = 0
                            vm.currentSymbol = pair.baseSymbol
                            
                            // PRICE CONSISTENCY: Save exchange preference for this coin
                            // This ensures the same exchange is used across the app (trading, market, watchlist)
                            AppSettings.setPreferredExchange(for: pair.baseSymbol, exchangeID: pair.exchangeID)
                            
                            // Update tvQuote for TradingView
                            tvQuote = pair.quoteSymbol
                            updateTVRouting()
                            
                            // Handle exchange selection based on pair tradability
                            if pair.isTradable {
                                // Pair is from a connected exchange - select it directly
                                if let exchange = TradingExchange(rawValue: pair.exchangeID) {
                                    vm.selectedExchange = exchange
                                }
                            } else {
                                // View-only pair (Kraken/KuCoin or unconnected exchange)
                                // Keep the current exchange selection if user has one connected
                                // This allows viewing market data while trading on a connected exchange
                                // The user can still trade the same base asset on their connected exchange
                                if vm.selectedExchange == nil && vm.hasConnectedExchange {
                                    // Auto-select the default exchange for trading convenience
                                    vm.selectedExchange = TradingCredentialsManager.shared.defaultExchange
                                }
                                // Note: Price display will use composite/aggregate pricing
                                // Trading will use the selected connected exchange
                            }
                            
                            orderBookVM.startFetchingOrderBook(for: pair.baseSymbol, exchange: pair.exchangeID)
                        }
                    }
                } else {
                    // Unified coin picker for regular users (portfolio/paper trading)
                    CoinPickerSheet(selectedSymbol: $symbol) { coin in
                        // LOGO FIX: Set quote/exchange state SYNCHRONOUSLY (not in Task)
                        // so it's ready BEFORE CoinPickerSheet.selectCoin updates the symbol binding.
                        // The binding change triggers .onChange(of: symbol) -> handleSymbolChange(),
                        // which needs these values to be set correctly.
                        selectedQuote = "USD"
                        selectedPairExchange = nil
                        tvQuote = "USD"
                        // Note: symbol is set via the $symbol binding in CoinPickerSheet.selectCoin
                        // No need to set it again here — the binding handles it.
                    }
                }
            }
            .sheet(isPresented: $isOrderBookModalPresented) { orderBookModalContent }
            .sheet(isPresented: $showIndicatorMenu) {
                ChartIndicatorMenu(isPresented: $showIndicatorMenu, isUsingNativeChart: selectedChartSource == .sage)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTechnicals) {
                NavigationStack {
                    let tvSym = "\(tvExchangePrefix):\(symbol.uppercased())\(tvQuote)"
                    let theme = (colorScheme == .dark) ? "Dark" : "Light"
                    TechnicalsDetailNativeView(symbol: symbol.uppercased(), tvSymbol: tvSym, tvTheme: theme, currentPrice: displayedPrice)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showBotSelectionSheet) {
                BotSelectionSheet(
                    isPresented: $showBotSelectionSheet,
                    side: selectedSide,
                    orderType: orderType,
                    quantity: Double(quantity) ?? 0.0,
                    slippage: 0.5  // Default slippage for bots
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            // Paper Trading settings sheet - presented modally to avoid navigation confusion
            .sheet(isPresented: $showPaperTradingSettings) {
                NavigationStack {
                    PaperTradingSettingsView()
                }
                .presentationDragIndicator(.visible)
            }
            // Trade execution upgrade prompt
            .unifiedPaywallSheet(feature: .tradeExecution, isPresented: $vm.showTradeExecutionUpgradePrompt)
            // Terms of Service acceptance sheet (shown first for real trades)
            .sheet(isPresented: $showingToSAcceptance) {
                TermsOfServiceAcceptanceView(
                    onAccept: {
                        // After ToS acceptance, check if risk acknowledgment is needed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !TradingRiskAcknowledgmentManager.shared.hasValidAcknowledgment {
                                showingRiskAcknowledgment = true
                            } else {
                                showingPreTradeConfirmation = true
                            }
                        }
                    },
                    onDecline: {
                        pendingTradeAction = nil
                    }
                )
            }
            // Trading risk acknowledgment sheet (shown after ToS acceptance)
            .sheet(isPresented: $showingRiskAcknowledgment) {
                TradingRiskAcknowledgmentView(
                    onAcknowledge: {
                        // After acknowledging risks, show pre-trade confirmation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingPreTradeConfirmation = true
                        }
                    },
                    onDecline: {
                        pendingTradeAction = nil
                    }
                )
            }
            // Pre-trade confirmation dialog (shown every time for real trades) – detailed summary
            .alert("⚠️ Review Real Trade", isPresented: $showingPreTradeConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingTradeAction = nil
                }
                Button(confirmButtonLabel(isPaper: false), role: .destructive) {
                    // Haptic feedback for trade execution
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    #endif
                    // Log the trade confirmation to audit trail
                    TradingRiskAcknowledgmentManager.shared.logTradeConfirmation(
                        symbol: symbol,
                        side: selectedSide.rawValue,
                        quantity: Double(quantity) ?? 0,
                        price: vm.currentPrice
                    )
                    pendingTradeAction?()
                    pendingTradeAction = nil
                }
            } message: {
                Text(orderSummaryText(isPaper: false))
            }
            // Paper trade confirmation dialog – detailed summary (Coinbase-style)
            .alert("Review Paper Trade", isPresented: $showingPaperTradeConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingTradeAction = nil
                }
                Button(confirmButtonLabel(isPaper: true)) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    pendingTradeAction?()
                    pendingTradeAction = nil
                }
            } message: {
                Text(orderSummaryText(isPaper: true))
            }
            // Navigation to BotHub from Social tab copy
            .navigationDestination(isPresented: $showBotHubFromSocial) {
                BotHubView(highlightBotId: appState.pendingBotNavigation)
                    .onDisappear {
                        // Clear the pending navigation when leaving
                        appState.pendingBotNavigation = nil
                    }
            }
            // Navigation to Smart Trading Hub (unified AI trading assistant)
            .navigationDestination(isPresented: $showSmartTradingHub) {
                SmartTradingHub()
            }
            // Navigation to Smart Trading Hub with Strategies mode pre-selected
            .navigationDestination(isPresented: $showStrategiesHub) {
                SmartTradingHub(initialMode: .strategies)
            }
            .navigationDestination(isPresented: $showDerivativesBotFromAI) {
                DerivativesBotView()
            }
            .navigationDestination(isPresented: $showTradingBotFromAI) {
                TradingBotView()
            }
            .navigationDestination(isPresented: $showPredictionBotFromAI) {
                PredictionBotView()
            }
    }

    var body: some View {
        bodyLayer3
            .overlay { timeframeOverlay }
            .animation(.easeInOut(duration: 0.2), value: showTimeframePopover)
            .onChange(of: prefShowVolume) { _, _ in Task { @MainActor in syncTVIndicatorsFromBooleans() } }
            .onChange(of: prefSMAEnabled) { _, _ in Task { @MainActor in syncTVIndicatorsFromBooleans() } }
            .onChange(of: prefEMAEnabled) { _, _ in Task { @MainActor in syncTVIndicatorsFromBooleans() } }
            .onChange(of: settingsDarkMode) { _, v in
                // Instant theme sync - no animations
                withAnimation(nil) {
                    let desired = v ? "dark" : "light"
                    if appAppearanceRaw != desired { appAppearanceRaw = desired }
                }
            }
            .onChange(of: appAppearanceRaw) { _, newVal in
                // Instant theme sync - no animations
                withAnimation(nil) {
                    let desired = (newVal == "dark")
                    if settingsDarkMode != desired { settingsDarkMode = desired }
                }
            }
            // Order confirmation alert
            .alert("Order Submitted", isPresented: $vm.showOrderConfirmation) {
                Button("OK", role: .cancel) {
                    vm.showOrderConfirmation = false
                    // Reset form state after successful trade so user sees fresh state
                    quantity = ""
                    sliderValue = 0
                    // Refresh balances to ensure UI shows updated values
                    vm.refreshBalances()
                }
            } message: {
                if let result = vm.lastOrderResult {
                    Text(orderConfirmationMessage(result))
                } else {
                    Text("Your order has been submitted successfully.")
                }
            }
            // Native iOS pop gesture (always enabled for navigation consistency)
            .enableInteractivePopGesture()
            // Edge swipe to dismiss when presented as subpage (with back button)
            .edgeSwipeToDismissIf(showBackButton, onDismiss: { dismiss() })
    }
    
    // MARK: - Order Confirmation Helpers
    
    /// Build a detailed order summary string for pre-trade confirmation dialogs.
    /// Matches the detail level of Coinbase/Binance confirmation screens:
    /// order type, side, quantity, price, fee, total, and balance impact.
    private func orderSummaryText(isPaper: Bool) -> String {
        let side = selectedSide == .buy ? "BUY" : "SELL"
        let sym = symbol.uppercased()
        let qty = Double(quantity) ?? 0
        let price = vm.tradingPrice > 0 ? vm.tradingPrice : vm.currentPrice
        
        // Determine effective price based on order type
        let effectivePrice: Double
        let priceLabel: String
        switch orderType {
        case .market:
            effectivePrice = price
            priceLabel = "Market Price"
        case .limit:
            effectivePrice = Double(limitPrice) ?? price
            priceLabel = "Limit Price"
        case .stop, .stopLoss:
            effectivePrice = Double(stopPrice) ?? price
            priceLabel = "Stop Price"
        case .stopLimit:
            effectivePrice = Double(limitPrice) ?? price
            priceLabel = "Stop-Limit Price"
        }

        let subtotal = qty * effectivePrice
        let feeRate = vm.currentFeeRate
        let fee = subtotal * feeRate
        let feePercent = String(format: "%.2f", feeRate * 100)
        let total = selectedSide == .buy ? subtotal + fee : subtotal - fee

        // Order type display name
        let orderTypeName: String = {
            switch orderType {
            case .market:    return "Market Order"
            case .limit:     return "Limit Order"
            case .stop, .stopLoss: return "Stop Order"
            case .stopLimit: return "Stop-Limit Order"
            }
        }()

        var lines: [String] = []
        lines.append("\(side) \(quantity) \(sym)")
        lines.append("Order Type: \(orderTypeName)")
        lines.append("\(priceLabel): \(formatUSD(effectivePrice))")

        // Show stop price separately for stop-limit orders
        if orderType == .stopLimit, let sp = Double(stopPrice), sp > 0 {
            lines.append("Stop Trigger: \(formatUSD(sp))")
        }

        lines.append("")
        lines.append("Subtotal: \(formatUSD(subtotal))")
        lines.append("Fee (\(feePercent)%): \(formatUSD(fee))")

        if selectedSide == .buy {
            lines.append("Total Cost: \(formatUSD(total))")
        } else {
            lines.append("You Receive: \(formatUSD(total))")
        }

        if isPaper {
            lines.append("")
            lines.append("This is a simulated trade using virtual funds. No real money is involved.")
        } else {
            lines.append("")
            lines.append("⚠️ This will execute a REAL trade on your connected exchange. This action cannot be undone. You may lose money.")
        }

        return lines.joined(separator: "\n")
    }

    /// Format the confirm button label to include the dollar amount (Coinbase-style).
    /// e.g. "Buy $34,658.50 BTC" or "Sell 0.5 BTC ($34,623.88)"
    private func confirmButtonLabel(isPaper: Bool) -> String {
        let side = selectedSide == .buy ? "Buy" : "Sell"
        let sym = symbol.uppercased()
        let qty = Double(quantity) ?? 0
        let price = vm.tradingPrice > 0 ? vm.tradingPrice : vm.currentPrice
        let effectivePrice: Double = {
            switch orderType {
            case .limit, .stopLimit: return Double(limitPrice) ?? price
            case .stop, .stopLoss: return Double(stopPrice) ?? price
            case .market: return price
            }
        }()
        let total = qty * effectivePrice
        let prefix = isPaper ? "Paper " : ""
        return "\(prefix)\(side) \(formatUSD(total)) \(sym)"
    }
    
    // Helper to format order confirmation message
    private func orderConfirmationMessage(_ result: OrderResult) -> String {
        var message = "Your order has been submitted to \(result.exchange.capitalized)."
        if let orderId = result.orderId {
            message += "\n\nOrder ID: \(orderId)"
        }
        if let status = result.status {
            message += "\nStatus: \(status.rawValue)"
        }
        if let filled = result.filledQuantity, filled > 0 {
            message += "\nFilled: \(String(format: "%.6f", filled))"
        }
        if let avgPrice = result.averagePrice, avgPrice > 0 {
            message += "\nAvg Price: $\(String(format: "%.2f", avgPrice))"
        }
        return message
    }
    
    // MARK: - Nav Bar
private var navBar: some View {
    let isCompact = (self.horizontalSizeClass ?? .compact) == .compact
    let hPadding: CGFloat = isCompact ? 10 : 16
    let innerSpacing: CGFloat = isCompact ? 8 : 10
    
    // ZStack overlay approach: Coin picker is absolutely centered regardless of
    // different widths on left (back button + badge) vs right (Smart Trade button)
    return ZStack {
        // Left/right elements in an HStack — pushed to edges
        HStack(spacing: isCompact ? 8 : 12) {
            // Leading: Back button (if shown) + Paper Trading badge
            HStack(spacing: innerSpacing) {
                // Back button comes FIRST (far left) - unified gold nav button
                if showBackButton {
                    CSNavButton(
                        icon: "chevron.left",
                        action: { dismiss() },
                        compact: isCompact
                    )
                }
                
                // Paper Trading mode badge - always shown since this page is paper trading focused
                // Live trading is developer-only, so all regular users use paper trading
                paperTradingBadge
            }
            
            Spacer()
            
            // Trailing: Smart Trade button (with Strategies in context menu)
            botsButton
        }
        
        // Center: Coin symbol and picker — absolutely centered in ZStack
        coinPickerButton
    }
    .padding(.horizontal, hPadding)
    .padding(.vertical, isCompact ? 8 : 10)
    .background(colorScheme == .dark ? pageBackground : Color.clear)
}

// MARK: - Paper Trading Badge (always shown - this page is paper trading focused)
@ViewBuilder
private var paperTradingBadge: some View {
    let hasPaperTradingAccess = SubscriptionManager.shared.hasAccess(to: .paperTrading)
    let isPaperTradingEnabled = PaperTradingManager.isEnabled
    let isLiveTradingEnabled = AppConfig.liveTradingEnabled
    
    // Responsive sizing - matched with Smart Trade button for consistency
    let isCompact = (self.horizontalSizeClass ?? .compact) == .compact
    let iconSize: CGFloat = isCompact ? 12 : 13
    let textSize: CGFloat = isCompact ? 12 : 14
    let hPadding: CGFloat = isCompact ? 10 : 14
    let vPadding: CGFloat = isCompact ? 6 : 8
    let spacing: CGFloat = isCompact ? 5 : 6
    
    // LAYOUT FIX: Consistent minimum width to prevent layout shifts when P&L badge appears/disappears
    let minButtonWidth: CGFloat = isCompact ? 95 : 115
    
    // Mode-aware colors from AppTradingMode (single source of truth)
    let paperColor = AppTradingMode.paper.color
    let liveColor = AppTradingMode.liveTrading.color
    
    if isLiveTradingEnabled && !isPaperTradingEnabled {
        // Developer mode with live trading enabled — prominent badge with mode color
        HStack(spacing: spacing) {
            Image(systemName: AppTradingMode.liveTrading.icon)
                .font(.system(size: iconSize, weight: .semibold))
            Text(AppTradingMode.liveTrading.badgeLabel)
                .font(.system(size: textSize, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(liveColor)
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .frame(minWidth: minButtonWidth)
        .background(
            Capsule()
                .fill(liveColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            Capsule()
                .stroke(liveColor.opacity(colorScheme == .dark ? 0.5 : 0.35), lineWidth: 1)
        )
    } else if hasPaperTradingAccess && isPaperTradingEnabled {
        // Pro+ user with paper trading enabled - show active badge with P&L
        let plPercent = PaperTradingManager.shared.calculateProfitLossPercent(prices: getCurrentPricesForPaperTrading())
        let plSign = plPercent >= 0 ? "+" : ""
        let isDark = colorScheme == .dark
        
        // FIX: Use Button + sheet instead of NavigationLink to avoid navigation bar confusion
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showPaperTradingSettings = true
        } label: {
            HStack(spacing: spacing) {
                Image(systemName: AppTradingMode.paper.icon)
                    .font(.system(size: iconSize, weight: .bold))
                Text(AppTradingMode.paper.rawValue)
                    .font(.system(size: textSize, weight: .semibold))
                    .lineLimit(1)
                // P&L indicator - clear red/green coloring for instant readability
                Text("\(plSign)\(String(format: "%.1f", plPercent))%")
                    .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(plPercent >= 0 ? Color.green : Color.red)
                    .padding(.horizontal, isCompact ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(plPercent >= 0
                                ? Color.green.opacity(isDark ? 0.25 : 0.15)
                                : Color.red.opacity(isDark ? 0.25 : 0.15)
                            )
                    )
            }
            .foregroundColor(paperColor)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minWidth: minButtonWidth)
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [
                                    paperColor.opacity(isDark ? 0.18 : 0.10),
                                    paperColor.opacity(isDark ? 0.06 : 0.03),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.06 : 0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .stroke(paperColor.opacity(isDark ? 0.45 : 0.30), lineWidth: isDark ? 1 : 1.2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    } else if hasPaperTradingAccess && !isPaperTradingEnabled {
        // Pro+ user but paper trading not enabled - show enable button (outlined style)
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            Task { @MainActor in
                PaperTradingManager.shared.enablePaperTrading()
                vm.refreshBalances()
            }
        } label: {
            HStack(spacing: spacing) {
                Image(systemName: "doc.text")
                    .font(.system(size: iconSize, weight: .semibold))
                Text("Paper")
                    .font(.system(size: textSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(paperColor)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minWidth: minButtonWidth)
            .background(
                Capsule()
                    .fill(paperColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
            )
            .overlay(
                Capsule()
                    .stroke(paperColor.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    } else {
        // Free user - show locked paper trading badge with lock icon (cleaner than text badge)
        Button {
            showPaperTradingUpgrade = true
        } label: {
            HStack(spacing: isCompact ? 5 : 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundColor(paperColor)
                Text("Paper")
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "lock.fill")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .padding(3.5)
                    .background(
                        Circle()
                            .fill(BrandColors.goldBase)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                            )
                    )
            }
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6))
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minWidth: minButtonWidth)
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: colorScheme == .dark
                                    ? [paperColor.opacity(0.08), Color.white.opacity(0.04)]
                                    : [paperColor.opacity(0.05), Color.black.opacity(0.02)],
                                center: .top,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [paperColor.opacity(0.4), paperColor.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .unifiedPaywallSheet(feature: .paperTrading, isPresented: $showPaperTradingUpgrade)
    }
}

// MARK: - Coin Picker Button (extracted for centering)
private var coinPickerButton: some View {
    // Responsive sizing based on screen width - increased for better visibility
    let isCompact = (self.horizontalSizeClass ?? .compact) == .compact
    let coinSize: CGFloat = isCompact ? 24 : 28
    let textSize: CGFloat = isCompact ? 16 : 18
    let chevronSize: CGFloat = isCompact ? 10 : 12
    let spacing: CGFloat = isCompact ? 5 : 7
    
    // Show full pair format (BTC / USDT) only when live trading is enabled
    // This requires both developer mode AND the live trading toggle to be ON
    // Regular users and paper trading users just see the symbol (e.g., "BTC")
    let isLiveTrading = AppConfig.liveTradingEnabled
    let displayText = isLiveTrading ? "\(symbol.uppercased()) / \(currentQuoteSymbol)" : symbol.uppercased()
    
    return Button {
        isCoinPickerPresented = true
    } label: {
        HStack(spacing: spacing) {
            ZStack {
                // Fallback placeholder (shows immediately if image is nil or slow)
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08))
                    .frame(width: coinSize, height: coinSize)
                    .overlay(
                        Text(String(symbol.prefix(1)))
                            .font(.system(size: coinSize * 0.55, weight: .bold))
                            .foregroundColor(.primary)
                    )
                // Real image on top when available
                // .id(symbol) forces view recreation when switching coins,
                // preventing stale cached images from the previous symbol
                CoinImageView(symbol: symbol, url: coinImageURL, size: coinSize)
                    .id(symbol)
            }
            Text(displayText)
                .font(.system(size: textSize, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.down")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundColor(.primary.opacity(0.6))
        }
    }
    .buttonStyle(PlainButtonStyle())
}

// MARK: - Smart Trade Button (unified trading hub access)
private var botsButton: some View {
    let hasTradingBotsAccess = SubscriptionManager.shared.hasAccess(to: .tradingBots)
    let isDark = colorScheme == .dark
    
    // Responsive sizing based on screen width - increased for better readability
    let isCompact = (self.horizontalSizeClass ?? .compact) == .compact
    let iconSize: CGFloat = isCompact ? 12 : 13
    let textSize: CGFloat = isCompact ? 12 : 14
    let hPadding: CGFloat = isCompact ? 10 : 14
    let vPadding: CGFloat = isCompact ? 6 : 8
    let spacing: CGFloat = isCompact ? 5 : 6
    
    // Simplified styling - purple/blue gradient for paper trading page
    let iconGradient = LinearGradient(
        colors: [Color.purple, Color.blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    let strokeGradient = LinearGradient(
        colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    return Button {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if hasTradingBotsAccess {
            showSmartTradingHub = true
        } else {
            showSmartTradeUpgrade = true
        }
    } label: {
        HStack(spacing: spacing) {
            Image(systemName: "sparkles")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(iconGradient)
            Text(hasTradingBotsAccess ? "Smart Trade" : "Smart")
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            // Lock icon for non-Premium users (cleaner than text badge)
            if !hasTradingBotsAccess {
                Image(systemName: "lock.fill")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(iconGradient)
            }
        }
        .padding(.vertical, vPadding)
        .padding(.horizontal, hPadding)
        .background(
            ZStack {
                // Radial glass fill
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.purple.opacity(isDark ? 0.14 : 0.08),
                                Color.blue.opacity(isDark ? 0.06 : 0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                // Top shine
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.08 : 0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(strokeGradient, lineWidth: isDark ? 1 : 1.2)
        )
    }
    .buttonStyle(PressableButtonStyle())
    .unifiedPaywallSheet(feature: .tradingBots, isPresented: $showSmartTradeUpgrade)
    .contextMenu {
        // Quick access menu for power users (only if they have access)
        if hasTradingBotsAccess {
            Button {
                showSmartTradingHub = true
            } label: {
                Label("Smart Trading Hub", systemImage: "sparkles")
            }
            
            Button {
                showStrategiesHub = true
            } label: {
                Label("Algo Strategies", systemImage: "function")
            }
            
            Button {
                showBotSelectionSheet = true
            } label: {
                Label("Quick Bot Selection", systemImage: "cpu")
            }
        }
    }
}
    
    // MARK: - Exchange Connection Banner
    // NOTE: P&L is now displayed inline in the Paper badge (top nav bar)
    // Pro+ users: No banner needed - P&L is in badge, tap badge for full details
    // Free users: No banner needed - lock overlay on trade form already shows upgrade prompt
    //             This avoids duplicate upgrade prompts which was confusing
    @ViewBuilder
    private var exchangeConnectionBanner: some View {
        // Banner removed for cleaner UX - free users see the lock overlay on the trade form
        // which provides clear upgrade messaging. Pro+ users have P&L in the badge.
        // Having both banner AND lock overlay was redundant and cluttered.
        EmptyView()
    }
    
    // MARK: - Locked Trade Form Wrapper (for Free users)
    @ViewBuilder
    private var lockedTradeFormWrapper: some View {
        let hasPaperTradingAccess = SubscriptionManager.shared.hasAccess(to: .paperTrading)
        
        if hasPaperTradingAccess {
            // Pro+ user - show full trade form
            unlockedTradeForm
        } else {
            lockedTradeForm
        }
    }

    private var unlockedTradeForm: some View {
        tradeFormContent()
    }

    private var lockedTradeForm: some View {
        ZStack {
            lockedTradeBackdrop
            lockedTradeOverlayCard
        }
    }

    private var lockedTradeBackdrop: some View {
        tradeFormContent()
            .disabled(true)
            .opacity(0.25)
            .blur(radius: 2)
    }

    private var lockedTradeOverlayCard: some View {
        VStack(spacing: 14) {
            paperTradingLockIcon
            paperTradingTitleBlock
            paperTradingUpgradeButton
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperTradingOverlayBackground)
    }

    private var paperTradingLockIcon: some View {
        let paperColor = AppTradingMode.paper.color
        let paperColorLight = AppTradingMode.paper.secondaryColor
        let iconFill = LinearGradient(
            colors: [paperColorLight, paperColor],
            startPoint: .top,
            endPoint: .bottom
        )
        let circleFill = colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)

        return ZStack(alignment: .bottomTrailing) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconFill)
                .padding(14)
                .background(
                    Circle()
                        .fill(circleFill)
                        .overlay(
                            Circle()
                                .stroke(paperColor.opacity(0.35), lineWidth: 1)
                        )
                )

            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(4)
                .background(
                    Circle()
                        .fill(BrandColors.goldBase)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .offset(x: 1, y: 1)
        }
    }

    private var paperTradingTitleBlock: some View {
        let subtitleColor = colorScheme == .dark ? Color.white.opacity(0.5) : DS.Adaptive.textSecondary

        return VStack(spacing: 4) {
            Text("Paper Trading")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)

            Text("Practice with $100k virtual funds")
                .font(.system(size: 13))
                .foregroundColor(subtitleColor)
        }
    }

    private var paperTradingUpgradeButton: some View {
        return Button {
            showPaperTradingUpgrade = true
        } label: {
            HStack(spacing: 6) {
                Text(StoreKitManager.shared.hasAnyTrialAvailable ? "Start Free Trial" : "Upgrade to Pro")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .buttonStyle(CSGoldCapsuleButtonStyle())
    }

    private var paperTradingOverlayBackground: some View {
        let overlayFill = colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.65)
        let overlayStroke = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.Adaptive.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(overlayFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(overlayStroke, lineWidth: 0.5)
            )
    }

    private func tradeFormContent() -> some View {
        TradeFormView(
            quantity: $quantity,
            limitPrice: $limitPrice,
            stopPrice: $stopPrice,
            selectedSide: $selectedSide,
            orderType: $orderType,
            sliderValue: $sliderValue,
            vm: vm,
            priceVM: priceVM,
            symbol: symbol,
            quoteSymbol: currentQuoteSymbol,
            horizontalSizeClass: horizontalSizeClass,
            quantityFieldFocused: $isQuantityFocused,
            isKeyboardVisible: keyboardHeight > 0
        )
    }
    
    // MARK: - Paper Trading Helpers
    
    /// Get current prices for paper trading P&L calculation
    private func getCurrentPricesForPaperTrading() -> [String: Double] {
        var prices: [String: Double] = [:]
        
        // Get price from current symbol
        if vm.currentPrice > 0 {
            let baseAsset = vm.baseAsset
            prices[baseAsset] = vm.currentPrice
        }
        
        // Add known stablecoin prices
        prices["USDT"] = 1.0
        prices["USD"] = 1.0
        prices["USDC"] = 1.0
        prices["BUSD"] = 1.0
        prices["FDUSD"] = 1.0
        
        // PRICE CONSISTENCY FIX: Use bestPrice() for all market coins
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // FIX: Try bestPrice(forSymbol:) for held assets not in allCoins
        for (asset, _) in PaperTradingManager.shared.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Fallback: Use lastKnownPrices only if fresh
        for (asset, _) in PaperTradingManager.shared.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = PaperTradingManager.shared.lastKnownPrices[symbol], cachedPrice > 0,
                   PaperTradingManager.shared.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        return prices
    }
    
    // MARK: - Price Row
    private var priceRow: some View {
        let p = displayedPrice
        // LAYOUT FIX: Use frame(maxWidth:) to ensure price is centered relative to screen
        return VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                // Use TradingPriceDisplay for smooth price transitions
                TradingPriceDisplay(targetPrice: p, isDark: colorScheme == .dark)
                    .onLongPressGesture(minimumDuration: 0.4) {
                        #if os(iOS)
                        if p > 0 {
                            UIPasteboard.general.string = formatUSD(p)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        #endif
                    }
                Spacer(minLength: 0)
            }
            
            // PRICE SOURCE INDICATOR
            // Only show specific exchange badge when live trading is enabled
            // Developer mode without live trading & regular users: No source label needed
            if AppConfig.liveTradingEnabled {
                // Live trading mode: Show which exchange data is being displayed
                if let exchange = dataSourceExchange {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(exchangeIndicatorColor(for: exchange))
                            .frame(width: 6, height: 6)
                        Text(exchange.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(white: colorScheme == .dark ? 0.15 : 0.95))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)  // Ensure full width for proper centering
        .padding(.vertical, 2)  // Minimal padding to bring price closer to chart
        .padding(.horizontal, (self.horizontalSizeClass ?? .compact) == .compact ? 10 : 16)
        .onChange(of: priceVM.price) { _, newPrice in
            // STARTUP FIX v25: Allow significant price corrections during startup
            if isInGlobalStartupPhase() && newPrice <= 0 { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling else { return }
            
            // Cache the price and handle USD conversion (animation is handled by AnimatedPriceText)
            if newPrice > 0 {
                setCachedPrice(newPrice, for: symbol)
                convertPendingUSDToQuantity()
            }
        }
        .compositingGroup()
        .overlay(alignment: .bottom) { HairlineDivider().opacity(0.15) }  // More subtle divider
        .zIndex(10)
    }
    
    /// The current data source exchange (from order book or selected pair)
    private var dataSourceExchange: String? {
        // Priority 1: Order book's actual data source
        if let obExchange = orderBookVM.selectedExchange, !obExchange.isEmpty {
            return obExchange
        }
        // Priority 2: Selected pair exchange
        if let selected = selectedPairExchange, !selected.isEmpty {
            return selected
        }
        // Default: no indicator shown (aggregated data)
        return nil
    }
    
    /// Color indicator for different exchanges
    private func exchangeIndicatorColor(for exchange: String) -> Color {
        switch exchange.lowercased() {
        case "binance", "binance.us", "binance.com":
            return Color.yellow
        case "coinbase":
            return Color.blue
        case "kraken":
            return Color.purple
        case "kucoin":
            return Color.green
        default:
            return Color.gray
        }
    }
    
    // A comma-based price formatter
    private func formatPriceWithCommas(_ value: Double) -> String { formatUSD(value) }

    // Persistent TradingView container — stays mounted and we toggle opacity
    @ViewBuilder
    private func tradingViewContainer(tvSymbol: String, theme: String) -> some View {
        let alt: [String] = [
            tvSymbol,
            "BINANCEUS:\(symbol.uppercased())USD",
            "COINBASE:\(symbol.uppercased())USD",
            "KRAKEN:\(symbol.uppercased())USD",
            "BITFINEX:\(symbol.uppercased())USD",
            "BITSTAMP:\(symbol.uppercased())USD",
            "GEMINI:\(symbol.uppercased())USD",
            "CRYPTO:\(symbol.uppercased())USD",
            "BINANCE:\(symbol.uppercased())USDT",
            "BYBIT:\(symbol.uppercased())USDT",
            "OKX:\(symbol.uppercased())USDT",
            "KUCOIN:\(symbol.uppercased())USDT",
            "BITGET:\(symbol.uppercased())USDT",
            "BINANCE:\(symbol.uppercased())FDUSD"
        ]
        TradingViewChartWebView(
            symbol: tvSymbol,
            interval: selectedInterval.tvValue,
            theme: theme,
            studies: tvStudies,
            altSymbols: alt,
            interactive: selectedChartSource == .trading,
            isReady: $tvReady
        )
        .id("TV-\(theme)")
        .background(Color.clear)
        .opacity(isChartSourceInitialized && selectedChartSource == .trading ? 1 : 0)
        .allowsHitTesting(isChartSourceInitialized && selectedChartSource == .trading)
        .zIndex(1)
        .accessibilityHidden(true)
    }
    
    // Factored helpers to keep type-checking fast
    /// CHART READJUST FIX: Returns a stabilized price for the chart during the cold-start
    /// settling period. After settling, tracks displayedPrice normally.
    private var chartLivePrice: Double {
        let now = Date()
        if now.timeIntervalSince(chartPriceSettledAt) < chartPriceSettlingDuration {
            // Still in settling period — return the first valid price we captured
            return stabilizedChartPrice > 0 ? stabilizedChartPrice : displayedPrice
        }
        // Settled — pass through the live price normally
        return displayedPrice
    }
    
    @ViewBuilder
    private func chartCanvas(innerChartHeight: CGFloat, tvSymbol: String, theme: String, containerWidth: CGFloat) -> some View {
        ZStack {
            // Timestamp hook: record when chart becomes visible
            Color.clear
                .onAppear {
                    Task { @MainActor in
                        if selectedChartSource == .sage {
                            chartLastLoadedAt = Date()
                        }
                        // CHART READJUST FIX: Start the settling timer for chart price
                        chartPriceSettledAt = Date()
                        if displayedPrice > 0 {
                            stabilizedChartPrice = displayedPrice
                        }
                    }
                }
                .onChange(of: displayedPrice) { _, newPrice in
                    // CHART READJUST FIX: During settling period, capture the first valid price
                    // but don't propagate further changes to the chart
                    if Date().timeIntervalSince(chartPriceSettledAt) < chartPriceSettlingDuration {
                        if stabilizedChartPrice <= 0 && newPrice > 0 {
                            stabilizedChartPrice = newPrice
                        }
                    } else {
                        stabilizedChartPrice = newPrice
                    }
                }

            // Native CryptoSage chart - always render immediately, it handles its own loading internally
            // CryptoChartView loads cached data instantly and fetches fresh data in background
            // CHART READJUST FIX: Use stabilized chartLivePrice instead of displayedPrice
            // to prevent rapid price resolution from retriggering chart body evaluation during cold start
            CryptoChartView(symbol: symbol, interval: selectedInterval, height: innerChartHeight, alignVolumeToPriceAxis: true, livePrice: chartLivePrice, preferredExchange: selectedPairExchange)
                // PERFORMANCE: Use symbol-only ID to prevent full view recreation on timeframe switch
                .id("chart-\(symbol)")
                .padding(.horizontal, 0)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: innerChartHeight, maxHeight: innerChartHeight)
                .contentShape(Rectangle())
                .opacity(selectedChartSource == .sage ? 1 : 0)
                .allowsHitTesting(selectedChartSource == .sage)
                .zIndex(selectedChartSource == .sage ? 2 : 0)

            // TradingView web chart (lazy-mounted only when needed)
            if mountTradingView {
                tradingViewContainer(tvSymbol: tvSymbol, theme: theme)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: innerChartHeight, maxHeight: innerChartHeight)
                    .background(Color.clear)
                    .clipped()
            }

        }
        // Disable animations on chart canvas to prevent glitchy appearance on initial load
        // The chart source and loading state changes should be instant for a professional feel
        .transaction { $0.animation = nil }
        .transition(.identity)
    }

    // Added private PreferenceKey inside TradeView per instructions
    // PERFORMANCE FIX: Aggressive throttling to minimize "multiple updates per frame" warnings
    private struct TradeTimeframeButtonFrameKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        private static var lastUpdateAt: CFTimeInterval = 0
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue()
            guard next != .zero else { return }
            let now = CACurrentMediaTime()
            // Coalesce to at most ~10Hz (reduced from 15Hz to further reduce multi-update warnings)
            // The actual value is debounced again in onPreferenceChange, so lower frequency is fine
            if now - lastUpdateAt < 0.1 { return }
            // Ignore jitter up to 5px to avoid unnecessary updates
            let dx = abs(next.origin.x - value.origin.x)
            let dy = abs(next.origin.y - value.origin.y)
            let dw = abs(next.size.width - value.size.width)
            let dh = abs(next.size.height - value.size.height)
            if dx < 5.0 && dy < 5.0 && dw < 5.0 && dh < 5.0 { return }
            value = next
            lastUpdateAt = now
        }
    }

    // Added helper method to compute best popover edge
    private func bestPopoverEdge(for frame: CGRect, desiredHeight: CGFloat = 340) -> Edge {
        let screen: CGRect = {
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
               let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window.bounds
            }
            return UIScreen.main.bounds
        }()
        let spaceBelow = max(0, screen.height - frame.maxY)
        let spaceAbove = max(0, frame.minY)
        if spaceBelow >= desiredHeight || spaceBelow >= spaceAbove { return .top }
        return .bottom
    }

    // Chart controls row using shared components from DesignSystem+Buttons.swift
    // Professional controls row - toggle fills remaining width, zero dead space on all devices
    @ViewBuilder
    private func chartControlsRow(isCompact: Bool, controlHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Chart source toggle - NO fixedSize so it expands to absorb remaining width
                // This ensures the row fills edge-to-edge on every screen size
                ChartSourceSegmentedToggle(selected: $selectedChartSource)

                // Timeframe dropdown button - fixed intrinsic size
                TimeframeDropdownButton(
                    interval: selectedInterval.rawValue,
                    isActive: showTimeframePopover,
                    action: {
                        timeframePopoverEdge = bestPopoverEdge(for: timeframeButtonFrame)
                        showTimeframePopover = true
                    }
                )
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TradeTimeframeButtonFrameKey.self, value: proxy.frame(in: .global))
                    }
                )
                .onPreferenceChange(TradeTimeframeButtonFrameKey.self) { frame in
                    timeframeFrameDebounce?.cancel()
                    let work = DispatchWorkItem { self.timeframeButtonFrame = frame }
                    timeframeFrameDebounce = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.032, execute: work)
                }

                // Indicators button - fixed intrinsic size
                IndicatorsButton(
                    count: tvIndicatorSet.count,
                    action: { showIndicatorMenu = true }
                )
                .fixedSize(horizontal: true, vertical: false)

                // Technicals button - fixed intrinsic size
                Button {
                    showTechnicals = true
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: controlHeight, height: controlHeight)
                        .capsuleChip(backgroundOpacity: 0.06)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Technicals")
                .frame(height: controlHeight)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Chart
    @ViewBuilder
    private var chartSection: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // Background card (no stroke to avoid any duplicate lines)
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardFillColor)

                // Chart + integrated controls
                VStack(spacing: 0) {
                    // Layout constants to ensure controls sit fully inside the card
                    // Use nil-coalescing to treat nil as compact (default for most iPhone users)
                    // This prevents layout shift when horizontalSizeClass resolves from nil
                    let isCompact = (self.horizontalSizeClass ?? .compact) == .compact
                    let cardHeight: CGFloat = isCompact ? 288 : 336
                    let controlHeight: CGFloat = 28
                    let chartTopPad: CGFloat = 2
                    let chartBottomPad: CGFloat = 2
                    let controlsTopPad: CGFloat = 4
                    let controlsBottomPad: CGFloat = 10 // 4 (row vertical bottom) + 6 (extra bottom)

                    let innerChartHeight: CGFloat = max(150, cardHeight - (controlHeight + chartTopPad + chartBottomPad + controlsTopPad + controlsBottomPad))

                    // Chart content - seamless edge-to-edge within the card
                    ChartStyledContainer(theme: chartContainerTheme, rows: 0, columns: 0) {
                        chartCanvas(
                            innerChartHeight: innerChartHeight,
                            tvSymbol: "\(tvExchangePrefix):\(symbol.uppercased())\(tvQuote)",
                            theme: (colorScheme == .dark) ? "Dark" : "Light",
                            containerWidth: chartWidth
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: innerChartHeight, maxHeight: innerChartHeight)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: innerChartHeight, maxHeight: innerChartHeight)
                    .padding(.horizontal, 0)
                    .padding(.top, chartTopPad)
                    .padding(.bottom, chartBottomPad)

                    // Integrated interval controls
                    chartControlsRow(isCompact: isCompact, controlHeight: controlHeight)
                        .padding(.top, 6)
                        .zIndex(3)
                }
            }
            .frame(height: (self.horizontalSizeClass ?? .compact) == .compact ? CGFloat(288) : CGFloat(336))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .overlay(
                LinearGradient(colors: [Color.white.opacity(cardTopHighlightOpacity), Color.clear], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            )
            .overlay(
                ctaBottomShade
                    .opacity(cardBottomShadeOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            )
            .compositingGroup()
            .onSizeChange { size in
                let newWidth = size.width.rounded()
                guard abs(newWidth - chartWidth) >= 2 else { return }
                chartWidthDebounceWork?.cancel()
                let work = DispatchWorkItem { chartWidth = newWidth }
                chartWidthDebounceWork = work
                // Use a small delay without animation to avoid per-frame updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }  // Modified per instructions
        }
    }
    
    // MARK: - Order Book Section
    private var orderBookSection: some View {
        // Show order book directly without skeleton placeholder
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Order book with integrated header and controls
                OrderBookView(
                    viewModel: orderBookVM,
                    symbol: symbol,
                    isActiveTab: isActiveTab,
                    depthMode: $depthMode,
                    useLogScale: $useLogScale,
                    priceGrouping: $priceGrouping,
                    showDepthChart: $showDepthChart,
                    rowsToShow: rowsToShow,
                    tabBarReserve: tabBarReserve,
                    showHeader: true,
                    showImbalanceBar: true,
                    onSelectPrice: { price in
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        Task { @MainActor in
                            orderType = .limit
                            limitPrice = price
                        }
                    }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(orderBookFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(orderBookStrokeColor, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, contentHPad)
        }
        .padding(.top, 8)
    }
    
    private var tabBarReserve: CGFloat { (self.horizontalSizeClass ?? .compact) == .compact ? 64 : 72 }

}

// MARK: - Trade Chart Controls (Toggle & Indicators)
/// Deprecated: Use ChartSourceSegmentedToggle from DesignSystem+Buttons.swift instead
@available(*, deprecated, message: "Use ChartSourceSegmentedToggle from DesignSystem+Buttons.swift instead")
private struct TradeChartSourceToggle: View {
    @Binding var selected: ChartSource
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 2) {
            segment(.sage, label: "CryptoSage AI")
            segment(.trading, label: "TradingView")
        }
        .padding(1)
        .background(DS.Adaptive.chipBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .frame(height: 28)
    }
    private var isDark: Bool { colorScheme == .dark }
    
    private func segment(_ type: ChartSource, label: String) -> some View {
        let isSelected = selected == type
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.12)) { selected = type }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .foregroundColor(isSelected ? BrandColors.ctaTextColor(isDark: isDark) : .primary.opacity(0.6))
                .background(
                    ZStack {
                        if isSelected {
                            // Gold gradient background for selected state
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AdaptiveGradients.chipGold(isDark: isDark))
                            // Top highlight
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(isDark ? 0.18 : 0.30), .clear], startPoint: .top, endPoint: .center))
                            // Rim stroke
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                        }
                    }
                )
        }
    }
}

private struct TradeSideToggle: View {
    @Binding var selected: TradeSide
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            segment(.buy, label: "Buy")
            segment(.sell, label: "Sell")
        }
        .padding(1)
        .background(DS.Adaptive.chipBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .overlay(SegmentDividers(count: 2).clipShape(Capsule()))
        .frame(height: 28)
        .frame(maxWidth: .infinity)
    }
    private func segment(_ side: TradeSide, label: String) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.12)) { selected = side }
        } label: {
            ZStack {
                if selected == side {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(side == .sell ? redButtonGradient : AdaptiveGradients.chipGold(isDark: colorScheme == .dark))
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(side == .sell ? ctaRimStrokeGradientRed : AdaptiveGradients.ctaRimStroke(isDark: colorScheme == .dark), lineWidth: 0.8)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AdaptiveGradients.ctaBottomShade(isDark: colorScheme == .dark))
                        .opacity(colorScheme == .dark ? 1 : 0.0)
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    // Dark mode: black text on gold Buy; Light mode: white text on black Buy
                    .foregroundColor(selected == side
                        ? (side == .sell ? .white : (colorScheme == .dark ? .black : .white))
                        : .primary.opacity(0.9))
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }
}

private struct OrderTypeToggle: View {
    @Binding var selected: OrderType
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            ForEach(OrderType.allCases, id: \.self) { type in
                segment(type, label: displayName(for: type))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(1)
        .background(DS.Adaptive.chipBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .overlay(SegmentDividers(count: OrderType.allCases.count).clipShape(Capsule()))
        .frame(height: 28)
        .frame(maxWidth: .infinity)
    }
    private func displayName(for type: OrderType) -> String {
        type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private var isDark: Bool { colorScheme == .dark }
    
    private func segment(_ type: OrderType, label: String) -> some View {
        let isSelected = selected == type
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.12)) { selected = type }
        } label: {
            ZStack {
                if isSelected {
                    // Match premium segmented style used across core trading controls.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AdaptiveGradients.chipGold(isDark: isDark))
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.18 : 0.12), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .foregroundColor(isSelected ? (isDark ? BrandColors.ctaTextColor(isDark: true) : .white) : .primary.opacity(0.6))
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }
}

// Added reusable divider view as per instructions
private struct SegmentDividers: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                ForEach(1..<count, id: \.self) { i in
                    // 6) Strengthened light mode divider opacity:
                    Rectangle()
                        .fill(DS.Neutral.divider(colorScheme == .dark ? 0.08 : 0.12))
                        .frame(width: 1, height: max(0, h - 2))
                        .position(x: geo.size.width * CGFloat(i) / CGFloat(count), y: h / 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HairlineDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.18),
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 1)
    }
}

// part 3) Define PreferredSchemeModifier near other private structs:
private struct PreferredSchemeModifier: ViewModifier {
    let mode: TradeView.AppearanceOverride
    func body(content: Content) -> some View {
        switch mode {
        case .system:
            content
        case .dark:
            content.preferredColorScheme(.dark)
        case .light:
            content.preferredColorScheme(.light)
        }
    }
}

private struct OrderBookHeaderRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let quote: String
    let bestBid: String?
    let bestAsk: String?
    
    // Loading animation state
    @State private var loadingPhase: CGFloat = 0.4
    
    // Extracted computed values to reduce type-checking complexity
    private var parsedBid: Double {
        (bestBid?.replacingOccurrences(of: ",", with: "")).flatMap { Double($0) } ?? 0
    }
    private var parsedAsk: Double {
        (bestAsk?.replacingOccurrences(of: ",", with: "")).flatMap { Double($0) } ?? 0
    }
    private var hasBid: Bool { parsedBid > 0 }
    private var hasAsk: Bool { parsedAsk > 0 }
    private var hasBoth: Bool { hasBid && hasAsk }
    private var isLoading: Bool { bestBid == nil && bestAsk == nil }
    private var spreadAbs: Double { hasBoth ? (parsedAsk - parsedBid) : 0 }
    private var spreadPct: Double { (hasBoth && parsedAsk > 0) ? (spreadAbs / parsedAsk) * 100.0 : 0 }
    
    // Show actual dollar spread - this is what traders actually care about
    private var spreadPctStr: String {
        guard hasBoth else { return "—" }
        if spreadAbs < 0.01 {
            // Extremely tight spread (sub-penny)
            return "<1¢"
        } else if spreadAbs < 1.0 {
            // Show cents for spreads under $1
            let cents = spreadAbs * 100
            if cents < 10 {
                return String(format: "%.0f¢", cents)
            } else {
                return String(format: "%.0f¢", cents)
            }
        } else if spreadAbs < 100 {
            // Show dollars with cents for spreads $1-$100
            return String(format: "$%.2f", spreadAbs)
        } else {
            // Show whole dollars for large spreads
            return String(format: "$%.0f", spreadAbs)
        }
    }
    
    // Tier based on spread as percentage of price:
    // Tight: < 0.01% (green) - excellent liquidity
    // Normal: 0.01% - 0.1% (orange) - typical spread
    // Wide: > 0.1% (red) - poor liquidity
    private var spreadTier: Int {
        guard hasBoth else { return -1 }
        if spreadPct < 0.01 { return 0 }      // Very tight spread (green)
        else if spreadPct < 0.1 { return 1 }  // Normal spread (orange)
        else { return 2 }                      // Wide spread (red)
    }
    private var chipColor: Color {
        (spreadTier == 0) ? .green : ((spreadTier == 1) ? .orange : (spreadTier == 2 ? .red : Color.gray))
    }
    
    // PERFORMANCE FIX: Cached formatter for non-USD quote pairs
    private static let _quotePriceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 8
        return nf
    }()

    private func formatPriceForQuote(_ value: Double) -> String {
        if quote.uppercased().contains("USD") {
            return formatUSD(value)
        } else {
            return Self._quotePriceFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
        }
    }
    private var bidText: String {
        if parsedBid > 0 { return formatPriceForQuote(parsedBid) }
        if let raw = bestBid, !raw.isEmpty { return raw }
        return isLoading ? "..." : "—"
    }
    private var askText: String {
        if parsedAsk > 0 { return formatPriceForQuote(parsedAsk) }
        if let raw = bestAsk, !raw.isEmpty { return raw }
        return isLoading ? "..." : "—"
    }
    private var spreadAbsText: String { hasBoth ? formatPriceForQuote(spreadAbs) : "" }
    
    @ViewBuilder
    private var placeholderBadge: some View {
        Text(isLoading ? "..." : "—")
            .font(DS.Fonts.orderBookHeader)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            // Matched padding with spreadBadge for consistency
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.15), lineWidth: 1.0)
                    )
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .opacity(isLoading ? loadingPhase : 1.0)
    }

    @ViewBuilder
    private var spreadBadge: some View {
        Text(spreadPctStr)
            .font(DS.Fonts.orderBookHeader)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            // Increased padding for better readability
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    // Increased fill opacity for better contrast
                    .fill(chipColor.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            // Stronger stroke for better definition
                            .stroke(chipColor.opacity(0.45), lineWidth: 1.0)
                    )
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }

    // Split UI into smaller sections
    @ViewBuilder
    private var leftBidSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text("Bid")
                    .font(DS.Fonts.orderBookHeader)
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(bidText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
            HStack(spacing: 4) {
                Text("Bid")
                    .font(DS.Fonts.orderBookHeader)
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(bidText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
            HStack(spacing: 2) {
                Text(bidText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
        }
    }

    @ViewBuilder
    private var centerSpreadSection: some View {
        ViewThatFits(in: .horizontal) {
            if hasBoth {
                HStack(spacing: 4) {
                    Text("Spread")
                        .font(DS.Fonts.orderBookHeader)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    spreadBadge
                    Text("• \(spreadAbsText)")
                        .font(DS.Fonts.orderBookHeader)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .lineLimit(1)

                HStack(spacing: 3) {
                    Text("Spread")
                        .font(DS.Fonts.orderBookHeader)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                    spreadBadge
                }
                .lineLimit(1)

                HStack(spacing: 0) {
                    spreadBadge
                }
            } else {
                HStack(spacing: 4) {
                    Text("Spread")
                        .font(DS.Fonts.orderBookHeader)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    placeholderBadge
                }
                HStack(spacing: 0) {
                    placeholderBadge
                }
            }
        }
    }

    @ViewBuilder
    private var rightAskSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text("Ask")
                    .font(DS.Fonts.orderBookHeader)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(askText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
            HStack(spacing: 4) {
                Text("Ask")
                    .font(DS.Fonts.orderBookHeader)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(askText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
            HStack(spacing: 2) {
                Text(askText)
                    .font(DS.Fonts.orderBookHeader)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .opacity(0.95)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                    .allowsTightening(true)
            }
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            leftBidSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isLoading ? loadingPhase : 1.0)

            centerSpreadSection
                .frame(minWidth: 76, maxWidth: .infinity, alignment: .center)

            rightAskSection
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(isLoading ? loadingPhase : 1.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.clear)
        // Strengthened light mode divider opacity from 0.08 to 0.12
        .overlay(
            Rectangle()
                .fill(DS.Neutral.divider(colorScheme == .dark ? 0.08 : 0.12))
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoading ? "Loading order book data" : "Bid \(bidText), Spread \(spreadPctStr) \(spreadAbsText), Ask \(askText)")
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                guard isLoading, !reduceMotion, !globalAnimationsKilled else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    loadingPhase = 1.0
                }
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading && !reduceMotion && !globalAnimationsKilled {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    loadingPhase = 1.0
                }
            } else {
                withAnimation(.none) { loadingPhase = 1.0 }
            }
        }
    }
}

struct CapsuleChipStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var backgroundOpacity: Double = 0.12
    func body(content: Content) -> some View {
        // 7) Stronger light mode surface for chips:
        let bg = (colorScheme == .dark) ? DS.Neutral.bg(backgroundOpacity) : Color(UIColor.systemGray5)
        return content
            .background(bg)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(ctaRimStrokeGradient, lineWidth: 0.8).opacity(colorScheme == .dark ? 1 : 0.8)
            )
    }
}

private extension View {
    func capsuleChip(backgroundOpacity: Double = 0.12) -> some View {
        self.modifier(CapsuleChipStyle(backgroundOpacity: backgroundOpacity))
    }
}

// Lightweight size reader used to capture the chart card width for a one-time remount
// THREAD SAFETY FIX: PreferenceKey reduce() can be called from background threads - use NSLock.
private struct ChartSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    private static let lock = NSLock()
    private static var _lastUpdateAt: CFTimeInterval = 0
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        
        let now = CACurrentMediaTime()
        
        lock.lock()
        defer { lock.unlock() }
        
        // Coalesce to at most ~10Hz (reduced from 20Hz to reduce multi-update warnings)
        if now - _lastUpdateAt < 0.1 { return }
        // Ignore jitter up to 3px to avoid multiple updates per frame
        let dx = abs(next.width - value.width)
        let dy = abs(next.height - value.height)
        if dx < 3 && dy < 3 { return }
        value = next
        _lastUpdateAt = now
    }
}

private extension View {
    func onSizeChange(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ChartSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ChartSizePreferenceKey.self, perform: onChange)
    }
}

// MARK: - Custom Sheets (lightweight adapters)

// MARK: - IndicatorPickerSheet
struct IndicatorPickerSheet: View {
    let selected: Set<IndicatorType>
    let onChange: (Set<IndicatorType>) -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var local: Set<IndicatorType>

    init(selected: Set<IndicatorType>, onChange: @escaping (Set<IndicatorType>) -> Void, onClose: @escaping () -> Void) {
        self.selected = selected
        self.onChange = onChange
        self.onClose = onClose
        _local = State(initialValue: selected)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") {
                    onChange(local)
                    onClose()
                }
                .font(.headline)
                .padding()
            }
            .background(DS.Adaptive.background.opacity(0.8))
            .foregroundColor(DS.Adaptive.textPrimary)
            List {
                ForEach(IndicatorType.allCases, id: \.self) { ind in
                    Toggle(isOn: Binding(
                        get: { local.contains(ind) },
                        set: { v in
                            if v { local.insert(ind) } else { local.remove(ind) }
                            onChange(local)
                        }
                    )) {
                        Text(ind.label)
                    }
                    .tint(AppTradingMode.paper.color)
                }
            }
            .listStyle(PlainListStyle())
            .background(DS.Adaptive.background)
            .scrollContentBackground(.hidden)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
    }
}

// TimeframePopoverView has been replaced by CSAnchoredGridMenu for a better anchored dropdown experience

// Insert the following new reusable segmented control for percent allocation immediately after the closing brace of OrderTypeToggle:

private struct PercentAllocationToggle: View {
    @Binding var sliderValue: Double
    let onSelect: (Int) -> Void
    var isCompact: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private let options: [Int] = [25, 50, 75, 100]
    private var selectionAccent: Color { colorScheme == .dark ? BrandColors.goldBase : BrandColors.silverBase }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Single-row segmented control
            ZStack {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { pct in
                        segment(pct)
                            .frame(maxWidth: .infinity)
                    }
                }
                SegmentDividers(count: options.count)
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
            }
            .fixedSize(horizontal: true, vertical: false)

            // Fallback: 2x2 layout for ultra-narrow widths
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(options.prefix(2), id: \.self) { pct in
                        segment(pct)
                            .frame(maxWidth: .infinity)
                    }
                }
                Rectangle()
                    .fill(DS.Neutral.divider(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 1)
                HStack(spacing: 0) {
                    ForEach(options.suffix(2), id: \.self) { pct in
                        segment(pct)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(1)
        .background(DS.Adaptive.chipBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .frame(height: isCompact ? 26 : 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Allocation")
    }

    private func isSelected(_ pct: Int) -> Bool {
        abs(sliderValue - Double(pct) / 100.0) < 0.02
    }

    private var isDark: Bool { colorScheme == .dark }
    
    private func segment(_ pct: Int) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.12)) {
                sliderValue = Double(pct) / 100.0
            }
            onSelect(pct)
        } label: {
            ZStack {
                if isSelected(pct) {
                    // Semantic accent by trading mode (paper) with neutral fallback
                    Capsule()
                        .fill(selectionAccent.opacity(isDark ? 0.82 : 0.78))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(isDark ? 0.12 : 0.25), .clear], startPoint: .top, endPoint: .center))
                    Capsule()
                        .stroke(selectionAccent.opacity(isDark ? 0.55 : 0.42), lineWidth: 0.8)
                }
                Text(pct == 100 ? "Max" : "\(pct)%")
                    .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .foregroundColor(isSelected(pct) ? .white : .primary.opacity(0.6))
                    .padding(.horizontal, isCompact ? 5 : 8)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: isCompact ? 44 : 52, maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(pct) percent")
        .accessibilityAddTraits(isSelected(pct) ? .isSelected : AccessibilityTraits())
    }
}

// MARK: - Bot Selection Sheet
struct BotSelectionSheet: View {
    @Binding var isPresented: Bool
    let side: TradeSide
    let orderType: OrderType
    let quantity: Double
    let slippage: Double
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTradingBot = false
    @State private var showDerivativesBot = false
    @State private var showBotHub = false
    
    // Bot managers for status display
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    // MARK: - Current Mode
    
    private enum TradingMode {
        case demo
        case paper
        case live
    }
    
    private var currentMode: TradingMode {
        if demoModeManager.isDemoMode {
            return .demo
        } else if paperTradingManager.isPaperTradingEnabled {
            return .paper
        } else {
            return .live
        }
    }
    
    // Total running bots count (mode-aware)
    private var runningBotsCount: Int {
        switch currentMode {
        case .demo:
            return paperBotManager.runningDemoBotCount
        case .paper:
            return paperBotManager.runningBotCount
        case .live:
            return liveBotManager.enabledBotCount
        }
    }
    
    // Total bots count (mode-aware)
    private var totalBotsCount: Int {
        switch currentMode {
        case .demo:
            return paperBotManager.demoBotCount
        case .paper:
            return paperBotManager.totalBotCount
        case .live:
            return liveBotManager.totalBotCount
        }
    }
    
    private var spotBotGradient: [Color] {
        switch currentMode {
        case .demo:
            return [AppTradingMode.demo.secondaryColor, AppTradingMode.demo.color]
        case .paper:
            return [AppTradingMode.paper.secondaryColor, AppTradingMode.paper.color]
        case .live:
            return [Color.cyan.opacity(0.9), Color.blue.opacity(0.85)]
        }
    }
    
    private var derivativesBotGradient: [Color] {
        [Color.orange.opacity(0.95), Color.red.opacity(0.9)]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header with refined styling
                HStack {
                    Text("Select Bot Type")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [DS.Adaptive.textSecondary, DS.Adaptive.textTertiary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Bot Type Cards
                VStack(spacing: 14) {
                    // Trading Bot Card (Spot)
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showTradingBot = true
                    } label: {
                        PremiumBotTypeCard(
                            icon: "chart.xyaxis.line",
                            title: "Trading Bot",
                            subtitle: "Spot trading with DCA, Grid & Signal strategies",
                            gradientColors: spotBotGradient
                        )
                    }
                    .buttonStyle(BotCardButtonStyle())
                    
                    // Derivatives Bot Card (Futures)
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showDerivativesBot = true
                    } label: {
                        PremiumBotTypeCard(
                            icon: "chart.line.uptrend.xyaxis.circle",
                            title: "Derivatives Bot",
                            subtitle: "Futures & perpetual contracts with leverage",
                            gradientColors: derivativesBotGradient
                        )
                    }
                    .buttonStyle(BotCardButtonStyle())
                    
                    // Divider
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, DS.Adaptive.divider],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Adaptive.divider, Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                    }
                    .padding(.vertical, 4)
                    
                    // Manage My Bots Card
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showBotHub = true
                    } label: {
                        ManageBotsCard(
                            runningCount: runningBotsCount,
                            totalCount: totalBotsCount,
                            isDemoMode: demoModeManager.isDemoMode,
                            isPaperMode: paperTradingManager.isPaperTradingEnabled
                        )
                    }
                    .buttonStyle(BotCardButtonStyle())
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 20)
            }
            .background(DS.Adaptive.background)
            .navigationDestination(isPresented: $showTradingBot) {
                TradingBotView(
                    side: side,
                    orderType: orderType,
                    quantity: quantity,
                    slippage: slippage
                )
            }
            .navigationDestination(isPresented: $showDerivativesBot) {
                DerivativesBotView()
            }
            .navigationDestination(isPresented: $showBotHub) {
                BotHubView()
            }
        }
        .presentationDetents([.height(420)])
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Seed demo bots if in demo mode
                if demoModeManager.isDemoMode {
                    paperBotManager.seedDemoBots()
                }
            }
        }
    }
}

// MARK: - Manage Bots Card
private struct ManageBotsCard: View {
    let runningCount: Int
    let totalCount: Int
    let isDemoMode: Bool
    let isPaperMode: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulseAnimation: Bool = false
    
    // Mode-aware colors and styling
    private var iconGradientColors: [Color] {
        if isDemoMode {
            return [AppTradingMode.demo.secondaryColor, AppTradingMode.demo.color]
        }
        return [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
    }
    
    private var shadowColor: Color {
        if isDemoMode {
            return AppTradingMode.demo.color.opacity(colorScheme == .dark ? 0.4 : 0.25)
        }
        return Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.25)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: iconGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 54, height: 54)
                
                Image(systemName: isDemoMode ? "sparkles" : "gearshape.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Manage My Bots")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Demo badge — uses shared ModeBadge for consistent styling
                    if isDemoMode && totalCount > 0 {
                        ModeBadge(mode: .demo, variant: .compact)
                    }
                    
                    // Running indicator
                    if runningCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                .animation(globalAnimationsKilled ? .none : .easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseAnimation)
                            
                            Text("\(runningCount) running")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                    }
                }
                
                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    strokeColor,
                    lineWidth: 1
                )
        )
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if runningCount > 0 && !globalAnimationsKilled {
                    pulseAnimation = true
                }
            }
        }
    }
    
    private var strokeColor: Color {
        if runningCount > 0 {
            return Color.green.opacity(0.3)
        } else if isDemoMode && totalCount > 0 {
            return AppTradingMode.demo.color.opacity(0.3)
        }
        return DS.Adaptive.stroke
    }
    
    private var statusText: String {
        if isDemoMode {
            if totalCount == 0 {
                return "View sample bots for demonstration"
            } else if runningCount == 0 {
                return "Sample: \(totalCount) bot\(totalCount == 1 ? "" : "s") • All stopped"
            } else {
                return "Sample: \(totalCount) bot\(totalCount == 1 ? "" : "s") • \(runningCount) running"
            }
        } else if totalCount == 0 {
            return "No bots created yet. Start with a new bot above!"
        } else if runningCount == 0 {
            return "\(totalCount) bot\(totalCount == 1 ? "" : "s") • All stopped"
        } else {
            let mode = isPaperMode ? "Paper" : "Live"
            return "\(totalCount) bot\(totalCount == 1 ? "" : "s") • \(mode) Trading"
        }
    }
}

// MARK: - Bot Card Button Style
private struct BotCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Premium Bot Type Card
private struct PremiumBotTypeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradientColors: [Color]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Refined icon container with gradient background
            ZStack {
                // Outer glow
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 54, height: 54)
                
                // Icon - white works well against gold gradient
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Chevron with subtle styling
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(0.5), gradientColors[1].opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
