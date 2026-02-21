import SwiftUI
import Combine

struct OrderBookView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: OrderBookViewModel
    let symbol: String
    let isActiveTab: Bool
    @Binding var depthMode: DepthMode
    @Binding var useLogScale: Bool
    @Binding var priceGrouping: PriceGrouping
    @Binding var showDepthChart: Bool
    var rowsToShow: Int
    var tabBarReserve: CGFloat
    var showHeader: Bool = true
    var showImbalanceBar: Bool = true
    var onSelectPrice: (String) -> Void

    // Local UI state moved from TradeView
    @State private var highlightedBids: Set<String> = []
    @State private var highlightedAsks: Set<String> = []
    @State private var previousBidMap: [String: String] = [:]
    @State private var previousAskMap: [String: String] = [:]
    @State private var bidMaxEMA: Double = 1
    @State private var askMaxEMA: Double = 1

    private var displayedOrderBookRows: Int { rowsToShow }
    
    // MARK: - Grouped Order Book Data
    /// Chooses a display grouping that avoids collapsing real depth into too few rows.
    /// Keeps the user's selected grouping as the first choice, then progressively
    /// tries finer groupings when depth would otherwise look sparse.
    private var effectivePriceGrouping: PriceGrouping {
        // Professional defaults: each side should show mostly real depth.
        // If coarse grouping produces too few levels, prefer finer buckets.
        let minRowsPerSide = min(displayedOrderBookRows, max(10, Int(Double(displayedOrderBookRows) * 0.85)))
        let candidates = groupingCandidates(startingFrom: priceGrouping)
        var fallbackGroup = priceGrouping
        var fallbackMinSideDepth = -1
        var fallbackTotalDepth = -1
        
        for group in candidates {
            let bids = viewModel.aggregateByPriceLevel(viewModel.bids, tickSize: group.tickSize, isBids: true)
            let asks = viewModel.aggregateByPriceLevel(viewModel.asks, tickSize: group.tickSize, isBids: false)

            // Prefer groupings that provide enough depth on both sides.
            if bids.count >= minRowsPerSide && asks.count >= minRowsPerSide {
                return group
            }

            // If none reaches the target, keep the densest balanced grouping.
            let minSideDepth = min(bids.count, asks.count)
            let totalDepth = bids.count + asks.count
            if minSideDepth > fallbackMinSideDepth || (minSideDepth == fallbackMinSideDepth && totalDepth > fallbackTotalDepth) {
                fallbackGroup = group
                fallbackMinSideDepth = minSideDepth
                fallbackTotalDepth = totalDepth
            }
        }
        return fallbackGroup
    }
    
    private var effectiveTickSize: Double {
        effectivePriceGrouping.tickSize
    }
    
    private func groupingCandidates(startingFrom selected: PriceGrouping) -> [PriceGrouping] {
        switch selected {
        case .p001:
            return [.p001]
        case .p01:
            return [.p01, .p001]
        case .p1:
            return [.p1, .p01, .p001]
        case .p10:
            return [.p10, .p1, .p01, .p001]
        case .p100:
            return [.p100, .p10, .p1, .p01, .p001]
        }
    }
    
    private var groupedBids: [OrderBookViewModel.OrderBookEntry] {
        viewModel.aggregateByPriceLevel(viewModel.bids, tickSize: effectiveTickSize, isBids: true)
    }
    
    private var groupedAsks: [OrderBookViewModel.OrderBookEntry] {
        viewModel.aggregateByPriceLevel(viewModel.asks, tickSize: effectiveTickSize, isBids: false)
    }

    private func extrapolatedPriceString(_ price: Double) -> String {
        // Preserve enough precision for low-priced assets (e.g., XRP, DOGE, SHIB pairs)
        if price >= 1000 { return String(format: "%.2f", price) }
        if price >= 1 { return String(format: "%.3f", price) }
        if price >= 0.01 { return String(format: "%.5f", price) }
        return String(format: "%.8f", price)
    }
    
    // MARK: - Display Data
    /// Returns real bids only. Do not fabricate 0.00 liquidity rows.
    private var paddedBids: [OrderBookViewModel.OrderBookEntry] {
        let bids = groupedBids
        return Array(bids.prefix(displayedOrderBookRows))
    }
    
    /// Returns real asks only. Do not fabricate 0.00 liquidity rows.
    private var paddedAsks: [OrderBookViewModel.OrderBookEntry] {
        let asks = groupedAsks
        return Array(asks.prefix(displayedOrderBookRows))
    }
    
    // MARK: - Cumulative Depths (precomputed for performance)
    private var bidCumulativeDepths: [Double] {
        viewModel.cumulativeDepths(for: groupedBids)
    }
    
    private var askCumulativeDepths: [Double] {
        viewModel.cumulativeDepths(for: groupedAsks)
    }

    // MARK: - Best Bid/Ask & Spread
    // Optimized: data is already sorted, so just use first element
    private var bestBid: Double {
        viewModel.bids.first.flatMap { Double($0.price) } ?? 0
    }
    private var bestAsk: Double {
        viewModel.asks.first.flatMap { Double($0.price) } ?? 0
    }
    private var spreadAbs: Double {
        (bestAsk > 0 && bestBid > 0) ? (bestAsk - bestBid) : 0
    }
    private var spreadPct: Double {
        bestAsk > 0 ? (spreadAbs / bestAsk) * 100.0 : 0
    }
    private var spreadAbsString: String {
        if viewModel.isLoading && viewModel.bids.isEmpty && viewModel.asks.isEmpty {
            return "..."
        }
        return formatPriceWithCommas(spreadAbs)
    }
    
    // Show actual dollar spread - this is what traders actually care about
    private var spreadPctString: String {
        if viewModel.isLoading && viewModel.bids.isEmpty && viewModel.asks.isEmpty {
            return "..."
        }
        return formatSpreadDisplay(spreadAbs)
    }
    
    /// Formats spread value for display with appropriate units (cents or dollars)
    private func formatSpreadDisplay(_ spread: Double) -> String {
        if spread < 0.01 {
            return "<1¢"
        } else if spread < 1.0 {
            let cents = spread * 100
            return String(format: "%.0f¢", cents)
        } else if spread < 100 {
            return String(format: "$%.2f", spread)
        } else {
            return String(format: "$%.0f", spread)
        }
    }
    
    /// Formats quantity for clean display (removes trailing zeros)
    private func formatQty(_ qty: String) -> String {
        guard let value = Double(qty) else { return qty }
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.5f", value)
        }
    }

    // MARK: - Order Book Depth Calculations
    /// Calculates the normalized depth width for a given order book entry.
    /// Used for both bid and ask depth bars.
    private func calculateDepth(_ entry: OrderBookViewModel.OrderBookEntry, maxV: Double, cumulativeValue: Double? = nil) -> CGFloat {
        let value: Double = {
            if depthMode == .cumulative, let cumVal = cumulativeValue {
                return cumVal
            }
            let p = Double(entry.price) ?? 0
            let q = Double(entry.qty) ?? 0
            return depthMode == .qty ? q : (p * q)
        }()
        let clampedMax = max(maxV, 0.0001)  // Prevent division by very small numbers
        
        // Use log scale for better visibility of small orders (common in Qty mode)
        // This ensures even tiny orders show a meaningful bar
        let minV = clampedMax * 0.001  // 0.1% of max gets minimum visible width
        let v = max(value, minV)
        let scaled = log(v) - log(minV)
        let denom = log(clampedMax) - log(minV)
        let norm = denom > 0 ? CGFloat(scaled / denom) : 0.1
        
        // Minimum 10% width so all orders are visible, max 100%
        return min(max(norm, 0.10), 1.0)
    }
    
    // MARK: - Buy/Sell Pressure Imbalance Bar (Binance-style) with Spread
    private var imbalanceBar: some View {
        let isDark = colorScheme == .dark
        let buyPct = viewModel.buyPressurePercent
        let isLoading = viewModel.isLoading && viewModel.bids.isEmpty && viewModel.asks.isEmpty
        
        // Spread text for center - use formatSpreadDisplay for better small value handling
        let spreadText: String = {
            if isLoading { return "—" }
            return formatSpreadDisplay(spreadAbs)
        }()
        
        return GeometryReader { geo in
            let width = geo.size.width
            let buyWidth = isLoading ? width * 0.5 : width * CGFloat(buyPct / 100)
            
            ZStack(alignment: .leading) {
                // Ask (sell) side - full width background
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Colors.ask.opacity(isDark ? 0.35 : 0.25))
                
                // Bid (buy) side - proportional width
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Colors.bid.opacity(isDark ? 0.5 : 0.4))
                    .frame(width: buyWidth)
                
                // Labels: Buy % | Spread | Sell %
                HStack {
                    Text(isLoading ? "—" : String(format: "%.0f%%", buyPct))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DS.Colors.bid)
                        .padding(.leading, 4)
                    
                    Spacer()
                    
                    // Spread in center
                    Text(spreadText)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.6))
                    
                    Spacer()
                    
                    Text(isLoading ? "—" : String(format: "%.0f%%", 100 - buyPct))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DS.Colors.ask)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(height: DS.Spacing.orderBookImbalanceHeight)
    }
    
    // MARK: - Compact Header (spread now in imbalance bar)
    private func compactHeaderWithSpread(colWidth: CGFloat, spreadWidth: CGFloat) -> some View {
        let isDark = colorScheme == .dark
        let dimColor = isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.4)
        
        // Column headers aligned with data columns
        return HStack(spacing: 0) {
            // Bids column header
            HStack(spacing: 0) {
                Text("Price")
                    .foregroundColor(DS.Colors.bid.opacity(0.7))
                Spacer(minLength: 2)
                Text("Size")
                    .foregroundColor(dimColor)
            }
            .frame(width: colWidth)
            
            // Thin divider space (matches data rows)
            Spacer()
                .frame(width: spreadWidth)
            
            // Asks column header
            HStack(spacing: 0) {
                Text("Price")
                    .foregroundColor(DS.Colors.ask.opacity(0.7))
                Spacer(minLength: 2)
                Text("Size")
                    .foregroundColor(dimColor)
            }
            .frame(width: colWidth)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .padding(.vertical, 5)
    }
    
    // MARK: - UI Subviews
    private func bidsColumn(width: CGFloat) -> some View {
        let bids = paddedBids  // Use padded data to always fill rows
        let realBidsCount = groupedBids.count
        let cumDepths = bidCumulativeDepths
        let maxCumDepth = cumDepths.last ?? 1
        let localMax = depthMode == .cumulative ? maxCumDepth : max(bidMaxEMA, 1)
        
        return LazyVStack(alignment: .leading, spacing: DS.Spacing.orderBookRowSpacing) {
            // Use index-based IDs for stable row positions (prevents shuffling animation)
            ForEach(Array(bids.prefix(displayedOrderBookRows).enumerated()), id: \.offset) { index, bid in
                let isExtrapolated = index >= realBidsCount
                let cumValue = index < cumDepths.count ? cumDepths[index] : nil
                let depthVal = isExtrapolated ? 0.05 : calculateDepth(bid, maxV: localMax, cumulativeValue: cumValue)
                let clampedW = max(min(width * depthVal, width * 0.98), 6)

                bidRow(bid: bid, width: width, depthWidth: clampedW, isBest: index == 0, isHighlighted: highlightedBids.contains(bid.price), isExtrapolated: isExtrapolated)
            }
        }
        // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
        .animation(.easeInOut(duration: 0.15), value: displayedOrderBookRows)
    }

    private func asksColumn(width: CGFloat) -> some View {
        let asks = paddedAsks  // Use padded data to always fill rows
        let realAsksCount = groupedAsks.count
        let cumDepths = askCumulativeDepths
        let maxCumDepth = cumDepths.last ?? 1
        let localMax = depthMode == .cumulative ? maxCumDepth : max(askMaxEMA, 1)
        
        return LazyVStack(alignment: .leading, spacing: DS.Spacing.orderBookRowSpacing) {
            // Use index-based IDs for stable row positions (prevents shuffling animation)
            ForEach(Array(asks.prefix(displayedOrderBookRows).enumerated()), id: \.offset) { index, ask in
                let isExtrapolated = index >= realAsksCount
                let cumValue = index < cumDepths.count ? cumDepths[index] : nil
                let depthVal = isExtrapolated ? 0.05 : calculateDepth(ask, maxV: localMax, cumulativeValue: cumValue)
                let clampedW = max(min(width * depthVal, width * 0.98), 6)

                askRow(ask: ask, width: width, depthWidth: clampedW, isBest: index == 0, isHighlighted: highlightedAsks.contains(ask.price), isExtrapolated: isExtrapolated)
            }
        }
        // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
        .animation(.easeInOut(duration: 0.15), value: displayedOrderBookRows)
    }
    
    // MARK: - Row Views (Professional Style)
    private func bidRow(bid: OrderBookViewModel.OrderBookEntry, width: CGFloat, depthWidth: CGFloat, isBest: Bool = false, isHighlighted: Bool = false, isExtrapolated: Bool = false) -> some View {
        let isDark = colorScheme == .dark
        // Extrapolated rows are slightly dimmed to indicate thin/no liquidity
        let dimFactor: Double = isExtrapolated ? 0.5 : 1.0
        let qtyColor = isDark ? Color.white.opacity(0.65 * dimFactor) : Color.black.opacity(0.6 * dimFactor)
        
        let depthOpacity = isBest
            ? (isDark ? DS.OrderBook.depthOpacityBestDark : DS.OrderBook.depthOpacityBestLight)
            : (isDark ? DS.OrderBook.depthOpacityDark : DS.OrderBook.depthOpacityLight)
        
        // Highlight flash opacity - subtle like Binance
        let highlightOpacity = isHighlighted ? (isDark ? 0.12 : 0.08) : 0.0
        
        return ZStack(alignment: .leading) {
            // Background flash for price changes (Binance/Coinbase style)
            RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                .fill(DS.Colors.bid.opacity(highlightOpacity))
                .animation(.easeOut(duration: 0.15), value: isHighlighted)
            
            // Depth bar with gradient (fades to right)
            RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            DS.Colors.bid.opacity(depthOpacity * dimFactor),
                            DS.Colors.bid.opacity(depthOpacity * 0.35 * dimFactor)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: depthWidth, height: DS.Spacing.orderBookRowHeight - 1)
                // Instant updates like Binance - no spring animation for professional feel
            
            // Content
            HStack(spacing: 0) {
                Text(formatUSD(Double(bid.price) ?? 0))
                    .font(DS.Fonts.orderBookPrice)
                    .fontWeight(isBest ? .semibold : .medium)
                    .foregroundColor(DS.Colors.bid.opacity(dimFactor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(formatQty(bid.qty))
                    .font(DS.Fonts.orderBookQty)
                    .foregroundColor(qtyColor)
                    .lineLimit(1)
            }
            .monospacedDigit()
        }
        .frame(width: width, height: DS.Spacing.orderBookRowHeight)
        .background(
            isBest
                ? RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                    .fill(DS.Colors.bid.opacity(isDark ? DS.OrderBook.bestRowBgDark : DS.OrderBook.bestRowBgLight))
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isExtrapolated { onSelectPrice(bid.price) } }
    }
    
    private func askRow(ask: OrderBookViewModel.OrderBookEntry, width: CGFloat, depthWidth: CGFloat, isBest: Bool = false, isHighlighted: Bool = false, isExtrapolated: Bool = false) -> some View {
        let isDark = colorScheme == .dark
        // Extrapolated rows are slightly dimmed to indicate thin/no liquidity
        let dimFactor: Double = isExtrapolated ? 0.5 : 1.0
        let qtyColor = isDark ? Color.white.opacity(0.65 * dimFactor) : Color.black.opacity(0.6 * dimFactor)
        
        let depthOpacity = isBest
            ? (isDark ? DS.OrderBook.depthOpacityBestDark : DS.OrderBook.depthOpacityBestLight)
            : (isDark ? DS.OrderBook.depthOpacityDark : DS.OrderBook.depthOpacityLight)
        
        // Highlight flash opacity - subtle like Binance
        let highlightOpacity = isHighlighted ? (isDark ? 0.12 : 0.08) : 0.0
        
        return ZStack(alignment: .trailing) {
            // Background flash for price changes (Binance/Coinbase style)
            RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                .fill(DS.Colors.ask.opacity(highlightOpacity))
                .animation(.easeOut(duration: 0.15), value: isHighlighted)
            
            // Depth bar with gradient (fades to left)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Colors.ask.opacity(depthOpacity * 0.35 * dimFactor),
                                DS.Colors.ask.opacity(depthOpacity * dimFactor)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: depthWidth, height: DS.Spacing.orderBookRowHeight - 1)
                    // Instant updates like Binance - no spring animation for professional feel
            }
            
            // Content
            HStack(spacing: 0) {
                Text(formatUSD(Double(ask.price) ?? 0))
                    .font(DS.Fonts.orderBookPrice)
                    .fontWeight(isBest ? .semibold : .medium)
                    .foregroundColor(DS.Colors.ask.opacity(dimFactor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(formatQty(ask.qty))
                    .font(DS.Fonts.orderBookQty)
                    .foregroundColor(qtyColor)
                    .lineLimit(1)
            }
            .monospacedDigit()
        }
        .frame(width: width, height: DS.Spacing.orderBookRowHeight)
        .background(
            isBest
                ? RoundedRectangle(cornerRadius: DS.OrderBook.depthBarRadius)
                    .fill(DS.Colors.ask.opacity(isDark ? DS.OrderBook.bestRowBgDark : DS.OrderBook.bestRowBgLight))
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isExtrapolated { onSelectPrice(ask.price) } }
    }

    // MARK: - Depth Mode Toggle (Compact)
    private var depthModeToggle: some View {
        let isDark = colorScheme == .dark
        let bgColor = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        
        return HStack(spacing: 1) {
            ForEach(DepthMode.allCases, id: \.self) { mode in
                depthModeButton(mode: mode, isDark: isDark)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))
    }
    
    private func depthModeButton(mode: DepthMode, isDark: Bool) -> some View {
        let isSelected = depthMode == mode
        // Qty = Order size (default), Val = Dollar value, Sum = Cumulative depth
        let label = mode == .qty ? "Qty" : (mode == .notional ? "Val" : "Sum")
        let textColor: Color = isSelected 
            ? (isDark ? Color(white: 0.1) : .white) 
            : (isDark ? .white.opacity(0.45) : .black.opacity(0.35))
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { depthMode = mode }
        }) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .foregroundColor(textColor)
                .background(selectedButtonBackground(isSelected: isSelected, isDark: isDark))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Price Grouping Picker (Compact)
    private var priceGroupingPicker: some View {
        let isDark = colorScheme == .dark
        let bgColor = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        
        return HStack(spacing: 1) {
            ForEach(PriceGrouping.allCases) { group in
                priceGroupingButton(group: group, isDark: isDark)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))
    }
    
    private func priceGroupingButton(group: PriceGrouping, isDark: Bool) -> some View {
        let isSelected = priceGrouping == group
        let textColor: Color = isSelected 
            ? (isDark ? Color(white: 0.1) : .white) 
            : (isDark ? .white.opacity(0.45) : .black.opacity(0.35))
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { priceGrouping = group }
        }) {
            Text(group.displayLabel)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
                .foregroundColor(textColor)
                .background(selectedButtonBackground(isSelected: isSelected, isDark: isDark))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func selectedButtonBackground(isSelected: Bool, isDark: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 5)
                .fill(AdaptiveGradients.chipGold(isDark: isDark))
        } else {
            Color.clear
        }
    }
    
    // MARK: - Bottom Controls Row (Compact)
    private var bottomControlsRow: some View {
        HStack(spacing: 8) {
            viewModeToggle
            Spacer()
            priceGroupingPicker
            depthModeToggle
        }
    }
    
    // MARK: - View Mode Toggle (Table/Chart)
    private var viewModeToggle: some View {
        let isDark = colorScheme == .dark
        let bgColor = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        
        return HStack(spacing: 1) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { showDepthChart = false }
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 26, height: 22)
                    .foregroundColor(!showDepthChart ? (isDark ? Color(white: 0.1) : .white) : (isDark ? .white.opacity(0.4) : .black.opacity(0.3)))
                    .background(selectedButtonBackground(isSelected: !showDepthChart, isDark: isDark))
            }
            .buttonStyle(.plain)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { showDepthChart = true }
            }) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 26, height: 22)
                    .foregroundColor(showDepthChart ? (isDark ? Color(white: 0.1) : .white) : (isDark ? .white.opacity(0.4) : .black.opacity(0.3)))
                    .background(selectedButtonBackground(isSelected: showDepthChart, isDark: isDark))
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))
    }

    
    // MARK: - Body
    var body: some View {
        let isDark = colorScheme == .dark
        
        return VStack(alignment: .leading, spacing: 0) {
            // Content area: table or depth chart
            if showDepthChart {
                OrderBookDepthChartView(viewModel: viewModel, height: 180)
                    .padding(.vertical, 4)
            } else {
                // Calculate height based on actual row count
                let rowHeight = DS.Spacing.orderBookRowHeight + DS.Spacing.orderBookRowSpacing
                let headerHeight: CGFloat = 26
                let imbalanceHeight: CGFloat = showImbalanceBar ? (DS.Spacing.orderBookImbalanceHeight + 8) : 0
                let contentHeight = CGFloat(displayedOrderBookRows) * rowHeight
                let depthHeight = contentHeight + headerHeight + imbalanceHeight + 2

                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    // Tight Binance-style layout: thin divider between bid/ask columns
                    let dividerWidth: CGFloat = 8  // Thin divider only
                    let colWidth = (totalWidth - dividerWidth) / 2

                    VStack(spacing: 0) {
                        // Buy/Sell pressure indicator (Binance-style)
                        if showImbalanceBar {
                            imbalanceBar
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                        
                        // Header row - uses same column width as data for alignment
                        compactHeaderWithSpread(colWidth: colWidth, spreadWidth: dividerWidth)
                        
                        // Subtle separator
                        Rectangle()
                            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                            .frame(height: 0.5)
                        
                        // Order book data - tight layout with thin divider
                        HStack(alignment: .top, spacing: 0) {
                            bidsColumn(width: colWidth)
                                .frame(width: colWidth, height: contentHeight, alignment: .top)
                            
                            // Thin visual divider between bids and asks
                            Rectangle()
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                .frame(width: 1)
                                .padding(.horizontal, (dividerWidth - 1) / 2)
                            
                            asksColumn(width: colWidth)
                                .frame(width: colWidth, height: contentHeight, alignment: .top)
                        }
                        .padding(.top, 2)
                        
                        Spacer(minLength: 0)
                    }
                }
                .clipped()
                .frame(height: depthHeight)
            }
            
            // Bottom controls
            bottomControlsRow
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .transaction { $0.animation = nil }
        .onReceive(
            Publishers.CombineLatest(viewModel.$bids, viewModel.$asks)
                .throttle(for: .milliseconds(66), scheduler: RunLoop.main, latest: true)  // ~15Hz for responsive updates
        ) { newBids, newAsks in
            // Already on main thread via RunLoop.main scheduler - no extra dispatch needed
            let topBids = newBids.prefix(8)
            let changedBidPrices = topBids.compactMap { entry in
                if let oldQty = previousBidMap[entry.price] { return oldQty != entry.qty ? entry.price : nil }
                else { return entry.price }
            }
            previousBidMap = Dictionary(uniqueKeysWithValues: topBids.map { ($0.price, $0.qty) })

            let topAsks = newAsks.prefix(8)
            let changedAskPrices = topAsks.compactMap { entry in
                if let oldQty = previousAskMap[entry.price] { return oldQty != entry.qty ? entry.price : nil }
                else { return entry.price }
            }
            previousAskMap = Dictionary(uniqueKeysWithValues: topAsks.map { ($0.price, $0.qty) })

            // Update EMA of depth maxima from latest data
            let rawBidMax = newBids.prefix(displayedOrderBookRows).compactMap { entry -> Double? in
                guard let p = Double(entry.price), let q = Double(entry.qty) else { return nil }
                return p * q
            }.max() ?? 1
            let rawAskMax = newAsks.prefix(displayedOrderBookRows).compactMap { entry -> Double? in
                guard let p = Double(entry.price), let q = Double(entry.qty) else { return nil }
                return p * q
            }.max() ?? 1
            // Higher alpha = more responsive to changes, less smoothing jitter
            let alpha = isActiveTab ? 0.5 : 0.3
            if bidMaxEMA <= 0 { bidMaxEMA = rawBidMax } else { bidMaxEMA = alpha * rawBidMax + (1 - alpha) * bidMaxEMA }
            if askMaxEMA <= 0 { askMaxEMA = rawAskMax } else { askMaxEMA = alpha * rawAskMax + (1 - alpha) * askMaxEMA }

            if isActiveTab && (!changedBidPrices.isEmpty || !changedAskPrices.isEmpty) {
                // Fast, subtle flash like Binance/Coinbase - 250ms total
                withAnimation(.easeIn(duration: 0.1)) {
                    highlightedBids = Set(changedBidPrices)
                    highlightedAsks = Set(changedAskPrices)
                }
                // Quick fade out for professional feel
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        highlightedBids.removeAll()
                        highlightedAsks.removeAll()
                    }
                }
            } else if !isActiveTab {
                highlightedBids.removeAll()
                highlightedAsks.removeAll()
            }
        }
    }

    // MARK: - Helpers
    private func formatPriceWithCommas(_ value: Double) -> String { formatUSD(value) }
}

